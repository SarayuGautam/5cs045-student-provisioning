<?php
declare(strict_types=1);

// Every page of the admin panel comes through here. nginx sends all requests except /assets/ to this file.

require dirname(__DIR__) . '/app/lib.php';

start_session();
header('X-Robots-Tag: noindex');

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$path = rtrim((string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH), '/') ?: '/';
$post = $method === 'POST';
$USER = '[a-z][a-z0-9_]{2,31}';
$JOB = '\d{8}-\d{6}-[a-f0-9]{6}';

if ($post) {
    check_csrf();
}

// ---------------------------------------------------------------------------------------------
// Signing in and out

if ($path === '/login') {
    if (signed_in()) redirect('/');
    $error = null;
    $username = 'fullstack';
    if ($post) {
        $username = trim((string) ($_POST['username'] ?? ''));
        try {
            $data = api('login', ['username' => $username, 'password' => (string) ($_POST['password'] ?? '')]);
            session_regenerate_id(true);
            $_SESSION['token'] = $data['token'];
            $_SESSION['user'] = $data['user'];
            $next = (string) ($_SESSION['after_login'] ?? '/');
            unset($_SESSION['after_login']);
            redirect(preg_match('#^/[a-z0-9/_-]*$#', $next) ? $next : '/');
        } catch (ApiError $e) {
            $error = $e->getMessage();
        }
    }
    render('login', ['title' => 'Sign in', 'error' => $error, 'username' => $username], 'bare');
}

if (!signed_in()) {
    if (!$post && $path !== '/' && !str_ends_with($path, '.json')) {
        $_SESSION['after_login'] = $path;
    }
    if (str_ends_with($path, '.json')) {
        http_response_code(401);
        json_out(['signed_out' => true]);
    }
    redirect('/login');
}

if ($path === '/logout' && $post) {
    try {
        api('logout');
    } catch (ApiError) {
        // Signed out on the server already; clearing the browser side is all that is left.
    }
    $_SESSION = [];
    session_regenerate_id(true);
    flash('success', 'You are signed out.');
    redirect('/login');
}

// ---------------------------------------------------------------------------------------------
// Pages

