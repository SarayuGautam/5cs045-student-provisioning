<?php
declare(strict_types=1);

session_set_cookie_params([
    'secure' => true,
    'httponly' => true,
    'samesite' => 'Strict',
]);
session_start();

require __DIR__ . '/lib/smtp_mailer.php';
require __DIR__ . '/lib/credentials.php';
$smtp = require '/etc/5cs045/smtp_config.php';

const ADD_STUDENT_SCRIPT = '/usr/local/sbin/5cs045/bin/add-student.sh';
const LOG_FILE = '/var/log/5cs045-registration.log';
const RATE_LIMIT_DIR = '/var/lib/5cs045-ratelimit';
const LOCK_DIR = '/var/lib/5cs045-registration-locks';
const REGISTRY_DIR = '/var/lib/5cs045-registrations';
const RATE_LIMIT_SECONDS = 300;

// The per-email lock above stops one address from being spammed, but does
// nothing to stop one visitor from working through many different
// (real or guessed) addresses in a row - each one still fully provisions a
// Linux account, database and PHP-FPM pool. This caps that per source IP.
// The limit is deliberately generous: a whole class can be behind the same
// campus NAT during a lab session, and that is normal, legitimate traffic.
const IP_RATE_LIMIT_DIR = '/var/lib/5cs045-ip-ratelimit';
const IP_RATE_LIMIT_MAX_ATTEMPTS = 40;
const IP_RATE_LIMIT_WINDOW_SECONDS = 900; // 15 minutes

function respond_and_redirect(bool $ok, string $message): never {
    $_SESSION['register_result'] = ['ok' => $ok, 'message' => $message];
    header('Location: /', true, 303);
    exit;
}

function audit_log(string $line): void {
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    @file_put_contents(LOG_FILE, sprintf("[%s] [%s] %s\n", date('c'), $ip, $line), FILE_APPEND | LOCK_EX);
}

function already_registered(string $email): bool {
    return is_file(REGISTRY_DIR . '/' . registration_key($email));
}

