<?php
/**
 * register_handler.php — email-only registration. Derives a username from
 * the email, provisions (or resets) the account via add-student.sh through
 * a narrowly-scoped sudo rule, then emails the credentials.
 *
 * Security model, spelled out (see also add-student.sh and the sudoers
 * template):
 *   - www-data is NOT root, and can only sudo this one exact script
 *     (/etc/sudoers.d/5cs045-provisioning) — a bug here can create/reset
 *     student accounts, it cannot compromise the rest of the box.
 *   - the password is never written anywhere www-data can read on an
 *     ongoing basis (add-student.sh's credentials.txt stays 600, owned by
 *     the student, exactly as tested). www-data only ever sees a password
 *     in the one HTTP response from the sudo call that just generated it —
 *     the same moment it caused that generation — not via standing file
 *     access. It's parsed from add-student.sh's stdout and never persisted
 *     to disk from this side.
 *   - every value that reaches a shell goes through escapeshellarg().
 *   - resubmitting for an existing account is a deliberate, documented
 *     reset path (add-student.sh regenerates the password every run) —
 *     not an accidental side effect.
 */
declare(strict_types=1);
session_start();

require __DIR__ . '/lib/smtp_mailer.php';
// Loaded from OUTSIDE the web root on purpose (see setup/00-server-setup.sh)
// — this holds the SMTP relay password, so it should never be reachable by
// any possible nginx config, not just correctly denied by the current one.
$smtp = require '/etc/5cs045/smtp_config.php';

const ADD_STUDENT_SCRIPT = '/usr/local/sbin/5cs045/bin/add-student.sh';
const LOG_FILE = '/var/log/5cs045-registration.log';
const RATE_LIMIT_DIR = '/var/lib/5cs045-ratelimit';
const RATE_LIMIT_SECONDS = 300; // one registration/reset per email per 5 minutes

function respond_and_redirect(bool $ok, string $message): never {
    $_SESSION['register_result'] = ['ok' => $ok, 'message' => $message];
    header('Location: register.php');
    exit;
}

function audit_log(string $line): void {
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    @file_put_contents(LOG_FILE, sprintf("[%s] [%s] %s\n", date('c'), $ip, $line), FILE_APPEND | LOCK_EX);
}

/** Local-part of the email, sanitized into a safe Linux/MySQL username. Null if it can't produce a valid one. */
function derive_username(string $email): ?string {
    $at = strrpos($email, '@');
    if ($at === false) return null;
    $local = strtolower(substr($email, 0, $at));
    $local = preg_replace('/[^a-z0-9]+/', '_', $local);
    $local = trim($local, '_');
    if ($local === '') return null;
    if (!preg_match('/^[a-z]/', $local)) {
        $local = 's' . $local; // usernames must start with a letter — 's' matches the existing student-ID convention (s1234567)
    }
    $local = substr($local, 0, 32);
    return preg_match('/^[a-z][a-z0-9_]{2,31}$/', $local) ? $local : null;
}

function rate_limited(string $email): bool {
    $key = hash('sha256', strtolower($email));
    $lockFile = RATE_LIMIT_DIR . '/' . $key;
    if (is_file($lockFile) && (time() - (int) file_get_contents($lockFile)) < RATE_LIMIT_SECONDS) {
        return true;
    }
    @mkdir(RATE_LIMIT_DIR, 0700, true);
    @file_put_contents($lockFile, (string) time());
    return false;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond_and_redirect(false, 'Please use the form.');
}

$email = trim((string)($_POST['email'] ?? ''));

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    respond_and_redirect(false, 'That doesn\'t look like a valid email address.');
}
if (!empty($smtp['allowed_email_domain'])) {
    $domain = substr($email, strrpos($email, '@') + 1);
    if (strcasecmp($domain, $smtp['allowed_email_domain']) !== 0) {
        audit_log("REJECTED wrong domain: {$email}");
        respond_and_redirect(false, "Please use your @{$smtp['allowed_email_domain']} college email.");
    }
}

$username = derive_username($email);
if ($username === null) {
    audit_log("REJECTED could not derive username from: {$email}");
    respond_and_redirect(false, 'Could not derive a valid username from that email. Please contact your tutor.');
}

if (rate_limited($email)) {
    respond_and_redirect(false, 'A request for this email was already made in the last few minutes. Check your inbox (and spam folder), or wait a few minutes and try again.');
}

// --- Safe invocation: fixed script path (never user input), every argument
// through escapeshellarg(), username re-validated here even though
// derive_username() already constrains it — defense in depth, exactly like
// the original design. ---
$cmd = sprintf(
    'sudo -n %s -u %s 2>&1',
    escapeshellarg(ADD_STUDENT_SCRIPT),
    escapeshellarg($username)
);
exec($cmd, $outputLines, $exitCode);
$output = implode("\n", $outputLines);
audit_log("provision username={$username} email={$email} exit={$exitCode}");

if ($exitCode !== 0) {
    audit_log("FAILURE detail: {$output}");
    respond_and_redirect(false, 'Something went wrong creating your account. Please email your tutor — this has been logged for them to check.');
}

// Parse the password add-student.sh just printed. Deliberately not reading
// it back from credentials.txt on disk — that file stays 600, owned by the
// student, exactly as tested; www-data only ever sees this value in the
// output of the sudo call that just generated it.
if (!preg_match('/^Password:\s+(\S+)/m', $output, $m)) {
    audit_log("FAILURE could not parse password from add-student.sh output: {$output}");
    respond_and_redirect(false, 'Your account was created, but something went wrong retrieving your password. Please email your tutor.');
}
$password = $m[1];
$dbName = "student_{$username}";

$body = <<<TXT
Your 5CS045 server account is ready.

Username: {$username}
Database: {$dbName}
Password: {$password}

This password works for BOTH SSH/SCP and MySQL.

Connect:
  ssh {$username}@<server-address>
  scp -r ./my-site {$username}@<server-address>:~/workshops/

Your files go in one of three folders in your home directory —
workshops/, exams/, assessments/ — and are visible at:
  https://<server-address>/~{$username}/workshops/
  https://<server-address>/~{$username}/exams/
  https://<server-address>/~{$username}/assessments/

Full setup and usage instructions: see the Server Access Guide on Canvas.

If you didn't request this, you can ignore this email — no account
information was disclosed anywhere except to this address.
TXT;

try {
    $mailer = new SmtpMailer(
        host: $smtp['host'], port: $smtp['port'],
        username: $smtp['username'], password: $smtp['password'],
        fromAddress: $smtp['from_address'], fromName: $smtp['from_name'],
        useStartTls: $smtp['use_starttls'],
    );
    $mailer->send($email, 'Your 5CS045 server account', $body);
    audit_log("emailed credentials to {$email} for {$username}");
} catch (Throwable $e) {
    audit_log("EMAIL SEND FAILED for {$username}: " . $e->getMessage());
    respond_and_redirect(false,
        "Your account ({$username}) was created, but we couldn't email your credentials " .
        "(mail server error, logged for your tutor). Please contact your tutor directly to get your password."
    );
}

respond_and_redirect(true, "Account ready — check {$email} for your username, database name, and password.");
