<?php
/** @var array $rows  Log lines, newest first. "[time] [address] who: what" is shown as time, what happened, then the address. */
?>
<ol class="log-list">
  <?php foreach ($rows as $line):
      $bad = preg_match('/FAIL|ERROR|WARNING|denied|refused/i', $line);
      $time = null;
      $addr = null;
      if (preg_match('/^\[([^\]]+)\]\s*(.*)$/s', $line, $m) && ($t = strtotime($m[1])) !== false) {
          $time = $t;
          $line = $m[2];
      }
      if (preg_match('/^\[([0-9a-fA-F.:]+)\]\s*(.*)$/s', $line, $m)) {
          $addr = $m[1];
          $line = $m[2];
      }
      $line = preg_replace('/^([a-z_][a-z0-9_-]*): /', '$1 ', $line);
  ?>
    <li class="<?= $bad ? 'is-bad' : '' ?>">
      <?php if ($time): ?><time datetime="<?= h(date(DATE_ATOM, $time)) ?>"><?= h(date('j M, H:i', $time)) ?></time><?php endif; ?>
      <span class="log-text"><?= h($line) ?></span>
      <?php if ($addr): ?><span class="log-addr mono"><?= h($addr) ?></span><?php endif; ?>
    </li>
  <?php endforeach; ?>
</ol>
