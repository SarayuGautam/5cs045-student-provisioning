<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

$userId = require_login();
$stmt = $pdo->prepare('SELECT id, title, description, tech FROM projects WHERE user_id = ? ORDER BY created_at DESC');
$stmt->execute([$userId]);
render('index', ['projects' => $stmt->fetchAll()]);
