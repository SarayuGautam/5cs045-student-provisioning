<?php /** @var array $job */
[$cls, $label] = job_state($job);
$hints = [
    'smoke-test' => 'Checks logins, isolation and limits with two throwaway accounts.',
    'bulk-add' => 'Makes one account for each email address.',
    'remove-all' => 'Removes every student account, file and database.',
];
?>
<a class="back" href="/semester"><?= icon('arrow-left') ?>Semester</a>
<header class="page-head">
  <h1><?= h(job_label((string) $job['kind'])) ?></h1>
  <p class="lead"><span class="state state-<?= $cls ?>" data-job-state><?= h($label) ?></span> <?= h($hints[$job['kind']] ?? '') ?> Started by <?= h($job['admin'] ?? '?') ?> at <?= h(date('H:i', (int) $job['started'])) ?>.</p>
</header>

<section class="log-panel" data-job="<?= h($job['id']) ?>" data-done="<?= $job['done'] ? '1' : '0' ?>">
  <div class="log-head">
    <p data-job-summary><?= $job['done'] ? 'Finished.' : 'Running. This page follows along by itself, and you can leave it.' ?></p>
    <button type="button" class="btn btn-small btn-quiet" data-copy="#job-log"><?= icon('copy') ?><span>Copy</span></button>
  </div>
  <pre class="log" id="job-log" tabindex="0"><?= h($job['log']) ?></pre>
</section>
