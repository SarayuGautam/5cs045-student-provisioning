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

// The file name used to remember that an email has been registered.
function registration_key(string $email): string {
    return hash('sha256', strtolower($email));
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
Assessments: {$site}/assessments/
Exams: {$site}/exams/

Please keep this safe.

If you did not request this account, please contact your tutor.
TXT;
}
