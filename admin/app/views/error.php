<?php /** @var string $title @var string $message @var ?array $back */ [$backUrl, $backLabel] = $back ?? ['/', 'Back to the students']; ?>
<header class="page-head">
  <h1><?= h($title) ?></h1>
  <p class="lead"><?= h($message) ?></p>
</header>
<p><a class="btn" href="<?= h($backUrl) ?>"><?= icon('arrow-left') ?><span><?= h($backLabel) ?></span></a></p>
