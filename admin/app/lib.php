<?php
declare(strict_types=1);

// Shared helpers for the admin panel. The panel itself cannot change anything on the server:
// it runs as the unprivileged user 5cs045-admin and sends every request to bin/admin-action
// through sudo. See templates/sudoers-5cs045-admin.

const ADMIN_ACTION = '/usr/local/sbin/5cs045/bin/admin-action';
const APP_DIR = __DIR__;

final class ApiError extends RuntimeException {}

// ---------------------------------------------------------------------------------------------
// Session, CSRF and flash messages

function start_session(): void {
    session_set_cookie_params(['path' => '/', 'secure' => true, 'httponly' => true, 'samesite' => 'Strict']);
    session_name('admin_session');
    session_start();
}

function signed_in(): bool {
    return isset($_SESSION['token'], $_SESSION['user']);
}

function current_user(): string {
    return (string) ($_SESSION['user'] ?? '');
}

function csrf_token(): string {
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

function csrf_field(): string {
    return '<input type="hidden" name="csrf" value="' . h(csrf_token()) . '">';
}

function check_csrf(): void {
    $sent = (string) ($_POST['csrf'] ?? '');
    if ($sent === '' || !hash_equals(csrf_token(), $sent)) {
        flash('error', 'That form had expired, so nothing was changed. Please try again.');
        // Back to the page the form was on: /students/x/reset -> /students/x, /security/unban -> /security
        $path = (string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH);
        if (preg_match('#^(/students/[a-z0-9_]+)/[a-z-]+$#', $path, $m) || preg_match('#^(/semester|/security)/#', $path, $m)) {
            $path = $m[1];
        } elseif ($path !== '/login') {
            $path = '/';
        }
        redirect($path);
    }
}

/** $type is success, error or info. */
function flash(string $type, string $message): void {
    $_SESSION['flash'][] = [$type, $message];
}

function take_flashes(): array {
    $f = $_SESSION['flash'] ?? [];
    unset($_SESSION['flash']);
    return $f;
}

/** Something to show exactly once (a new password), kept out of the URL and the history. */
function keep_secret(array $secret): void {
    $_SESSION['secret'] = $secret;
}

function take_secret(): ?array {
    $s = $_SESSION['secret'] ?? null;
    unset($_SESSION['secret']);
    return $s;
}

/** Form values to put back after a failed submit. */
function keep_old(array $values): void {
    $_SESSION['old'] = $values;
}

function take_old(): array {
    $o = $_SESSION['old'] ?? [];
    unset($_SESSION['old']);
    return $o;
}

function redirect(string $path): never {
    header('Location: ' . $path, true, 303);
    exit;
}

function client_ip(): string {
    return (string) ($_SERVER['REMOTE_ADDR'] ?? '');
}

// ---------------------------------------------------------------------------------------------
// Talking to bin/admin-action

/** Sends one request to admin-action. Returns its data, or throws ApiError with a readable message. */
function api(string $action, array $args = []): mixed {
    $request = json_encode([
        'action' => $action,
        'token' => (string) ($_SESSION['token'] ?? ''),
        'ip' => client_ip(),
        'args' => $args,
    ]);
    $proc = proc_open(['sudo', '-n', ADMIN_ACTION], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    if (!is_resource($proc)) {
        throw new ApiError('The panel could not reach the server tools. Run setup/update-server.sh again.');
    }
    fwrite($pipes[0], (string) $request);
    fclose($pipes[0]);
    $out = (string) stream_get_contents($pipes[1]);
    $err = (string) stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    proc_close($proc);

    $answer = json_decode($out, true);
    if (!is_array($answer)) {
        error_log('admin-action gave no answer: ' . trim($err . ' ' . $out));
        throw new ApiError(str_contains($err, 'sudo')
            ? 'The panel is not allowed to run the server tools. Run setup/update-server.sh again.'
            : 'The server tools did not answer. Details are in /var/lib/5cs045-admin/php-error.log.');
    }
    if (!empty($answer['ok'])) {
        return $answer['data'] ?? null;
    }
    $message = (string) ($answer['error'] ?? 'Something went wrong.');
    if (in_array($message, ['SESSION_EXPIRED', 'ADMIN_ACCESS_REVOKED'], true) && $action !== 'login') {
        $revoked = $message === 'ADMIN_ACCESS_REVOKED';
        $_SESSION = [];
        session_regenerate_id(true);
        flash('info', $revoked
            ? 'Your admin-panel access was removed by the superadmin.'
            : 'You were signed out after 30 minutes without activity. Please sign in again.');
        if (str_ends_with((string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? ''), PHP_URL_PATH), '.json')) {
            http_response_code(401);
            header('Content-Type: application/json');
            echo json_encode(['signed_out' => true]);
            exit;
        }
        redirect('/login');
    }
    throw new ApiError($message);
}

// ---------------------------------------------------------------------------------------------
// Rendering

function h(mixed $s): string {
    return htmlspecialchars((string) $s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/** Renders app/views/<name>.php inside the page layout. */
function render(string $view, array $vars = [], string $layout = 'layout'): never {
    $vars['flashes'] ??= take_flashes();
    extract($vars, EXTR_SKIP);
    ob_start();
    require APP_DIR . "/views/{$view}.php";
    $content = (string) ob_get_clean();
    header('Content-Type: text/html; charset=utf-8');
    require APP_DIR . "/views/{$layout}.php";
    exit;
}

function json_out(mixed $data): never {
    header('Content-Type: application/json');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function asset(string $file): string {
    $path = dirname(APP_DIR) . "/public/assets/{$file}";
    return "/assets/{$file}?v=" . (is_file($path) ? filemtime($path) : 0);
}

/** An icon from app/icons.php (Phosphor Icons), sized by CSS and coloured by the text around it. */
function icon(string $name): string {
    static $icons = null;
    $icons ??= require APP_DIR . '/icons.php';
    return '<svg class="icon" viewBox="0 0 256 256" aria-hidden="true" fill="currentColor">' . ($icons[$name] ?? '') . '</svg>';
}

// ---------------------------------------------------------------------------------------------
// Formatting

function fmt_bytes(float|int $bytes): string {
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];
    $i = 0;
    $n = (float) $bytes;
    while ($n >= 1024 && $i < count($units) - 1) {
        $n /= 1024;
        $i++;
    }
    return ($n >= 100 || $i === 0 ? number_format($n, 0) : number_format($n, 1)) . ' ' . $units[$i];
}

function fmt_mb(float|int|null $mb): string {
    if ($mb === null) return 'unknown';
    if ($mb < 0.05) return '0 MB';
    if ($mb >= 1024) return number_format($mb / 1024, 1) . ' GB';
    return ($mb >= 10 ? number_format($mb, 0) : number_format($mb, 1)) . ' MB';
}

/** "3 min ago", "yesterday", "12 Mar". */
function fmt_ago(?string $iso): string {
    if ($iso === null || $iso === '' || ($t = strtotime($iso)) === false) return 'Never';
    $d = time() - $t;
    if ($d < 60) return 'Just now';
    if ($d < 3600) return intdiv($d, 60) . ' min ago';
    if ($d < 86400) return intdiv($d, 3600) . ' h ago';
    if ($d < 2 * 86400) return 'Yesterday';
    if ($d < 7 * 86400) return intdiv($d, 86400) . ' days ago';
    return date(date('Y', $t) === date('Y') ? 'j M' : 'j M Y', $t);
}

/** "Signed in 3 days ago", "Signed in on 12 Sep", "Never signed in". */
function fmt_last(?string $iso): string {
    if ($iso === null || $iso === '') return 'Never signed in';
    $ago = fmt_ago($iso);
    return 'Signed in ' . (preg_match('/^\d+ [A-Z]/', $ago) ? 'on ' . $ago : strtolower($ago));
}

function fmt_date(?string $iso): string {
    if ($iso === null || $iso === '' || ($t = strtotime($iso)) === false) return '';
    return date('j M Y, H:i', $t);
}

function fmt_duration(int $seconds): string {
    if ($seconds < 60) return "{$seconds} s";
    if ($seconds < 3600) return intdiv($seconds, 60) . ' min';
    if ($seconds < 86400) return intdiv($seconds, 3600) . ' h ' . intdiv($seconds % 3600, 60) . ' min';
    $days = intdiv($seconds, 86400);
    return $days . ' day' . ($days === 1 ? '' : 's') . ', ' . intdiv($seconds % 86400, 3600) . ' h';
}

function percent(float|int|null $used, float|int|null $total): int {
    if (!$total || $used === null) return 0;
    return (int) max(0, min(100, round(100 * $used / $total)));
}

/** ok below 75%, warn below 90%, danger from 90%. */
function level(int $pct): string {
    return $pct >= 90 ? 'danger' : ($pct >= 75 ? 'warn' : 'ok');
}

function job_label(string $kind): string {
    return ['smoke-test' => 'Health check', 'bulk-add' => 'Add a class', 'remove-all' => 'Remove every student'][$kind] ?? $kind;
}

function job_state(array $job): array {
    if (empty($job['done'])) return ['running', 'Running'];
    return ($job['exit'] ?? 1) === 0 ? ['ok', 'Finished'] : ['danger', 'Finished with problems'];
}
