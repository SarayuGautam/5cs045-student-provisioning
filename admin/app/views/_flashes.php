<?php /** @var array $flashes */ if ($flashes): ?>
<div class="flashes" role="status">
  <?php foreach ($flashes as [$type, $message]): ?>
    <div class="flash flash-<?= h($type) ?>">
      <?= icon($type === 'success' ? 'check' : ($type === 'error' ? 'alert' : 'info')) ?>
      <p><?= h($message) ?></p>
      <button type="button" class="flash-close" data-dismiss aria-label="Dismiss"><?= icon('x') ?></button>
    </div>
  <?php endforeach; ?>
</div>
<?php endif; ?>
