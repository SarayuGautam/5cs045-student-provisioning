<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

// Shows the create form (no id) or edit form (?id=N). Saving is in project_save.php.
$userId = require_login();
$project = ['id' => null, 'title' => '', 'description' => '', 'tech' => ''];

if (isset($_GET['id'])) {
    $stmt = $pdo->prepare('SELECT id, title, description, tech FROM projects WHERE id = ? AND user_id = ?');
    $stmt->execute([(int) $_GET['id'], $userId]);
    $found = $stmt->fetch();
    if (!$found) {
        http_response_code(404);
        exit('Project not found.');
    }
    $project = $found;
}

$old = $_SESSION['old'] ?? null;
$errors = $_SESSION['errors'] ?? [];
unset($_SESSION['old'], $_SESSION['errors']);
if (is_array($old)) {
    $project = array_merge($project, $old);
}
render('form', ['project' => $project, 'errors' => $errors]);
