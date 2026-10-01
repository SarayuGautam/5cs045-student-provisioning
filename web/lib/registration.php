<?php
declare(strict_types=1);

// Shared by the sign-up page (index.php), register_handler.php and confirm_handler.php.
//
// Signing up takes two steps, so an account is only ever made for a mailbox that exists and
// belongs to the person signing up:
//   1. register_handler.php checks the email and sends a one-time link to it. Nothing is created.
//   2. The link opens the sign-up page, which asks the student to click "Create my account". Only
//      then does confirm_handler.php create the account and email the password.
// Sending an email proves nothing on its own: mail servers often accept a message for an address
// that does not exist and only bounce it later. Only someone who can read the mailbox gets the link.
// Step 2 is a button, not the link itself, because some mail scanners open every link they see.

require_once __DIR__ . '/smtp_mailer.php';
require_once __DIR__ . '/credentials.php';

const LOG_FILE = '/var/log/5cs045-registration.log';
const RATE_LIMIT_DIR = '/var/lib/5cs045-ratelimit';
const LOCK_DIR = '/var/lib/5cs045-registration-locks';
const REGISTRY_DIR = '/var/lib/5cs045-registrations';
const SIGNUP_LINK_DIR = '/var/lib/5cs045-signup-links';
const RATE_LIMIT_SECONDS = 300;
const SIGNUP_LINK_SECONDS = 3600;
// Used when smtp_config.php has no signup_url
const DEFAULT_SIGNUP_URL = 'https://fullstack.heraldcollege.edu.np';

const SIGNUP_LINK_EXPIRED = 'This link has expired. Type your email again to get a new one.';
const SIGNUP_LINK_NOT_VALID = 'This link is not valid, or it has already been used. If you have already created your account, your password is in your email. If not, type your email again to get a new link.';

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

// Lets one request at a time work on an email, and with $rateLimit only one every
// RATE_LIMIT_SECONDS. Returns false when the email is busy or was tried too recently.
// The lock is released when the request ends, however it ends: respond_and_redirect() exits,
// and exit skips `finally` blocks, which used to leave locks behind for two minutes.
function acquire_request_lock(string $email, bool $rateLimit = true): bool {
    @mkdir(RATE_LIMIT_DIR, 0700, true);
    @mkdir(LOCK_DIR, 0700, true);
    $key = registration_key($email);
    $rateFile = RATE_LIMIT_DIR . '/' . $key;
    $lockPath = LOCK_DIR . '/' . $key;
    $now = time();
    if ($rateLimit && is_file($rateFile) && ($now - (int) @file_get_contents($rateFile)) < RATE_LIMIT_SECONDS) {
        return false;
    }
    // A lock older than two minutes belongs to a request that crashed. Remove it.
    if (is_dir($lockPath) && ($now - (int) @filemtime($lockPath)) > 120) {
        @rmdir($lockPath);
    }
    if (!@mkdir($lockPath, 0700)) {
        return false;
    }
    register_shutdown_function(static function () use ($lockPath): void {
        @rmdir($lockPath);
    });
    if ($rateLimit) {
        if (@file_put_contents($rateFile, (string) $now, LOCK_EX) === false) {
            return false;
        }
        @chmod($rateFile, 0600);
    }
    return true;
}

// Lets the email be tried again straight away, for when the attempt failed on our side.
function forget_recent_request(string $email): void {
    @unlink(RATE_LIMIT_DIR . '/' . registration_key($email));
}

// The sign-up page's address, for the link in the email. It comes from the settings and never from
// the request, so a forged Host header cannot point a student's link at someone else's website.
function signup_url(array $smtp): string {
    return configured_url($smtp, 'signup_url', DEFAULT_SIGNUP_URL);
}

function smtp_mailer(array $smtp): SmtpMailer {
    return new SmtpMailer(
        host: (string) $smtp['host'],
        port: (int) $smtp['port'],
        username: (string) $smtp['username'],
        password: (string) $smtp['password'],
        fromAddress: (string) $smtp['from_address'],
        fromName: (string) $smtp['from_name'],
        useStartTls: (bool) $smtp['use_starttls'],
    );
}

// A sign-up link carries a random token. Only a hash of it is stored (as the file name), so the
// saved files cannot be turned back into working links.
function signup_link_path(string $token): ?string {
    return preg_match('/^[0-9a-f]{64}$/', $token) ? SIGNUP_LINK_DIR . '/' . hash('sha256', $token) : null;
}

function create_signup_link(string $email, string $username): string {
    $token = bin2hex(random_bytes(32));
    $path = signup_link_path($token);
    $record = json_encode([
        'email' => $email,
        'username' => $username,
        'expires' => time() + SIGNUP_LINK_SECONDS,
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    if ($record === false || @file_put_contents($path, $record, LOCK_EX) === false) {
        throw new RuntimeException('Could not save the sign-up link in ' . SIGNUP_LINK_DIR);
    }
    @chmod($path, 0600);
    return $token;
}

// The email and username a link was made for. Null if the link is unknown, used up or out of
// date; $expired tells the last one apart, so the page can say so.
function find_signup_link(string $token, ?bool &$expired = null): ?array {
    $expired = false;
    $path = signup_link_path($token);
    $raw = $path === null ? false : @file_get_contents($path);
    $record = $raw === false ? null : json_decode($raw, true);
    if (!is_array($record) || !is_string($record['email'] ?? null) || !is_string($record['username'] ?? null)) {
        return null;
    }
    if ((int) ($record['expires'] ?? 0) < time()) {
        $expired = true;
        return null;
    }
    return $record;
}

function delete_signup_link(string $token): void {
    $path = signup_link_path($token);
    if ($path !== null) {
        @unlink($path);
    }
}

// Links nobody used are deleted a day after they expire (until then the page can still say
// "expired" rather than "not valid").
function prune_signup_links(): void {
    $cutoff = time() - SIGNUP_LINK_SECONDS - 86400;
    foreach (glob(SIGNUP_LINK_DIR . '/*') ?: [] as $file) {
        if ((int) @filemtime($file) < $cutoff) {
            @unlink($file);
        }
    }
}
