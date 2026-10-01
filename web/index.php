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

// Opened from the link in the sign-up email. Nothing happens until the student clicks
// "Create my account" (confirm_handler.php), because mail scanners open links too.
require __DIR__ . '/lib/credentials.php';
require __DIR__ . '/lib/registration.php';

$token = is_string($_GET['confirm'] ?? null) ? $_GET['confirm'] : '';
$confirm = null;

if ($token !== '') {
    $confirm = find_signup_link($token, $expired);

    if ($confirm === null) {
        $message = [
            'ok' => false,
            'message' => $expired
                ? SIGNUP_LINK_EXPIRED
                : SIGNUP_LINK_NOT_VALID
        ];
    } elseif (already_registered($confirm['email'])) {
        delete_signup_link($token);

        $message = [
            'ok' => true,
            'message' => "Your account has already been created. Your username and password were emailed to {$confirm['email']}."
        ];

        $confirm = null;
    }
}

$e = static fn (string $s): string =>
    htmlspecialchars(
        $s,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Server Registration | Full Stack Development</title>

<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link
    href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&display=swap"
    rel="stylesheet"
>

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

* {
    box-sizing: border-box;
}

html,
body {
    min-height: 100%;
}

body {
    margin: 0;
    min-height: 100vh;
    font-family: 'Poppins', sans-serif;
    background:
        radial-gradient(
            circle at top right,
            rgba(114, 191, 61, 0.10),
            transparent 30%
        ),
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
    line-height: 1.25;
    font-weight: 700;
    letter-spacing: -0.025em;
    white-space: nowrap;
}

.intro {
    margin: 16px auto 34px;
    max-width: 680px;
    color: var(--muted);
    font-size: 15px;
    line-height: 1.9;
    letter-spacing: 0.01em;
}

.intro strong {
    color: var(--ink);
    font-weight: 600;
    overflow-wrap: anywhere;
}

/* Registration success/error message */
.message {
    width: min(100%, 720px);
    margin: 0 auto 28px;
    border-radius: 16px;
    padding: 18px 24px;
    font-size: 14px;
    line-height: 1.9;
    letter-spacing: 0.01em;
    text-align: left;
    overflow-wrap: anywhere;
    word-break: normal;
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
    transition:
        border-color .15s ease,
        box-shadow .15s ease;
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
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    transition:
        background .15s ease,
        transform .15s ease,
        box-shadow .15s ease;
    box-shadow: 0 10px 24px rgba(114, 191, 61, 0.20);
}

button:hover {
    background: var(--green-dark);
    box-shadow: 0 12px 28px rgba(92, 165, 44, 0.22);
}

button:active {
    transform: translateY(1px);
}

button:disabled {
    cursor: not-allowed;
    background: var(--green-dark);
    opacity: 0.9;
    transform: none;
}

.spinner {
    display: none;
    width: 18px;
    height: 18px;
    flex: 0 0 auto;
    border: 2.5px solid rgba(255, 255, 255, 0.45);
    border-top-color: #fff;
    border-radius: 50%;
    animation: spin 0.7s linear infinite;
}

button.loading .spinner {
    display: inline-block;
}

@keyframes spin {
    to {
        transform: rotate(360deg);
    }
}

@media (max-width: 700px) {
    body {
        padding: 18px 12px;
    }

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
        line-height: 1.85;
    }

    .message {
        margin-bottom: 24px;
        padding: 17px 20px;
        font-size: 13.5px;
        line-height: 1.9;
        letter-spacing: 0.008em;
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
        line-height: 1.3;
    }

    .intro {
        font-size: 13.5px;
        line-height: 1.85;
    }

    .message {
        padding: 16px 18px;
        font-size: 13px;
        line-height: 1.95;
        letter-spacing: 0.006em;
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
            <div class="badge">
                Full Stack Development Module Server
            </div>

            <img
                class="logo"
                src="data:image/png;base64,PASTE-YOUR-EXISTING-LOGO-BASE64-HERE"
                alt="Herald College Kathmandu and Islington College logo"
            >
        </div>

        <div class="content">

            <?php if ($confirm !== null): ?>

                <h1>Create your server account</h1>

                <p class="intro">
                    Your username will be
                    <strong><?= $e($confirm['username']) ?></strong>.
                    Click the button to create your account, and your password
                    will be emailed to
                    <strong><?= $e($confirm['email']) ?></strong>.
                </p>

                <form method="post" action="confirm_handler.php">
                    <input
                        type="hidden"
                        name="csrf_token"
                        value="<?= $e($_SESSION['register_csrf']) ?>"
                    >

                    <input
                        type="hidden"
                        name="token"
                        value="<?= $e($token) ?>"
                    >

                    <button type="submit" id="submitBtn">
                        <span class="btn-label">Create my account</span>
                        <span
                            class="spinner"
                            aria-hidden="true"
                        ></span>
                    </button>
                </form>

            <?php else: ?>

                <h1>Register for your server account</h1>

                <p class="intro">
                    Enter your college email address. We will email you a link
                    to create your account.
                </p>

                <?php if ($message !== null): ?>
                    <div
                        class="message <?= $message['ok'] ? 'ok' : 'err' ?>"
                        role="<?= $message['ok'] ? 'status' : 'alert' ?>"
                    >
                        <?= $e($message['message']) ?>
                    </div>
                <?php endif; ?>

                <form
                    method="post"
                    action="register_handler.php"
                    autocomplete="on"
                >
                    <input
                        type="hidden"
                        name="csrf_token"
                        value="<?= $e($_SESSION['register_csrf']) ?>"
                    >

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

                    <button type="submit" id="submitBtn">
                        <span class="btn-label">Register</span>
                        <span
                            class="spinner"
                            aria-hidden="true"
                        ></span>
                    </button>
                </form>

            <?php endif; ?>

        </div>
    </main>
</div>

<script>
(function () {
    var form = document.querySelector('form');
    var btn = document.getElementById('submitBtn');

    if (!form || !btn) return;

    form.addEventListener('submit', function () {
        if (btn.classList.contains('loading')) return;

        btn.classList.add('loading');
        btn.disabled = true;
    });

    window.addEventListener('pageshow', function (event) {
        if (event.persisted) {
            btn.classList.remove('loading');
            btn.disabled = false;
        }
    });
})();
</script>

</body>
</html>
