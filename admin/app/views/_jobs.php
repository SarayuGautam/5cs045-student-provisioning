<?php /** @var array $jobs */ ?>
<ul class="jobs">
  <?php foreach (array_slice($jobs, 0, 6) as $job): [$cls, $label] = job_state($job); ?>
    <li>
      <a href="/jobs/<?= h($job['id']) ?>">
        <span><strong><?= h(job_label((string) $job['kind'])) ?></strong> <span class="muted">by <?= h($job['admin'] ?? '?') ?>, <?= h(strtolower(fmt_ago(date(DATE_ATOM, (int) $job['started'])))) ?></span></span>
        <span class="state state-<?= $cls ?>"><?= h($label) ?></span>
      </a>
    </li>
  <?php endforeach; ?>
</ul>
