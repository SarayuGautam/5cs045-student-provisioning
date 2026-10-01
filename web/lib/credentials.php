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

    return preg_match('/^[a-z][a-z0-9_]{2,31}$/', $local)
        ? $local
        : null;
}

// True only for a plain mailbox name: letters and digits, with single dots, hyphens or underscores
// between them. College mail delivers name+anything@ to name@, so without this one student could
// sign up again and again as name+1@, name+2@ ..., with every new login emailed to the same inbox.
// It also rules out quoted names and other unusual forms that a mail server may deliver the same way.
function is_plain_address(string $email): bool {
    $at = strrpos($email, '@');
    if ($at === false) return false;

    return preg_match(
        '/^[a-z0-9]+(?:[._-][a-z0-9]+)*$/',
        strtolower(substr($email, 0, $at))
    ) === 1;
}

// The file name used to remember that an email has been registered.
function registration_key(string $email): string {
    return hash('sha256', strtolower($email));
}

// Students' websites are served only on this name (templates/nginx-students.conf). Any other
// address, the server's IP included, just sends the browser here.
const STUDENT_SITE_URL = 'https://fullstack-student.heraldcollege.edu.np';

// Server Access Guide stored in Google Drive.
const SERVER_ACCESS_GUIDE_URL =
    'https://drive.google.com/file/d/1dYHPNEagjrgTZoFiXwzQKuDLKiA_Mgnd/view?usp=drive_link';

// An address from smtp_config.php for an email, or $default when it is missing or an IP address.
// Emails always give the name: a private IP means nothing off campus, and server_url on older
// servers still holds the IP from before the names existed.
function configured_url(array $config, string $key, string $default): string {
    $url = rtrim(trim((string) ($config[$key] ?? '')), '/');
    $host = trim((string) parse_url($url, PHP_URL_HOST), '[]');

    return (
        $host === '' ||
        filter_var($host, FILTER_VALIDATE_IP) !== false
    ) ? $default : $url;
}

// The students' websites, as the login emails, the panel and add-student.sh give them.
function student_site_url(array $config): string {
    return configured_url($config, 'server_url', STUDENT_SITE_URL);
}

// The first email: a one-time link that proves the student can read this mailbox.
function signup_link_email_body(string $username, string $link): string {
    return <<<TXT
Confirm your Full Stack Development Module Server account

To create your server account, open this link within 1 hour. Then click Create my account:

{$link}

If you did not ask for a server account, ignore this email.
TXT;
}

// Plain-text fallback for the credentials email.
function credentials_email_body(
    string $username,
    string $password,
    string $serverUrl
): string {
    $site = rtrim($serverUrl, '/') . '/~' . $username;

    return "Welcome to the Full Stack Development Module Server!\n\n" .
        "Here are your access details. Please keep this safe:\n" .
        "-----------------------------\n" .
        "Username: {$username}\n" .
        "Password: {$password}\n" .
        "Database: {$username}\n\n" .
        "Your website:\n" .
        "{$site}\n\n" .
        "Server Access Guide:\n" .
        SERVER_ACCESS_GUIDE_URL . "\n\n" .
        "If you did not request this account, please contact your tutor.\n";
}

// HTML version of the credentials email.
// The visible link text is only: "Server Access Guide".
function credentials_email_html(
    string $username,
    string $password,
    string $serverUrl
): string {
    $safeUsername = htmlspecialchars(
        $username,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );

    $safePassword = htmlspecialchars(
        $password,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );

    $site = rtrim($serverUrl, '/') . '/~' . $username;

    $safeSite = htmlspecialchars(
        $site,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );

    $safeGuideUrl = htmlspecialchars(
        SERVER_ACCESS_GUIDE_URL,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );

    return <<<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Your Server Credentials</title>
</head>
<body style="font-family: Arial, sans-serif; line-height: 1.5; color: #222;">

  <p>Welcome to the Full Stack Development Module Server!</p>

  <p>Here are your access details. Please keep this safe:</p>

  <table cellpadding="6" cellspacing="0" border="0">
    <tr>
      <td><strong>Username</strong></td>
      <td>{$safeUsername}</td>
    </tr>
    <tr>
      <td><strong>Password</strong></td>
      <td>{$safePassword}</td>
    </tr>
    <tr>
      <td><strong>Database</strong></td>
      <td>{$safeUsername}</td>
    </tr>
  </table>

  <p>
    <strong>Your website:</strong><br>
    <a href="{$safeSite}">{$safeSite}</a>
  </p>

  <p>
    <a href="{$safeGuideUrl}">Server Access Guide</a>
  </p>

  <p>If you did not request this account, please contact your tutor.</p>

</body>
</html>
HTML;
}
