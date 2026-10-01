<?php
/** @var string $log @var int $lines @var array $filters @var array $rows */
$tabs = [
    'registration' => ['Registrations', 'Sign-ups on the public page, and why any failed.'],
    'provisioning' => ['Accounts', 'Accounts made and removed, limits applied, and warnings.'],
    'admin' => ['Admin panel', 'Every sign-in and change made on this panel.'],
    'privileged' => ['Privileged / SSH', 'Privileged SSH logins and sudo commands. Student SSH activity is excluded.'],
];

$columns = [
    'registration' => ['time', 'event', 'ip'],
    'provisioning' => ['time', 'event'],
    'admin' => ['time', 'user', 'event', 'ip'],
    'privileged' => ['time', 'user', 'event', 'ip'],
];

$columnLabels = [
    'time' => 'Time',
    'user' => 'User',
    'event' => 'Event / Details',
    'ip' => 'IP address',
];

$columnPlaceholders = [
    'time' => 'Filter time',
    'user' => 'Filter user',
    'event' => 'Filter event or command',
    'ip' => 'Filter IP',
];
?>
<header class="page-head">
  <h1>Logs</h1>
  <p class="lead"><?= h($tabs[$log][1]) ?> Newest first.</p>
</header>

<nav class="tabs" aria-label="Which log">
  <?php foreach ($tabs as $key => [$label]): ?>
    <a href="/logs?log=<?= $key ?>"<?= $key === $log ? ' aria-current="page"' : '' ?>><?= h($label) ?></a>
  <?php endforeach; ?>
</nav>

<form id="log-filters" method="get" action="/logs" class="log-filter-form">
  <input type="hidden" name="log" value="<?= h($log) ?>">
  <div class="log-filter-spacer" aria-hidden="true"></div>
  <select name="lines" aria-label="How far back" data-autosubmit>
    <?php foreach ([100, 300, 1000] as $n): ?>
      <option value="<?= $n ?>"<?= $n === $lines ? ' selected' : '' ?>>Last <?= $n ?> lines</option>
    <?php endforeach; ?>
  </select>
  <button class="btn" type="submit">Apply filters</button>
  <a class="btn btn-quiet" href="/logs?log=<?= h($log) ?>">Clear</a>
</form>

<?php if (!$rows): ?>
  <?php
    $activeFilters = array_filter($filters ?? [], fn(string $v): bool => $v !== '');
    $filterSummary = $activeFilters ? 'the selected filters' : 'the current log';
  ?>
  <p class="nothing">No entries match <?= h($filterSummary) ?>.</p>
<?php else: ?>
  <?php require __DIR__ . '/_loglines.php'; ?>
<?php endif; ?>
