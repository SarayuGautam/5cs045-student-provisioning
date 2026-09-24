<?php /** @var string $title @var string $content */ ?><!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title><?= h($title) ?> - 5CS045 admin</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='9' fill='%231f6b57'/%3E%3Ctext x='16' y='22' font-family='system-ui,sans-serif' font-size='15' font-weight='700' fill='white' text-anchor='middle'%3E5C%3C/text%3E%3C/svg%3E">
<link rel="preload" href="/assets/fonts/atkinson-next.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="<?= h(asset('app.css')) ?>">
<script src="<?= h(asset('app.js')) ?>" defer></script>
</head>
<body class="bare">
<?= $content ?>
</body>
</html>
