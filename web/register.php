<?php
declare(strict_types=1);

session_set_cookie_params([
    'secure' => true,
    'httponly' => true,
    'samesite' => 'Strict',
]);
session_start();

if (empty($_SESSION['register_csrf'])) {
    $_SESSION['register_csrf'] = bin2hex(random_bytes(32));
}

$message = $_SESSION['register_result'] ?? null;
unset($_SESSION['register_result']);
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Server Registration | Full Stack Development</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
:root {
    --green: #72bf3d;
    --green-dark: #5ca52c;
    --green-soft: #edf8e7;
    --ink: #252525;
    --muted: #6b7280;
    --line: #e6e8eb;
    --surface: #ffffff;
    --background: #f4f7f2;
    --danger-bg: #fff4f4;
    --danger-line: #f3c2c2;
    --danger-text: #9f2626;
    --success-line: #c3e7ad;
    --success-text: #2f6f19;
}

* { box-sizing: border-box; }

html, body { min-height: 100%; }

body {
    margin: 0;
    font-family: 'Poppins', sans-serif;
    background:
        radial-gradient(circle at top right, rgba(114, 191, 61, 0.12), transparent 28%),
        var(--background);
    color: var(--ink);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 48px 24px;
}

.shell {
    width: min(100%, 560px);
}

.card {
    background: var(--surface);
    border: 1px solid rgba(30, 41, 59, 0.08);
    border-radius: 24px;
    box-shadow: 0 22px 60px rgba(24, 39, 28, 0.10);
    overflow: hidden;
}

.logo-wrap {
    padding: 28px 30px 4px;
    background: #fff;
    display: flex;
    justify-content: flex-end;
}

.logo {
    display: block;
    width: 30%;
    height: auto;
    border-radius: 8px;
}

.content {
    padding: 34px 52px 46px;
    text-align: center;
}

.badge {
    display: inline-flex;
    align-items: center;
    padding: 7px 12px;
    border-radius: 999px;
    background: var(--green-soft);
    color: var(--green-dark);
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.02em;
    margin-bottom: 14px;
}

h1 {
    margin: 0;
    font-size: 30px;
    line-height: 1.25;
    font-weight: 700;
    letter-spacing: -0.02em;
}

.intro {
    margin: 10px 0 24px;
    color: var(--muted);
    font-size: 14px;
    line-height: 1.75;
}

.message {
    border-radius: 14px;
    padding: 13px 15px;
    margin-bottom: 20px;
    font-size: 13px;
    line-height: 1.6;
}

.message.ok {
    background: var(--green-soft);
    border: 1px solid var(--success-line);
    color: var(--success-text);
}

.message.err {
    background: var(--danger-bg);
    border: 1px solid var(--danger-line);
    color: var(--danger-text);
}

.field-label {
    display: block;
    margin-bottom: 8px;
    font-size: 13px;
    font-weight: 600;
}

.input-wrap {
    position: relative;
}

input[type="email"] {
    width: 100%;
    height: 52px;
    border: 1px solid var(--line);
    border-radius: 14px;
    padding: 0 16px;
    font: 500 14px 'Poppins', sans-serif;
    color: var(--ink);
    background: #fff;
    outline: none;
    transition: border-color .15s ease, box-shadow .15s ease;
}

input[type="email"]::placeholder {
    color: #a4a8ae;
    font-weight: 400;
}

input[type="email"]:focus {
    border-color: var(--green);
    box-shadow: 0 0 0 4px rgba(114, 191, 61, 0.14);
}

button {
    width: 100%;
    height: 52px;
    margin-top: 16px;
    border: 0;
    border-radius: 14px;
    background: var(--green);
    color: #fff;
    padding: 0 16px;
    font: 600 14px 'Poppins', sans-serif;
    cursor: pointer;
    transition: background .15s ease, transform .15s ease, box-shadow .15s ease;
    box-shadow: 0 10px 24px rgba(114, 191, 61, 0.20);
}

button:hover {
    background: var(--green-dark);
    box-shadow: 0 12px 28px rgba(92, 165, 44, 0.22);
}

button:active {
    transform: translateY(1px);
}


@media (max-width: 520px) {
    body { padding: 18px 12px; }
    .logo-wrap { padding: 18px 20px 2px; }
    .logo { width: 34%; }
    .content { padding: 26px 22px 30px; }
    h1 { font-size: 25px; }
}
</style>
</head>
<body>
<div class="shell">
    <main class="card">
        <div class="logo-wrap">
            <img class="logo" src="assets/herald-college-logo.png" alt="Herald College Kathmandu and Islington College logo">
        </div>

        <div class="content">
            <div class="badge">Full Stack Development Module Server</div>

            <h1>Register for your server account</h1>
            <p class="intro">Enter your college email address. Your credentials will be sent to your mail.</p>

            <?php if ($message !== null): ?>
                <div class="message <?= $message['ok'] ? 'ok' : 'err' ?>">
                    <?= htmlspecialchars($message['message'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>
                </div>
            <?php endif; ?>

            <form method="post" action="register_handler.php" autocomplete="on">
                <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($_SESSION['register_csrf'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>">

                <label class="field-label" for="email">College email</label>
                <div class="input-wrap">
                    <input
                        id="email"
                        name="email"
                        type="email"
                        required
                        maxlength="254"
                        autocomplete="email"
                        placeholder="yourname@heraldcollege.edu.np"
                        autofocus
                    >
                </div>

                <button type="submit">Register</button>
            </form>
        </div>
    </main>
</div>
</body>
</html>
