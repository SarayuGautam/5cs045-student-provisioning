<?php
declare(strict_types=1);

// Sign-up, step 2: the student opened the emailed link and clicked "Create my account", which
// proves the mailbox is real and theirs. Create the account and email the password.

session_set_cookie_params([
    'secure' => true,
    'httponly' => true,
    'samesite' => 'Strict',
]);
session_start();

require __DIR__ . '/lib/credentials.php';
require __DIR__ . '/lib/registration.php';

$smtp = require '/etc/5cs045/smtp_config.php';

const ADD_STUDENT_SCRIPT = '/usr/local/sbin/5cs045/bin/add-student.sh';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond_and_redirect(false, 'Please use the link in your email.');
}

$csrf = (string) ($_POST['csrf_token'] ?? '');

if (!hash_equals((string) ($_SESSION['register_csrf'] ?? ''), $csrf)) {
    audit_log('REJECTED invalid CSRF token (create account)');
    respond_and_redirect(false, 'The page expired. Please open the link in your email again.');
}

$token = is_string($_POST['token'] ?? null) ? $_POST['token'] : '';

$link = find_signup_link($token, $expired);

if ($link === null) {
    respond_and_redirect(
        false,
        $expired ? SIGNUP_LINK_EXPIRED : SIGNUP_LINK_NOT_VALID
    );
}

$email = $link['email'];
$username = derive_username($email);

if ($username === null || $username !== $link['username']) {
    delete_signup_link($token);
    respond_and_redirect(false, SIGNUP_LINK_NOT_VALID);
}

// One request at a time for this email, so a double click cannot create the account twice.
// The checks below come after the lock for the same reason.
if (!acquire_request_lock($email, false)) {
    respond_and_redirect(
        false,
        'Your account is already being created. Wait a minute, then check your email.'
    );
}

if (already_registered($email)) {
    delete_signup_link($token);

    respond_and_redirect(
        true,
        "Your account has already been created. Your username and password were emailed to {$email}."
    );
}

if (id_exists($username)) {
    delete_signup_link($token);
    audit_log("REJECTED {$username} already exists (email={$email})");

    respond_and_redirect(
        false,
        'An account already exists for this student. Please contact your tutor.'
    );
}

$cmd = sprintf(
    'sudo -n %s -d -u %s 2>&1',
    escapeshellarg(ADD_STUDENT_SCRIPT),
    escapeshellarg($username)
);

exec($cmd, $outputLines, $exitCode);

$output = implode("\n", $outputLines);

audit_log(
    "provision username={$username} email={$email} exit={$exitCode}"
);

if ($exitCode !== 0) {
    audit_log("FAILURE detail: {$output}");

    respond_and_redirect(
        false,
        'Something went wrong while creating your account. Please open the link again in a few minutes, or contact your tutor.'
    );
}

// The account exists now: record the email so it cannot sign up again, and use up the link.
try {
    mark_registered($email, $username);
} catch (Throwable $e) {
    audit_log("FAILURE {$username}: " . $e->getMessage());
}

delete_signup_link($token);

if (!preg_match('/^Password:\s+(\S+)/m', $output, $m)) {
    audit_log("FAILURE could not parse password for {$username}");

    respond_and_redirect(
        false,
        'Your account was created, but we could not prepare your email. Please ask your tutor to send your password.'
    );
}

try {
    $serverUrl = student_site_url($smtp);

    smtp_mailer($smtp)->send(
        $email,
        'Your Server Credentials',
        credentials_email_body(
            $username,
            $m[1],
            $serverUrl
        ),
        credentials_email_html(
            $username,
            $m[1],
            $serverUrl
        )
    );
} catch (Throwable $e) {
    audit_log(
        "PASSWORD EMAIL FAILED for {$username}: " . $e->getMessage()
    );

    respond_and_redirect(
        false,
        'Your account is ready, but the email with your password did not send. Please ask your tutor to send it again.'
    );
}

audit_log("registered username={$username} email={$email}");

respond_and_redirect(
    true,
    "Your account is ready. Your username and password are on their way to {$email}."
);
