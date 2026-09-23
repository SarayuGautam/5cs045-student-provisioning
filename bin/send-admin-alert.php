<?php
declare(strict_types=1);

// Emails the admin address set as admin_email in /etc/5cs045/smtp_config.php.
// enforce-limits.sh uses it for the "disk nearly full" alert.
// Usage: sudo php /usr/local/sbin/5cs045/bin/send-admin-alert.php "Subject" "Body text"
// Exit code 2 means admin_email is not set.

if (PHP_SAPI !== 'cli' || posix_geteuid() !== 0) {
    fwrite(STDERR, "Run this from the command line with sudo.\n");
    exit(1);
}

$subject = trim((string) ($argv[1] ?? ''));
$body = (string) ($argv[2] ?? '');
if ($subject === '') {
    fwrite(STDERR, "Usage: sudo php send-admin-alert.php \"Subject\" \"Body text\"\n");
    exit(1);
}

require '/var/www/html/lib/smtp_mailer.php';
$smtp = require '/etc/5cs045/smtp_config.php';

$to = trim((string) ($smtp['admin_email'] ?? ''));
if (!filter_var($to, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "admin_email is not set in /etc/5cs045/smtp_config.php, so there is nowhere to send alerts.\n");
    exit(2);
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
    $mailer->send($to, $subject, $body);
} catch (Throwable $e) {
    fwrite(STDERR, "Email failed: {$e->getMessage()}\n");
    exit(1);
}
echo "Alert sent to {$to}.\n";