function mark_registered(string $email, string $username, string $status = 'complete'): void {
    @mkdir(REGISTRY_DIR, 0700, true);
    $path = REGISTRY_DIR . '/' . registration_key($email);
    $content = json_encode([
        'username' => $username,
        'registered_at' => date(DATE_ATOM),
        'status' => $status,
        'email' => strtolower($email),
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    if ($content === false || @file_put_contents($path, $content, LOCK_EX) === false) {
        throw new RuntimeException('Could not record the registration.');
    }
    @chmod($path, 0600);
}

function id_exists(string $username): bool {
    exec('id ' . escapeshellarg($username) . ' >/dev/null 2>&1', $unused, $code);
    return $code === 0;
}

// Returns true if this IP has already made IP_RATE_LIMIT_MAX_ATTEMPTS (or
// more) registration attempts within the trailing window, and records this
// attempt either way. Keyed by IP, not email, so it catches a single source
// working through many different addresses - something the per-email lock
// cannot see.
function ip_rate_limited(string $ip): bool {
    if ($ip === '' || $ip === 'unknown') {
        // No usable IP to key on (e.g. REMOTE_ADDR missing) - fail open
        // rather than block legitimate traffic on a value we don't have.
        return false;
    }
    @mkdir(IP_RATE_LIMIT_DIR, 0700, true);
    $file = IP_RATE_LIMIT_DIR . '/' . hash('sha256', $ip);
    $now = time();

    $attempts = [];
    $raw = @file_get_contents($file);
    if ($raw !== false && $raw !== '') {
        foreach (explode("\n", trim($raw)) as $line) {
            $t = (int) $line;
            if ($t > 0 && ($now - $t) < IP_RATE_LIMIT_WINDOW_SECONDS) {
                $attempts[] = $t;
            }
        }
    }

    if (count($attempts) >= IP_RATE_LIMIT_MAX_ATTEMPTS) {
        return true;
    }

    $attempts[] = $now;
    @file_put_contents($file, implode("\n", $attempts), LOCK_EX);
    @chmod($file, 0600);
    return false;
}

function acquire_request_lock(string $email): ?string {
    @mkdir(RATE_LIMIT_DIR, 0700, true);
    @mkdir(LOCK_DIR, 0700, true);
    $key = registration_key($email);
    $rateFile = RATE_LIMIT_DIR . '/' . $key;
    $lockPath = LOCK_DIR . '/' . $key;
    $now = time();
    if (is_file($rateFile)) {
        $last = (int) @file_get_contents($rateFile);
        if (($now - $last) < RATE_LIMIT_SECONDS) {
            return null;
        }
    }
    // A lock older than two minutes belongs to a request that crashed. Remove it.
    if (is_dir($lockPath) && (time() - (int) @filemtime($lockPath)) > 120) {
        @rmdir($lockPath);
    }
    if (!@mkdir($lockPath, 0700)) {
        return null;
    }
    if (@file_put_contents($rateFile, (string) $now, LOCK_EX) === false) {
        @rmdir($lockPath);
        return null;
    }
    @chmod($rateFile, 0600);
    return $lockPath;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond_and_redirect(false, 'Please use the form to register.');
}

$csrf = (string) ($_POST['csrf_token'] ?? '');
if (!hash_equals((string) ($_SESSION['register_csrf'] ?? ''), $csrf)) {
    audit_log('REJECTED invalid CSRF token');
    respond_and_redirect(false, 'The form expired. Please try again.');
}

$email = strtolower(trim((string) ($_POST['email'] ?? '')));
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    respond_and_redirect(false, 'Please enter a valid college email.');
}

$allowedDomain = trim((string) ($smtp['allowed_email_domain'] ?? ''));
if ($allowedDomain !== '') {
    $domain = substr($email, strrpos($email, '@') + 1);
    if (strcasecmp($domain, $allowedDomain) !== 0) {
        audit_log("REJECTED wrong domain: {$email}");
        respond_and_redirect(false, "Please use your @{$allowedDomain} college email.");
    }
}

// name+1@ reaches the same inbox as name@, so it would give one student a second account
if (!is_plain_address($email)) {
    audit_log("REJECTED not a plain address: {$email}");
    respond_and_redirect(false, 'Please type your college email exactly as it is, with nothing added to it (no + part).');
}

$username = derive_username($email);
if ($username === null) {
    audit_log("REJECTED invalid username derived from {$email}");
    respond_and_redirect(false, 'That email cannot be used for a server account. Please contact your tutor.');
}

if (already_registered($email)) {
    respond_and_redirect(false, 'This email has already been registered. Please contact your tutor if you need a password reset.');
}

if (id_exists($username)) {
    respond_and_redirect(false, 'An account already exists for this student. Please contact your tutor.');
}

$clientIp = (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
if (ip_rate_limited($clientIp)) {
    audit_log("REJECTED ip rate limit ip={$clientIp} email={$email}");
    respond_and_redirect(false, 'Too many registration attempts from this network. Please wait a while and try again, or contact your tutor.');
}

$lockPath = acquire_request_lock($email);
if ($lockPath === null) {
    respond_and_redirect(false, 'Please wait a few minutes before trying this email again.');
}

try {
    $cmd = sprintf(
        'sudo -n %s -d -u %s 2>&1',
        escapeshellarg(ADD_STUDENT_SCRIPT),
        escapeshellarg($username)
    );
    exec($cmd, $outputLines, $exitCode);
    $output = implode("\n", $outputLines);
    audit_log("provision username={$username} email={$email} exit={$exitCode}");

    if ($exitCode !== 0) {
        audit_log("FAILURE detail: {$output}");
        respond_and_redirect(false, 'Something went wrong. Please contact your tutor.');
    }

    if (!preg_match('/^Password:\s+(\S+)/m', $output, $m)) {
        audit_log("FAILURE could not parse password for {$username}");
        respond_and_redirect(false, 'Your account was created, but we could not prepare your email. Please contact your tutor.');
    }

    $password = $m[1];
    $serverUrl = (string) ($smtp['server_url'] ?? '');
    if ($serverUrl === '') {
        throw new RuntimeException('server_url is not configured');
    }

    // Mark the email as taken before sending, so a second click cannot create it again.
    mark_registered($email, $username, 'pending');

    $body = credentials_email_body($username, $password, $serverUrl);

    try {
        $mailer = new SmtpMailer(
            host: (string) $smtp['host'],
            port: (int) $smtp['port'],
            username: (string) $smtp['username'],
            password: (string) $smtp['password'],
            fromAddress: (string) $smtp['from_address'],
            fromName: (string) $smtp['from_name'],
            useStartTls: (bool) $smtp['use_starttls'],
        );
        $mailer->send($email, 'Your Server Credentials', $body);
    } catch (Throwable $e) {
        @unlink(REGISTRY_DIR . '/' . registration_key($email));
        audit_log("EMAIL SEND FAILED for {$username}: " . $e->getMessage());
        respond_and_redirect(false, 'Your account was created, but we could not send the email. Please contact your tutor for your password.');
    }

    mark_registered($email, $username, 'complete');
    audit_log("registered username={$username} email={$email}");
    respond_and_redirect(true, "Your account is ready. Check {$email} for your server details.");
} finally {
    @rmdir($lockPath);
}
