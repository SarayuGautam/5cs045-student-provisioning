<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

$userId = require_login();
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: index.php');
    exit;
}
verify_csrf();

$id = (int) ($_POST['id'] ?? 0);
[$data, $errors] = validate_project($_POST);

if ($errors) {
    $_SESSION['errors'] = $errors;
    $_SESSION['old'] = $data;
    header('Location: project_form.php' . ($id ? '?id=' . $id : ''));
    exit;
}

if ($id) {
    // user_id in the WHERE clause stops one user editing another user's project.
    $stmt = $pdo->prepare('UPDATE projects SET title = ?, description = ?, tech = ? WHERE id = ? AND user_id = ?');
    $stmt->execute([$data['title'], $data['description'], $data['tech'], $id, $userId]);
    flash('Project updated.');
} else {
    $stmt = $pdo->prepare('INSERT INTO projects (user_id, title, description, tech) VALUES (?, ?, ?, ?)');
    $stmt->execute([$userId, $data['title'], $data['description'], $data['tech']]);
    flash('Project added.');
}
header('Location: index.php');