try {
    // Students: the roster, with one student or the "add a student" form beside it
    $roster = function (?array $student) {
        $partial = ($_SERVER['HTTP_X_PANEL'] ?? '') === '1';
        $vars = ['s' => $student, 'secret' => take_secret(), 'settings' => api('settings'), 'old' => take_old(), 'flashes' => take_flashes()];
        if ($partial) {
            // Only the right-hand panel, for app.js to swap in without reloading the roster
            header('Content-Type: text/html; charset=utf-8');
            header('Vary: X-Panel');
            extract($vars);
            $bans = $student ? [] : api('bans');
            require APP_DIR . '/views/' . ($student ? '_person.php' : '_home.php');
            exit;
        }
        render('roster', $vars + [
            'title' => $student ? $student['username'] : 'Students',
            'nav' => 'students',
            'students' => api('students'),
            'bans' => $student ? [] : api('bans'),
            'health' => api('health'),
            'main_class' => 'split',
            'flashes_in_panel' => true,
        ]);
    };

    if ($path === '/' && !$post) {
        $roster(null);
    }

    if ($path === '/students' && !$post) {
        redirect('/');
    }

    if (preg_match("#^/students/({$USER})$#", $path, $m) && !$post) {
        try {
            $student = api('student', ['username' => $m[1]]);
        } catch (ApiError $e) {
            http_response_code(404);
            render('error', ['title' => 'No such student', 'nav' => 'students', 'message' => $e->getMessage()]);
        }
        $roster($student);
    }

    if ($path === '/students' && $post) {
        $in = [
            'email' => trim((string) ($_POST['email'] ?? '')),
            'username' => trim((string) ($_POST['username'] ?? '')),
            'full_name' => trim((string) ($_POST['full_name'] ?? '')),
            'send_email' => !empty($_POST['send_email']),
        ];
        try {
            $r = api('add-student', $in);
        } catch (ApiError $e) {
            keep_old($in + ['error' => $e->getMessage()]);
            redirect('/');
        }
        keep_secret(['kind' => 'new', 'username' => $r['username'], 'password' => $r['password'],
            'emailed' => $r['emailed'] ? $r['email'] : null, 'email_error' => $r['email_error']]);
        flash('success', "{$r['username']} is ready. Their websites start working in about 10 seconds.");
        redirect("/students/{$r['username']}");
    }

    // Server health
    if ($path === '/server' && !$post) {
        render('server', ['title' => 'Server', 'nav' => 'server', 'health' => api('health'), 'jobs' => api('jobs')]);
    }

    if (preg_match("#^/students/({$USER})/(reset|resend|password|quota|remove)$#", $path, $m) && $post) {
        [, $user, $what] = $m;
        $back = "/students/{$user}";
        try {
            switch ($what) {
                case 'reset':
                    $email = !empty($_POST['send_email']) ? trim((string) ($_POST['email'] ?? '')) : '';
                    $r = api('reset-password', ['username' => $user, 'email' => $email]);
                    keep_secret(['kind' => 'reset', 'username' => $user, 'password' => $r['password'],
                        'emailed' => $r['emailed'] ? $email : null, 'email_error' => $r['email_error']]);
                    flash('success', 'Done. The old password no longer works.');
                    break;
                case 'resend':
                    $r = api('resend', ['username' => $user, 'email' => trim((string) ($_POST['email'] ?? ''))]);
                    flash('success', "The login details were emailed to {$r['emailed']}.");
                    break;
                case 'password':
                    $r = api('show-password', ['username' => $user]);
                    if ($r['password'] === null) {
                        flash('info', 'There is no saved password for this student. Reset it to make a new one.');
                    } else {
                        keep_secret(['kind' => 'show', 'username' => $user, 'password' => $r['password']]);
                    }
                    break;
                case 'quota':
                    $r = api('set-quota', ['username' => $user, 'mb' => (int) ($_POST['mb'] ?? 0)]);
                    if ($r['warning']) {
                        flash('info', $r['warning']);
                    } else {
                        flash('success', "The disk limit is now " . fmt_mb($r['mb']) . '.');
                    }
                    break;
                case 'remove':
                    api('remove-student', ['username' => $user, 'confirm' => trim((string) ($_POST['confirm'] ?? ''))]);
                    flash('success', "{$user} was removed, with their files and database.");
                    redirect('/');
            }
        } catch (ApiError $e) {
            flash('error', $e->getMessage());
        }
        redirect($back);
    }

    // Semester tools and background jobs
    if ($path === '/semester' && !$post) {
        render('semester', ['title' => 'Semester', 'nav' => 'semester', 'settings' => api('settings'), 'jobs' => api('jobs'), 'old' => take_old()]);
    }

    if (preg_match('#^/semester/(bulk-add|smoke-test|remove-all)$#', $path, $m) && $post) {
        $args = ['kind' => $m[1]];
        if ($m[1] === 'bulk-add') {
            $args += ['emails' => (string) ($_POST['emails'] ?? ''), 'send_email' => !empty($_POST['send_email'])];
        }
        if ($m[1] === 'remove-all') {
            $args['confirm'] = trim((string) ($_POST['confirm'] ?? ''));
        }
        try {
            $r = api('job-start', $args);
        } catch (ApiError $e) {
            if ($m[1] === 'bulk-add') keep_old(['emails' => $args['emails']]);
            flash('error', $e->getMessage());
            redirect('/semester');
        }
        redirect("/jobs/{$r['id']}");
    }

    if (preg_match("#^/jobs/({$JOB})$#", $path, $m) && !$post) {
        render('job', ['title' => 'Job', 'nav' => 'semester', 'job' => api('job-status', ['id' => $m[1]])]);
    }

    if (preg_match("#^/jobs/({$JOB})\.json$#", $path, $m) && !$post) {
        $job = api('job-status', ['id' => $m[1]]);
        $job['state'] = job_state($job);
        json_out($job);
    }

    // Security
    if ($path === '/security' && !$post) {
        render('security', ['title' => 'Security', 'nav' => 'security', 'bans' => api('bans'),
            'allow' => api('allowlist'), 'settings' => api('settings'),
            'signins' => array_slice(api('logs', ['log' => 'admin', 'lines' => 500, 'filter' => 'sign']), 0, 12)]);
    }

    if (preg_match('#^/security/(unban|allowlist|test-email)$#', $path, $m) && $post) {
        try {
            switch ($m[1]) {
                case 'unban':
                    $r = api('unban', ['jail' => (string) ($_POST['jail'] ?? ''), 'address' => (string) ($_POST['address'] ?? '')]);
                    flash('success', "{$r['address']} is unblocked and can try again.");
                    break;
                case 'allowlist':
                    api('allowlist-set', ['entries' => (string) ($_POST['entries'] ?? '')]);
                    flash('success', 'Saved. Only the listed computers can open this panel.');
                    break;
                case 'test-email':
                    $r = api('test-email', ['email' => trim((string) ($_POST['email'] ?? ''))]);
                    flash('success', "A test email was sent to {$r['emailed']}. It should arrive within a minute.");
                    break;
            }
        } catch (ApiError $e) {
            flash('error', $e->getMessage());
        }
        redirect(($_POST['back'] ?? '') === '/' ? '/' : '/security');
    }

    // Logs
    if ($path === '/logs' && !$post) {
        $log = in_array($_GET['log'] ?? '', ['registration', 'provisioning', 'admin', 'privileged'], true) ? $_GET['log'] : 'registration';
        $lines = in_array((int) ($_GET['lines'] ?? 300), [100, 300, 1000], true) ? (int) ($_GET['lines'] ?? 300) : 300;
        $filters = [
            'time' => substr(trim((string) ($_GET['time'] ?? '')), 0, 100),
            'user' => substr(trim((string) ($_GET['user'] ?? '')), 0, 64),
            'event' => substr(trim((string) ($_GET['event'] ?? '')), 0, 120),
            'ip' => substr(trim((string) ($_GET['ip'] ?? '')), 0, 64),
        ];
        render('logs', ['title' => 'Logs', 'nav' => 'logs', 'log' => $log, 'lines' => $lines,
            'filters' => $filters,
            'rows' => api('logs', ['log' => $log, 'lines' => $lines] + $filters)]);
    }
} catch (ApiError $e) {
    http_response_code(500);
    render('error', ['title' => 'Something went wrong', 'nav' => '', 'message' => $e->getMessage()]);
}

http_response_code(404);
render('error', ['title' => 'Page not found', 'nav' => '', 'message' => 'There is nothing at this address.']);
