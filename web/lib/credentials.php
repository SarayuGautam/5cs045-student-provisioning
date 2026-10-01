<?php
declare(strict_types=1);

// Turns "sarayu.gautam@college.edu" into "sarayu_gautam".
function derive_username(string $email): ?string {
    $at = strrpos($email, '@');
    if ($at === false) return null;
    $local = strtolower(substr($email, 0, $at));
    $local = preg_replace('/[^a-z0-9]+/', '_', $local);
    $local = trim($local, '_');
    if ($local === '') return null;
    if (!preg_match('/^[a-z]/', $local)) {
        $local = 's' . $local;
    }
    $local = substr($local, 0, 32);
    return preg_match('/^[a-z][a-z0-9_]{2,31}$/', $local) ? $local : null;
}

// True only for a plain mailbox name: letters and digits, with single dots, hyphens or underscores
// between them. College mail delivers name+anything@ to name@, so without this one student could
// sign up again and again as name+1@, name+2@ ..., with every new login emailed to the same inbox.
// It also rules out quoted names and other unusual forms that a mail server may deliver the same way.
function is_plain_address(string $email): bool {
    $at = strrpos($email, '@');
    if ($at === false) return false;
    return preg_match('/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/', strtolower(substr($email, 0, $at))) === 1;
}

// The file name used to remember that an email has been registered.
function registration_key(string $email): string {
    return hash('sha256', strtolower($email));
}

// Students' websites are served only on this name (templates/nginx-students.conf). Any other
// address, the server's IP included, just sends the browser here.
const STUDENT_SITE_URL = 'https://fullstack-student.heraldcollege.edu.np';

// An address from smtp_config.php for an email, or $default when it is missing or an IP address.
// Emails always give the name: a private IP means nothing off campus, and server_url on older
// servers still holds the IP from before the names existed.
function configured_url(array $config, string $key, string $default): string {
    $url = rtrim(trim((string) ($config[$key] ?? '')), '/');
    $host = trim((string) parse_url($url, PHP_URL_HOST), '[]');
    return ($host === '' || filter_var($host, FILTER_VALIDATE_IP) !== false) ? $default : $url;
}

// The students' websites, as the login emails, the panel and add-student.sh give them
function student_site_url(array $config): string {
    return configured_url($config, 'server_url', STUDENT_SITE_URL);
}

// The first email: a one-time link that proves the student can read this mailbox (see registration.php)
function signup_link_email_body(string $username, string $link): string {
    return <<<TXT
Confirm your server account

Full Stack Development Module Server

To create your server account, open this link within 1 hour and click Create my account:

{$link}

Your username will be: {$username}
Your password will follow in a second email.

If you did not ask for a server account, ignore this email. Nothing is created unless the link is used.
TXT;
}

function credentials_email_body(string $username, string $password, string $serverUrl): string {
    $site = rtrim($serverUrl, '/') . '/~' . $username;
    return <<<TXT
Your Server Credentials

Welcome to the Server!

Full Stack Development Module Server

Here are your access details:
-----------------------------
Username: {$username}
Password: {$password}
Database: {$username}

Your websites:
Workshops: {$site}/workshops/
(make one folder for each week, for example workshops/week1)
Assessment: {$site}/assessment/
Exam: {$site}/exam/

Please keep this safe.

If you did not request this account, please contact your tutor.
TXT;
}
