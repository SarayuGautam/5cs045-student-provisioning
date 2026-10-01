<?php /** @var string $log @var int $lines @var array $filters @var array $rows */ ?>
<?php
function log_table_fields(string $line): array {
    $time = '';
    $ip = '';
    $user = '';
    $event = trim($line);

    if (preg_match('/^\[([^\]]+)\]\s*(?:\[([^\]]+)\]\s*)?([^:]+):\s*(.*)$/', $line, $m)) {
        $time = $m[1];
        $ip = $m[2] ?? '';
        $user = trim($m[3]);
        $event = trim($m[4]);
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
    } elseif (preg_match('/\b(?:created|removed|reset|quota|password)\b/i', $event)) {
        $type = 'account';
        $label = 'ACCOUNT';
    }

    return compact('time', 'user', 'event', 'ip', 'type', 'label');
}
?>
<div class="log-table-wrap">
  <table class="log-table">
    <thead>
      <tr>
        <th scope="col">Time</th>
        <th scope="col">User</th>
        <th scope="col">Event / Details</th>
        <th scope="col">IP address</th>
      </tr>
      <tr class="log-filter-row">
        <th>
          <input type="search" form="log-filters" name="time" value="<?= h($filters['time'] ?? '') ?>" placeholder="Filter time" aria-label="Filter by time">
        </th>
        <th>
          <input type="search" form="log-filters" name="user" value="<?= h($filters['user'] ?? '') ?>" placeholder="Filter user" aria-label="Filter by user">
        </th>
        <th>
          <input type="search" form="log-filters" name="event" value="<?= h($filters['event'] ?? '') ?>" placeholder="Filter event or command" aria-label="Filter by event or command">
        </th>
        <th>
          <input type="search" form="log-filters" name="ip" value="<?= h($filters['ip'] ?? '') ?>" placeholder="Filter IP" aria-label="Filter by IP address">
        </th>
      </tr>
    </thead>
    <tbody>
      <?php foreach ($rows as $line):
          $row = log_table_fields($line);
      ?>
        <tr class="<?= $row['type'] === 'bad' ? 'is-bad' : '' ?>">
          <td class="log-time">
            <?= $row['time'] !== '' ? h(date('j M Y, H:i:s', strtotime($row['time']) ?: time())) : '—' ?>
          </td>
          <td class="log-user mono"><?= $row['user'] !== '' ? h($row['user']) : '—' ?></td>
          <td class="log-event">
            <span class="log-badge log-badge-<?= h($row['type']) ?>"><?= h($row['label']) ?></span>
            <span class="log-details"><?= h($row['event']) ?></span>
          </td>
          <td class="log-ip mono"><?= $row['ip'] !== '' ? h($row['ip']) : '—' ?></td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
</div>
