<?php
/**
 * The Students page: the roster on the left, one student (or "add a student") on the right.
 * @var array $students @var ?array $s @var ?array $secret @var array $settings @var array $bans
 * @var array $health @var array $old @var array $flashes
 */
$selected = $s['username'] ?? null;
$alerts = $health['alerts'];
$online = count(array_filter($students, fn($x) => $x['online']));
?>
<section class="roster<?= $selected ? ' has-selection' : '' ?>" aria-label="Students">
  <div class="roster-head">
    <h1>Who needs help?</h1>
    <?php if ($alerts): ?>
      <?php $more = count($alerts) - 1; ?>
      <p class="status status-bad"><?= icon('alert') ?><span><?= h(rtrim($alerts[0][1], '.')) ?><?= $more ? ', and ' . ($more === 1 ? 'one other problem' : "{$more} other problems") : '' ?>. <a href="/server">See the server</a></span></p>
    <?php else: ?>
      <p class="status">The server is running normally. <?= number_format(count($students)) ?> student<?= count($students) === 1 ? '' : 's' ?>, <?= $online ? number_format($online) . ' signed in now.' : 'nobody signed in right now.' ?></p>
    <?php endif; ?>
    <label class="finder">
      <?= icon('search') ?>
      <input type="search" id="finder" placeholder="Name, username or email" aria-label="Find a student"
             autocomplete="off" spellcheck="false" <?= $selected ? '' : 'autofocus' ?> data-finder>
      <kbd aria-hidden="true">/</kbd>
      <button type="button" class="icon-btn finder-clear" aria-label="Clear the search" data-clear><?= icon('x') ?></button>
    </label>
    <?php if (!$selected) require __DIR__ . '/_blocked.php'; ?>
  </div>

  <?php if (!$students): ?>
    <div class="empty">
      <p><strong>No students yet.</strong></p>
      <p>They appear here as soon as they register at <?= h($settings['server_url'] ?: 'the registration page') ?>. You can also add one yourself<?= $selected ? '' : ' on the right' ?>.</p>
    </div>
  <?php else: ?>
    <ol class="people" data-people>
      <?php foreach ($students as $p):
          $pct = percent($p['disk_used_mb'], $p['disk_limit_mb']);
          $name = $p['full_name'] !== '' ? $p['full_name'] : $p['username'];
      ?>
        <li>
          <a class="person<?= $p['username'] === $selected ? ' is-selected' : '' ?>" href="/students/<?= h($p['username']) ?>"
             data-search="<?= h(strtolower($p['username'] . ' ' . $p['full_name'] . ' ' . ($p['email'] ?? ''))) ?>"
             <?= $p['username'] === $selected ? 'aria-current="true"' : '' ?>>
            <span class="person-name"><?= h($name) ?></span>
            <span class="person-meta"><span class="mono"><?= h($p['username']) ?></span><?php if ($p['online']): ?><span class="online">Signed in now</span><?php endif; ?></span>
            <span class="person-side">
              <?php if ($p['disk_limit_mb'] && $pct >= 80): ?>
                <span class="warn-<?= level($pct) ?>">Disk <?= $pct ?>% full</span>
              <?php elseif ($p['db_locked']): ?>
                <span class="warn-danger">Database full</span>
              <?php else: ?>
                <span class="muted" title="<?= h(fmt_date($p['last_login'])) ?>"><?= h(fmt_last($p['last_login'])) ?></span>
              <?php endif; ?>
            </span>
          </a>
        </li>
      <?php endforeach; ?>
    </ol>
    <p class="people-none" hidden>Nobody matches that. Check the spelling, or add them on the right.</p>
  <?php endif; ?>
</section>

<aside class="panel" id="panel" aria-label="<?= $selected ? h($selected) : 'Add a student' ?>" data-panel>
  <?php if ($selected): ?>
    <?php require __DIR__ . '/_person.php'; ?>
  <?php else: ?>
    <?php require __DIR__ . '/_home.php'; ?>
  <?php endif; ?>
</aside>
