<?php
/** Lab computers fail2ban has blocked, with an Unblock button. Shown on the Students page. @var array $bans */
$blocked = [];
foreach ($bans as $jail) {
    foreach ($jail['banned'] as $addr) {
        $blocked[] = [$jail['jail'], $addr];
    }
}
if (!$blocked) return;
?>
<section class="blocked" aria-label="Blocked computers">
  <h2><?= count($blocked) === 1 ? 'A computer is blocked from SSH' : count($blocked) . ' computers are blocked from SSH' ?></h2>
  <p class="small muted">After too many wrong passwords. If a lab cannot log in, unblock its address.</p>
  <ul class="blocked-list">
    <?php foreach ($blocked as [$jail, $addr]): ?>
      <li>
        <span class="mono"><?= h($addr) ?></span>
        <?php if ($jail === 'recidive'): ?><span class="small muted">for a week</span><?php endif; ?>
        <form method="post" action="/security/unban" data-busy>
          <?= csrf_field() ?>
          <input type="hidden" name="jail" value="<?= h($jail) ?>">
          <input type="hidden" name="address" value="<?= h($addr) ?>">
          <input type="hidden" name="back" value="/">
          <button class="btn btn-small" type="submit" data-busy-text="Unblocking…"><?= icon('unlock') ?><span>Unblock</span></button>
        </form>
      </li>
    <?php endforeach; ?>
  </ul>
</section>
