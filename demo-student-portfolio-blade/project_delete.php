<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

$userId = require_login();
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: index.php');
    exit;
}
verify_csrf();

$stmt = $pdo->prepare('DELETE FROM projects WHERE id = ? AND user_id = ?');
$stmt->execute([(int) ($_POST['id'] ?? 0), $userId]);
flash('Project deleted.');
header('Location: index.php');
