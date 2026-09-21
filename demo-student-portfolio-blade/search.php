<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

// JSON endpoint used by the Fetch API search box on the home page.
header('Content-Type: application/json; charset=utf-8');
$userId = current_user_id();
if ($userId === null) {
    http_response_code(401);
    echo json_encode(['error' => 'Not logged in']);
    exit;
}

$q = trim((string) ($_GET['q'] ?? ''));
$like = '%' . str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], $q) . '%';
$stmt = $pdo->prepare(
    'SELECT id, title, description, tech FROM projects
     WHERE user_id = ? AND (title LIKE ? OR tech LIKE ?)
     ORDER BY created_at DESC LIMIT 50'
);
$stmt->execute([$userId, $like, $like]);
echo json_encode($stmt->fetchAll(), JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP);
