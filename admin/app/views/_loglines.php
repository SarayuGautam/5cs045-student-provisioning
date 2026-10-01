<?php
/** @var string $log @var int $lines @var array $filters @var array $rows @var array $columns @var array $columnLabels @var array $columnPlaceholders */
?>
<?php
function log_table_fields(string $line): array {
    $time = '';
    $ip = '';
    $user = '';
    $event = trim($line);

    if (preg_match('/^\[([^\]]+)\]\s*(.*)$/', $line, $m)) {
        $time = trim($m[1]);
        $rest = $m[2];

        if (preg_match('/^\[([0-9a-fA-F:.]+)\]\s*(.*)$/', $rest, $m2)) {
            $ip = $m2[1];
            $rest = $m2[2];
        }

        if (preg_match('/^([^:]+):\s*(.*)$/', $rest, $m3)) {
            $user = trim($m3[1]);
            $event = trim($m3[2]);
        } else {
            $event = trim($rest);
        }
    }

    $type = 'event';
    $label = 'EVENT';

    if (preg_match('/^FAILED\b|\bFAILED\s+(?:SSH\s+)?login/i', $event)) {
        $type = 'bad';
        $label = 'FAILED';
    } elseif (preg_match('/^SSH login accepted/i', $event)) {
        $type = 'ssh';
        $label = 'SSH LOGIN';
    } elseif (preg_match('/^sudo as /i', $event)) {
        $type = 'sudo';
        $label = 'SUDO';
    } elseif (preg_match('/\bsigned in\b/i', $event)) {
        $type = 'login';
        $label = 'PANEL LOGIN';
    } elseif (preg_match('/\b(?:created|removed|reset|quota|password|adding|creating)\b/i', $event)) {
        $type = 'account';
        $label = 'ACCOUNT';
    }

    return compact('time', 'user', 'event', 'ip', 'type', 'label');
}
?>
<div class="log-table-wrap">
  <table class="log-table log-table-<?= h($log) ?>">
    <colgroup>
      <?php foreach ($columns as $column): ?>
        <col class="log-col-<?= h($column) ?>">
      <?php endforeach; ?>
    </colgroup>
    <thead>
      <tr>
        <?php foreach ($columns as $column): ?>
          <th scope="col"><?= h($columnLabels[$column]) ?></th>
        <?php endforeach; ?>
      </tr>
      <tr class="log-filter-row">
        <?php foreach ($columns as $column): ?>
          <th>
            <input
              type="search"
              form="log-filters"
              name="<?= h($column) ?>"
              value="<?= h($filters[$column] ?? '') ?>"
              placeholder="<?= h($columnPlaceholders[$column]) ?>"
              aria-label="<?= h($columnLabels[$column]) ?>"
            >
          </th>
        <?php endforeach; ?>
      </tr>
    </thead>
    <tbody>
      <?php foreach ($rows as $line):
          $row = log_table_fields($line);
      ?>
        <tr class="<?= $row['type'] === 'bad' ? 'is-bad' : '' ?>">
          <?php foreach ($columns as $column): ?>
            <?php if ($column === 'time'): ?>
              <td class="log-time">
                <?= $row['time'] !== '' ? h(date('j M Y, H:i:s', strtotime($row['time']) ?: time())) : '—' ?>
              </td>
            <?php elseif ($column === 'user'): ?>
              <td class="log-user mono"><?= $row['user'] !== '' ? h($row['user']) : '—' ?></td>
            <?php elseif ($column === 'ip'): ?>
              <td class="log-ip mono"><?= $row['ip'] !== '' ? h($row['ip']) : '—' ?></td>
            <?php else: ?>
              <td class="log-event">
                <span class="log-badge log-badge-<?= h($row['type']) ?>"><?= h($row['label']) ?></span>
                <span class="log-details"><?= h($row['event']) ?></span>
              </td>
            <?php endif; ?>
          <?php endforeach; ?>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
</div>
