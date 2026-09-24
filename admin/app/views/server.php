<?php
/** @var array $health @var array $jobs */
$disk = $health['disk'];
$mem = $health['memory'];
$loadPct = percent($health['load'], $health['cores']);
$serviceNames = [
    'nginx' => ['Websites', 'nginx'],
    'php8.3-fpm' => ['PHP', 'php8.3-fpm'],
    'mariadb' => ['Databases', 'MariaDB'],
    'ssh' => ['SSH and SCP', 'ssh'],
    'fail2ban' => ['Password-guessing protection', 'fail2ban'],
    'cron' => ['Scheduled checks', 'cron'],
    'systemd-logind' => ['Login sessions', 'logind'],
];
$down = array_filter($health['services'], fn($state) => $state !== 'active');
?>
<header class="page-head">
  <h1>Server</h1>
  <p class="lead">
    <?php if ($health['alerts']): ?>
      <?= count($health['alerts']) === 1 ? 'One thing needs attention.' : count($health['alerts']) . ' things need attention.' ?>
    <?php else: ?>
      Everything is running normally.
    <?php endif; ?>
    Up for <?= h(fmt_duration($health['uptime'])) ?>. Checked at <?= h(date('H:i')) ?>, <a href="/server">check again</a>.
  </p>
</header>

<?php if ($health['alerts']): ?>
  <ul class="alerts">
    <?php foreach ($health['alerts'] as [$lvl, $text]): ?>
      <li class="alert alert-<?= h($lvl) ?>"><?= icon('alert') ?><span><?= h($text) ?></span></li>
    <?php endforeach; ?>
  </ul>
<?php endif; ?>

<section class="section" aria-labelledby="use-title">
  <h2 id="use-title">How full it is</h2>
  <dl class="gauges">
    <div>
      <dt>Disk</dt>
      <dd><strong><?= (int) $disk['percent'] ?>%</strong> <span class="muted"><?= h(fmt_bytes($disk['used'])) ?> of <?= h(fmt_bytes($disk['total'])) ?> used</span></dd>
      <dd class="meter meter-<?= level((int) $disk['percent']) ?>"><span data-pct="<?= (int) $disk['percent'] ?>"></span></dd>
    </div>
    <div>
      <dt>Memory</dt>
      <dd><strong><?= (int) $mem['percent'] ?>%</strong> <span class="muted"><?= h(fmt_bytes($mem['available'])) ?> free of <?= h(fmt_bytes($mem['total'])) ?></span></dd>
      <dd class="meter meter-<?= level((int) $mem['percent']) ?>"><span data-pct="<?= (int) $mem['percent'] ?>"></span></dd>
    </div>
    <div>
      <dt>Processor</dt>
      <dd><strong><?= $loadPct < 50 ? 'Quiet' : ($loadPct < 90 ? 'Busy' : 'Very busy') ?></strong> <span class="muted">load <?= h(number_format($health['load'], 1)) ?> on <?= (int) $health['cores'] ?> cores</span></dd>
      <dd class="meter meter-<?= level($loadPct) ?>"><span data-pct="<?= $loadPct ?>"></span></dd>
    </div>
    <div>
      <dt>Students</dt>
      <dd><strong><?= number_format($health['students']) ?></strong> <span class="muted"><?= $health['online'] ? number_format($health['online']) . ' signed in now' : 'nobody signed in now' ?><?= $health['sessions'] !== null ? ', ' . number_format($health['sessions']) . ' login session' . ($health['sessions'] === 1 ? '' : 's') . ' in total' : '' ?></span></dd>
    </div>
  </dl>
</section>

<section class="section" aria-labelledby="svc-title">
  <h2 id="svc-title">Services</h2>
  <p class="small muted"><?= $down ? 'Stopped services are listed first.' : 'All seven are running.' ?> Disk limits for students are <?= $health['quotas_on'] ? 'on' : '<strong class="warn-danger">off</strong>' ?>.</p>
  <ul class="services">
    <?php
    $svcs = $health['services'];
    uasort($svcs, fn($a, $b) => ($a === 'active') <=> ($b === 'active'));
    foreach ($svcs as $svc => $state): [$label, $tech] = $serviceNames[$svc] ?? [$svc, $svc]; ?>
      <li class="<?= $state === 'active' ? '' : 'is-down' ?>">
        <span><?= h($label) ?> <span class="muted small mono"><?= h($tech) ?></span></span>
        <span class="state"><?= $state === 'active' ? icon('check') . 'Running' : icon('alert') . h(ucfirst($state)) ?></span>
      </li>
    <?php endforeach; ?>
  </ul>
</section>

<?php if ($jobs): ?>
  <section class="section" aria-labelledby="jobs-title">
    <h2 id="jobs-title">Recent jobs</h2>
    <?php require __DIR__ . '/_jobs.php'; ?>
  </section>
<?php endif; ?>
