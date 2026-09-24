<?php /** @var string $log @var int $lines @var string $filter @var array $rows */
$tabs = [
    'registration' => ['Registrations', 'Sign-ups on the public page, and why any failed.'],
    'provisioning' => ['Accounts', 'Accounts made and removed, limits applied, and warnings.'],
    'admin' => ['Admin panel', 'Every sign-in and change made on this panel.'],
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

<form method="get" action="/logs" class="filter">
  <input type="hidden" name="log" value="<?= h($log) ?>">
  <label class="finder finder-small">
    <?= icon('search') ?>
    <input type="search" name="q" value="<?= h($filter) ?>" placeholder="Username, address or FAILED" aria-label="Filter">
  </label>
  <select name="lines" aria-label="How far back" data-autosubmit>
    <?php foreach ([100, 300, 1000] as $n): ?>
      <option value="<?= $n ?>"<?= $n === $lines ? ' selected' : '' ?>>Last <?= $n ?> lines</option>
    <?php endforeach; ?>
  </select>
  <button class="btn" type="submit">Filter</button>
</form>

<?php if (!$rows): ?>
  <p class="nothing"><?= $filter !== '' ? 'No lines match "' . h($filter) . '".' : 'Nothing has been written to this log yet.' ?></p>
<?php else: ?>
  <?php require __DIR__ . '/_loglines.php'; ?>
<?php endif; ?>
