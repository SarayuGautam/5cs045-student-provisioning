<?php
/** The right-hand side of the Students page when nobody is selected. @var array $settings @var array $bans @var array $old @var array $flashes */
$domain = $settings['email_domain'];
?>
<div class="panel-body">
  <?php require __DIR__ . '/_flashes.php'; ?>

  <?php require __DIR__ . '/_blocked.php'; ?>

  <section aria-labelledby="add-title">
    <h2 id="add-title">Add a student</h2>
    <p class="small muted">Most students register themselves. Use this for anyone who cannot.</p>
    <?php if (!empty($old['error'])): ?>
      <div class="flash flash-error" role="alert"><?= icon('alert') ?><p><?= h($old['error']) ?></p></div>
    <?php endif; ?>
    <form method="post" action="/students" class="stack" id="add-form" data-busy>
      <?= csrf_field() ?>
      <label class="field">
        <span class="label">Their email</span>
        <input type="email" name="email" value="<?= h($old['email'] ?? '') ?>" placeholder="<?= h($domain ? "firstname.lastname@{$domain}" : 'name@example.edu') ?>" autocomplete="off" data-email-source <?= !empty($old['error']) ? 'autofocus' : '' ?>>
        <span class="hint">Their username is made from it: <span class="mono">sarayu.gautam@…</span> becomes <span class="mono">sarayu_gautam</span>.</span>
      </label>
      <details class="more" <?= !empty($old['username']) || !empty($old['full_name']) ? 'open' : '' ?>>
        <summary>Choose the username, or add their name</summary>
        <div class="stack">
          <label class="field">
            <span class="label">Username</span>
            <input name="username" value="<?= h($old['username'] ?? '') ?>" pattern="[a-z][a-z0-9_]{2,31}" autocapitalize="off" spellcheck="false" autocomplete="off">
            <span class="hint">3 to 32 lowercase letters, numbers or _, starting with a letter.</span>
          </label>
          <label class="field">
            <span class="label">Full name</span>
            <input name="full_name" value="<?= h($old['full_name'] ?? '') ?>" autocomplete="off">
          </label>
        </div>
      </details>
      <label class="check">
        <input type="checkbox" name="send_email" value="1" <?= ($old['send_email'] ?? true) ? 'checked' : '' ?> data-needs-email>
        <span>Email them their login <span class="muted small" data-needs-email-hint>(add their email first)</span></span>
      </label>
      <div class="row"><button type="submit" class="btn btn-primary" data-busy-text="Creating…"><?= icon('plus') ?><span>Create account</span></button></div>
    </form>
  </section>

  <p class="small muted panel-foot">A whole class at once? Use <a href="/semester">Semester</a>.</p>
</div>
