<?php /** @var array $settings @var array $jobs @var array $old */
$n = (int) $settings['students'];
$domain = $settings['email_domain'];
?>
<header class="page-head">
  <h1>Semester</h1>
  <p class="lead">Jobs for the start and end of term. They carry on in the background, so you can leave the page.</p>
</header>

<section class="section" id="bulk" aria-labelledby="bulk-title">
  <h2 id="bulk-title">Add a whole class</h2>
  <p class="muted">Paste their email addresses, one per line or separated by commas. Each student gets an account named after their email<?= $domain ? '. Only @' . h($domain) . ' addresses are accepted' : '' ?>. Anyone who already has an account is skipped.</p>
  <form method="post" action="/semester/bulk-add" class="stack" data-busy>
    <?= csrf_field() ?>
    <label class="field">
      <span class="label">Email addresses <span class="muted" data-count-for="emails"></span></span>
      <textarea name="emails" id="emails" rows="8" spellcheck="false" class="mono" placeholder="<?= h($domain ? "sarayu.gautam@{$domain}\nrakshyak.basyal@{$domain}" : "sarayu.gautam@example.edu\nrakshyak.basyal@example.edu") ?>" required><?= h($old['emails'] ?? '') ?></textarea>
    </label>
    <label class="check">
      <input type="checkbox" name="send_email" value="1" checked>
      <span>Email each student their login</span>
    </label>
    <div class="row"><button class="btn btn-primary" type="submit" data-busy-text="Starting…"><?= icon('students') ?><span>Create the accounts</span></button></div>
  </form>
</section>

<section class="section" aria-labelledby="check-title">
  <h2 id="check-title">Health check</h2>
  <p class="muted">Makes two throwaway accounts, checks that logins work, that students cannot see each other's files and that every limit is in place, then deletes them. About a minute. Run it after every update.</p>
  <form method="post" action="/semester/smoke-test" data-busy>
    <?= csrf_field() ?>
    <button class="btn" type="submit" data-busy-text="Starting…"><?= icon('play') ?><span>Run the health check</span></button>
  </form>
</section>

<?php if ($jobs): ?>
  <section class="section" aria-labelledby="jobs-title">
    <h2 id="jobs-title">Recent jobs</h2>
    <?php require __DIR__ . '/_jobs.php'; ?>
  </section>
<?php endif; ?>

<section class="section section-danger" aria-labelledby="wipe-title">
  <h2 id="wipe-title">End of semester: remove every student</h2>
  <p class="muted">Deletes all <?= number_format($n) ?> student account<?= $n === 1 ? '' : 's' ?> with their files and databases. There is no backup, so ask students to download their work first.</p>
  <?php if ($n > 0): ?>
    <details class="fix fix-danger">
      <summary><?= icon('trash') ?><span><strong>Remove every student</strong><small>Asks you to confirm first.</small></span></summary>
      <form method="post" action="/semester/remove-all" class="fix-form" data-busy>
        <?= csrf_field() ?>
        <label class="field">
          <span class="label">Type <span class="mono">DELETE <?= $n ?></span> to confirm</span>
          <input name="confirm" autocomplete="off" spellcheck="false" data-confirm="DELETE <?= $n ?>" required>
        </label>
        <div class="row"><button type="submit" class="btn btn-danger" disabled data-busy-text="Starting…">Remove all <?= number_format($n) ?></button></div>
      </form>
    </details>
  <?php endif; ?>
</section>
