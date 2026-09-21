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
    --muted: #687285;
    --line: #e2e6ea;
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
    min-height: 100vh;
    font-family: 'Poppins', sans-serif;
    background:
        radial-gradient(circle at top right, rgba(114, 191, 61, 0.10), transparent 30%),
        var(--background);
    color: var(--ink);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 32px 20px;
}

.shell {
    width: min(100%, 900px);
}

.card {
    background: var(--surface);
    border: 1px solid rgba(30, 41, 59, 0.08);
    border-radius: 28px;
    box-shadow: 0 24px 70px rgba(24, 39, 28, 0.10);
    padding: 42px 56px 52px;
}

.header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 28px;
    margin-bottom: 40px;
}

.badge {
    display: inline-flex;
    align-items: center;
    padding: 6px 11px;
    border-radius: 999px;
    background: var(--green-soft);
    color: var(--green-dark);
    font-size: 11px;
    font-weight: 600;
    line-height: 1.2;
    letter-spacing: 0.01em;
    white-space: nowrap;
}

.logo {
    display: block;
    width: 170px;
    height: auto;
    flex: 0 0 auto;
}

.content {
    text-align: center;
}

h1 {
    margin: 0;
    font-size: clamp(26px, 3.1vw, 34px);
    line-height: 1.2;
    font-weight: 700;
    letter-spacing: -0.025em;
    white-space: nowrap;
}

.intro {
    margin: 16px auto 34px;
    max-width: 680px;
    color: var(--muted);
    font-size: 15px;
    line-height: 1.8;
}

.message {
    border-radius: 14px;
    padding: 13px 15px;
    margin-bottom: 22px;
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

form {
    width: min(100%, 720px);
    margin: 0 auto;
}

.field-label {
    display: block;
    margin-bottom: 9px;
    font-size: 13px;
    font-weight: 600;
    text-align: center;
}

input[type="email"] {
    width: 100%;
    height: 56px;
    border: 1px solid var(--line);
    border-radius: 15px;
    padding: 0 18px;
    font: 500 14px 'Poppins', sans-serif;
    color: var(--ink);
    background: #fff;
    outline: none;
    text-align: center;
    transition: border-color .15s ease, box-shadow .15s ease;
}

input[type="email"]::placeholder {
    color: #a4aab3;
    font-weight: 400;
}

input[type="email"]:focus {
    border-color: var(--green);
    box-shadow: 0 0 0 4px rgba(114, 191, 61, 0.14);
}

button {
    width: 100%;
    height: 56px;
    margin-top: 17px;
    border: 0;
    border-radius: 15px;
    background: var(--green);
    color: #fff;
    padding: 0 18px;
    font: 600 15px 'Poppins', sans-serif;
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

@media (max-width: 700px) {
    body { padding: 18px 12px; }

    .card {
        padding: 28px 24px 34px;
        border-radius: 22px;
    }

    .header {
        margin-bottom: 30px;
        gap: 18px;
    }

    .logo {
        width: 120px;
    }

    h1 {
        font-size: 26px;
        white-space: normal;
    }

    .intro {
        margin-bottom: 28px;
        font-size: 14px;
    }

    form {
        width: 100%;
    }
}

@media (max-width: 480px) {
    .header {
        align-items: flex-start;
    }

    .badge {
        font-size: 10px;
    }

    .logo {
        width: 94px;
    }

    h1 {
        font-size: 24px;
    }

    input[type="email"],
    button {
        height: 52px;
    }
}
</style>
</head>
<body>
<div class="shell">
    <main class="card">
        <div class="header">
            <div class="badge">Full Stack Development Module Server</div>
            <img
                class="logo"
                src="data:image/png;base64,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"
                alt="Herald College Kathmandu and Islington College logo"
            >
        </div>

        <div class="content">
            <h1>Register for your server account</h1>
            <p class="intro">Enter your college email address. Your credentials will be sent to your mail.</p>

            <?php if ($message !== null): ?>
                <div class="message <?= $message['ok'] ? 'ok' : 'err' ?>">
                    <?= htmlspecialchars($message['message'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>
                </div>
            <?php endif; ?>

            <form method="post" action="register_handler.php" autocomplete="on">
                <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($_SESSION['register_csrf'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?>">
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

                <button type="submit">Register</button>
            </form>
        </div>
    </main>
</div>
</body>
</html>
