<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "Run this script from the command line.\n");
    exit(1);
}
if (posix_geteuid() !== 0) {
    fwrite(STDERR, "Run as root so the script can read /etc/5cs045/smtp_config.php.\n");
    exit(1);
}

$recipient = $argv[1] ?? '';
if (!filter_var($recipient, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "Usage: php test/smtp-test.php your.email@example.com\n");
    exit(1);
}

require __DIR__ . '/../web/lib/smtp_mailer.php';
$smtp = require '/etc/5cs045/smtp_config.php';

$body = "This is a test email from the 5CS045 Full Stack Development Module Server.\n\n" .
date(DATE_RFC2822) . "\n";

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
    $mailer->send($recipient, '5CS045 SMTP Test', $body);
    echo "SMTP test email sent to {$recipient}.\n";
    exit(0);
} catch (Throwable $e) {
    fwrite(STDERR, "SMTP test failed: {$e->getMessage()}\n");
    exit(1);
}
