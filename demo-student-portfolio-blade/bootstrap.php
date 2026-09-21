<?php
declare(strict_types=1);

require __DIR__ . '/vendor/autoload.php';

use eftec\bladeone\BladeOne;

session_set_cookie_params(['httponly' => true, 'samesite' => 'Lax']);
session_start();

$configFile = __DIR__ . '/config.php';
if (!is_file($configFile)) {
    http_response_code(500);
    exit('Missing config.php - copy config.example.php to config.php and edit it.');
}
$config = require $configFile;

$pdo = new PDO(
    "mysql:host={$config['db_host']};dbname={$config['db_name']};charset=utf8mb4",
    $config['db_user'],
    $config['db_pass'],
    [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]
);

$blade = new BladeOne(__DIR__ . '/views', __DIR__ . '/cache', BladeOne::MODE_AUTO);

function csrf_token(): string {
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

function verify_csrf(): void {
    $sent = (string) ($_POST['csrf'] ?? '');
    if (!hash_equals($_SESSION['csrf'] ?? '', $sent)) {
        http_response_code(403);
        exit('Invalid form token. Go back, refresh the page and try again.');
    }
}

function current_user_id(): ?int {
    return isset($_SESSION['user_id']) ? (int) $_SESSION['user_id'] : null;
}

function require_login(): int {
    $id = current_user_id();
    if ($id === null) {
        header('Location: login.php');
        exit;
    }
    return $id;
}

function flash(string $message): void {
    $_SESSION['flash'] = $message;
}

function take_flash(): ?string {
    $m = $_SESSION['flash'] ?? null;
    unset($_SESSION['flash']);
    return $m;
}

/** Validate project input; returns [cleanData, errors]. */
function validate_project(array $in): array {
    $data = [
        'title' => trim((string) ($in['title'] ?? '')),
        'description' => trim((string) ($in['description'] ?? '')),
        'tech' => trim((string) ($in['tech'] ?? '')),
    ];
    $errors = [];
    if ($data['title'] === '' || mb_strlen($data['title']) > 120) {
        $errors[] = 'Title is required (max 120 characters).';
    }
    if ($data['description'] === '') {
        $errors[] = 'Description is required.';
    }
    if (mb_strlen($data['tech']) > 120) {
        $errors[] = 'Technologies must be 120 characters or fewer.';
    }
    return [$data, $errors];
}

function render(string $view, array $vars = []): void {
    global $blade;
    $vars += [
        'csrf' => csrf_token(),
        'loggedIn' => current_user_id() !== null,
        'username' => $_SESSION['username'] ?? null,
        'flash' => take_flash(),
    ];
    echo $blade->run($view, $vars);
}
