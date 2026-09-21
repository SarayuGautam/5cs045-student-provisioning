<?php
declare(strict_types=1);

// Emails a student their login details again (for example after they deleted the first email).
// Usage: sudo php /usr/local/sbin/5cs045/bin/resend-credentials.php student@heraldcollege.edu.np
//
// It sends the password saved in the student's credentials.txt.
// If the student has changed their password themselves, run reset-student-password.sh first.

if (PHP_SAPI !== 'cli' || posix_geteuid() !== 0) {
    fwrite(STDERR, "Run this from the command line with sudo.\n");
    exit(1);
}

$email = $argv[1] ?? '';
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "Usage: sudo php resend-credentials.php student@heraldcollege.edu.np\n");
    exit(1);
}

require '/var/www/html/lib/smtp_mailer.php';
require '/var/www/html/lib/credentials.php';
$smtp = require '/etc/5cs045/smtp_config.php';

// Find the username: the registration record first, otherwise work it out from the email.
$username = null;
$record = '/var/lib/5cs045-registrations/' . registration_key($email);
if (is_file($record)) {
    $username = json_decode((string) file_get_contents($record), true)['username'] ?? null;
}
$username ??= derive_username($email);

$credentialsFile = $username ? "/srv/students/{$username}/credentials.txt" : '';
if ($username === null || !is_file($credentialsFile)) {
    fwrite(STDERR, "No student account found for {$email}.\n");
    exit(1);
}
if (!preg_match('/^PASSWORD=(\S+)/m', (string) file_get_contents($credentialsFile), $m)) {
    fwrite(STDERR, "Could not read the password from {$credentialsFile}.\n");
    exit(1);
}

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
    $mailer->send($email, 'Your Server Credentials', credentials_email_body($username, $m[1], (string) $smtp['server_url']));
} catch (Throwable $e) {
    fwrite(STDERR, "Email failed: {$e->getMessage()}\n");
    exit(1);
}
echo "Sent the login details for {$username} to {$email}.\n";
