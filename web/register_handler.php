<?php
declare(strict_types=1);

// Sign-up, step 1: check the email and send it a one-time link. Nothing is created here. The
// account is made by confirm_handler.php, once the link has been opened (see lib/registration.php).

session_set_cookie_params([
    'secure' => true,
    'httponly' => true,
    'samesite' => 'Strict',
]);
session_start();

require __DIR__ . '/lib/credentials.php';
require __DIR__ . '/lib/registration.php';
$smtp = require '/etc/5cs045/smtp_config.php';

// The per-email limit stops one address from being spammed, but does
// nothing to stop one visitor from working through many different
// (real or guessed) addresses in a row, each one sent a link.
// This caps that per source IP.
// The limit is deliberately generous: a whole class can be behind the same
// campus NAT during a lab session, and that is normal, legitimate traffic.
const IP_RATE_LIMIT_DIR = '/var/lib/5cs045-ip-ratelimit';
const IP_RATE_LIMIT_MAX_ATTEMPTS = 40;
const IP_RATE_LIMIT_WINDOW_SECONDS = 900; // 15 minutes

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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond_and_redirect(false, 'Please use the form to register.');
}

$csrf = (string) ($_POST['csrf_token'] ?? '');
if (!hash_equals((string) ($_SESSION['register_csrf'] ?? ''), $csrf)) {
    audit_log('REJECTED invalid CSRF token');
    respond_and_redirect(false, 'The form expired. Please try again.');
}

$fullName = trim((string) ($_POST['full_name'] ?? ''));
if ($fullName === '') {
    respond_and_redirect(false, 'Please enter your full name.');
}
if (mb_strlen($fullName, 'UTF-8') > 100) {
    respond_and_redirect(false, 'Your name must be 100 characters or fewer.');
}
if (preg_match('/[\x00-\x1F\x7F]/', $fullName)) {
    respond_and_redirect(false, 'Please enter your name without control characters.');
}

$fullName = trim((string) ($_POST['full_name'] ?? ''));
if ($fullName === '') {
    respond_and_redirect(false, 'Please enter your full name.');
}
if (mb_strlen($fullName, 'UTF-8') > 100) {
    respond_and_redirect(false, 'Your name must be 100 characters or fewer.');
}
if (preg_match('/[\x00-\x1F\x7F]/', $fullName)) {
    respond_and_redirect(false, 'Please enter your name without control characters.');
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

if (!acquire_request_lock($email)) {
    respond_and_redirect(false, 'A link was sent to this email in the last 5 minutes. Check your inbox and Spam, or try again in a few minutes.');
}

prune_signup_links();
try {
    $token = create_signup_link($email, $username, $fullName);
} catch (Throwable $e) {
    forget_recent_request($email);
    audit_log('FAILURE ' . $e->getMessage());
    respond_and_redirect(false, 'Something went wrong. Please contact your tutor.');
}

try {
    smtp_mailer($smtp)->send($email, 'Confirm your server account',
        signup_link_email_body($username, signup_url($smtp) . '/?confirm=' . $token));
} catch (Throwable $e) {
    // Nothing was created, so the student can simply try again
    delete_signup_link($token);
    forget_recent_request($email);
    audit_log("LINK EMAIL FAILED for {$email}: " . $e->getMessage());
    respond_and_redirect(false, "We could not send an email to {$email}, so no account was made. Check the address and try again, or contact your tutor if it keeps happening.");
}

audit_log("link sent username={$username} email={$email}");
respond_and_redirect(true, "Almost done. Open the link we have emailed to {$email} within 1 hour to create your account. If it is not in your inbox, check Spam.");
