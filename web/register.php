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
<style>
:root {
    --green: #69be28;
    --green-dark: #4f921d;
    --ink: #1f2937;
    --muted: #6b7280;
    --line: #e5e7eb;
    --surface: #ffffff;
    --background: #f5f7f8;
}
* { box-sizing: border-box; }
body {
    margin: 0;
    min-height: 100vh;
    font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #f8fafb 0%, var(--background) 100%);
    color: var(--ink);
    display: grid;
    place-items: center;
    padding: 28px 16px;
}
.card {
    width: min(100%, 460px);
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 20px;
    box-shadow: 0 18px 50px rgba(15, 23, 42, 0.08);
    padding: 34px;
}
.brand {
    display: flex;
    align-items: center;
    gap: 14px;
    margin-bottom: 24px;
}
.brand-mark {
    width: 64px;
    height: 64px;
    flex: 0 0 64px;
}
.brand-copy strong {
    display: block;
    font-size: 14px;
    letter-spacing: 0.08em;
    line-height: 1.25;
}
.brand-copy span {
    display: block;
    margin-top: 5px;
    font-size: 12px;
    color: var(--muted);
}
h1 {
    font-size: 28px;
    line-height: 1.2;
    margin: 0 0 10px;
}
.intro {
    margin: 0 0 26px;
    color: var(--muted);
    line-height: 1.6;
}
label {
    display: block;
    font-size: 14px;
    font-weight: 650;
    margin-bottom: 8px;
}
input[type="email"] {
    width: 100%;
    border: 1px solid #d1d5db;
    border-radius: 12px;
    padding: 13px 14px;
    font: inherit;
    color: var(--ink);
    background: #fff;
    outline: none;
    transition: border-color .15s ease, box-shadow .15s ease;
}
input[type="email"]:focus {
    border-color: var(--green);
    box-shadow: 0 0 0 4px rgba(105, 190, 40, 0.14);
}
button {
    width: 100%;
    margin-top: 18px;
    border: 0;
    border-radius: 12px;
    background: var(--green);
    color: #fff;
    padding: 13px 16px;
    font: inherit;
    font-weight: 700;
    cursor: pointer;
    transition: background .15s ease, transform .15s ease;
}
button:hover { background: var(--green-dark); }
button:active { transform: translateY(1px); }
.note {
    margin-top: 14px;
    font-size: 12px;
    color: var(--muted);
    line-height: 1.5;
}
.message {
    border-radius: 12px;
    padding: 12px 14px;
    margin-bottom: 18px;
    font-size: 14px;
    line-height: 1.5;
}
.message.ok { background: #effbea; border: 1px solid #b9e59b; color: #245414; }
.message.err { background: #fff4f4; border: 1px solid #f2b8b8; color: #8d1e1e; }
.footer {
    text-align: center;
    margin-top: 22px;
    color: #9ca3af;
    font-size: 11px;
}
</style>
</head>
<body>
<main class="card">
    <div class="brand">
        <svg class="brand-mark" viewBox="0 0 64 64" role="img" aria-label="Herald College Kathmandu">
            <rect x="1" y="1" width="62" height="62" rx="10" fill="#69be28"/>
            <path d="M15 45V19h7v8h20v-8h7v26h-7V34H22v11h-7Z" fill="#fff"/>
            <path d="M27 19h7v26h-7z" fill="#fff"/>
        </svg>
        <div class="brand-copy">
            <strong>HERALD COLLEGE KATHMANDU</strong>
            <span>Full Stack Development Module Server</span>
        </div>
    </div>

    <h1>Create your server account</h1>
    <p class="intro">Use your college email. Your server details will be sent to you by email.</p>

    <?php if ($message !== null): ?>
        <div class="message <?= $message['ok'] ? 'ok' : 'err' ?>">
            <?= htmlspecialchars($message['message'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>
        </div>
    <?php endif; ?>

    <form method="post" action="register_handler.php" autocomplete="email">
        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($_SESSION['register_csrf'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>">
        <label for="email">College email</label>
        <input id="email" name="email" type="email" required maxlength="254" placeholder="yourname@heraldcollege.edu.np" autofocus>
        <button type="submit">Create account</button>
    </form>

    <p class="note">Use your college email only. Contact your tutor if you need help with an existing account.</p>
    <div class="footer">Full Stack Development Module</div>
</main>
</body>
</html>
