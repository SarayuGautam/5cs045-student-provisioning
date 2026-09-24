<?php
/** One student, shown beside the roster. @var array $s @var ?array $secret @var array $flashes */
$u = $s['username'];
$name = $s['full_name'] !== '' ? $s['full_name'] : $u;
$diskPct = percent($s['disk_used_mb'], $s['disk_limit_mb']);
$dbPct = percent($s['db_mb'], $s['db_limit_mb']);
$base = $s['server_url'];
$pw = ($secret && $secret['username'] === $u) ? (string) ($secret['password'] ?? '') : '';
?>
<div class="panel-body" data-person="<?= h($u) ?>">
  <a class="back" href="/"><?= icon('arrow-left') ?>All students</a>

  <?php require __DIR__ . '/_flashes.php'; ?>

  <header class="person-head">
    <h2><?= h($name) ?></h2>
    <p class="person-ids">
      <span class="mono" id="uname"><?= h($u) ?></span>
      <button type="button" class="icon-btn" data-copy="#uname" aria-label="Copy the username"><?= icon('copy') ?></button>
      <?php if ($s['online']): ?><span class="online">Signed in now</span><?php endif; ?>
    </p>
    <?php if ($s['email']): ?><p class="muted"><?= h($s['email']) ?></p><?php endif; ?>
  </header>

  <?php if ($pw !== ''): ?>
    <section class="secret" aria-labelledby="secret-title">
      <h3 id="secret-title"><?= $secret['kind'] === 'new' ? 'Their login' : ($secret['kind'] === 'reset' ? 'Their new password' : 'Their password') ?></h3>
      <p class="secret-pw"><span class="mono" id="secret-pw"><?= h($pw) ?></span>
        <button type="button" class="btn btn-small" data-copy="#secret-pw"><?= icon('copy') ?><span>Copy</span></button></p>
      <ol class="spell" aria-label="Spelled out">
        <?php foreach (str_split($pw) as $ch): ?>
          <li><span class="mono"><?= h($ch) ?></span><small><?= ctype_upper($ch) ? 'capital' : (ctype_digit($ch) ? 'number' : 'small') ?></small></li>
        <?php endforeach; ?>
      </ol>
      <p class="small">
        <?php if (!empty($secret['emailed'])): ?>
          Also emailed to <?= h($secret['emailed']) ?>.
        <?php elseif (!empty($secret['email_error'])): ?>
          <strong>The email could not be sent</strong> (<?= h($secret['email_error']) ?>), so read it out or write it down for them.
        <?php elseif ($secret['kind'] !== 'show'): ?>
          Not emailed. Read it out, or send it with "Email their login" below.
        <?php endif; ?>
        It works for SSH, SCP and phpMyAdmin. This box goes away when you leave the page.
      </p>
    </section>
  <?php endif; ?>

  <div class="fixes">
    <details class="fix" <?= $pw === '' && !$s['has_saved_password'] ? 'open' : '' ?>>
      <summary><?= icon('key') ?><span><strong>Reset password</strong><small>Makes a new one and shows it here. The old one stops working.</small></span></summary>
      <form method="post" action="/students/<?= h($u) ?>/reset" class="fix-form" data-busy>
        <?= csrf_field() ?>
        <label class="check">
          <input type="checkbox" name="send_email" value="1" <?= $s['email'] ? 'checked' : '' ?> data-toggles="reset-email-<?= h($u) ?>">
          <span>Also email it to them</span>
        </label>
        <label class="field" id="reset-email-<?= h($u) ?>">
          <span class="label">Email</span>
          <input type="email" name="email" value="<?= h($s['email'] ?? '') ?>" placeholder="name@<?= h($s['email'] ? substr((string) strrchr($s['email'], '@'), 1) : 'example.edu') ?>">
        </label>
        <div class="row"><button class="btn btn-primary" type="submit" data-busy-text="Resetting…">Reset the password</button></div>
      </form>
    </details>

    <details class="fix">
      <summary><?= icon('mail') ?><span><strong>Email their login</strong><small>Sends their current username and password again.</small></span></summary>
      <form method="post" action="/students/<?= h($u) ?>/resend" class="fix-form" data-busy>
        <?= csrf_field() ?>
        <?php if (!$s['has_saved_password']): ?><p class="small warn-warn">There is no saved password to send. Reset it instead.</p><?php endif; ?>
        <label class="field">
          <span class="label">Email</span>
          <input type="email" name="email" value="<?= h($s['email'] ?? '') ?>" required>
        </label>
        <div class="row"><button class="btn btn-primary" type="submit" data-busy-text="Sending…">Send it</button></div>
      </form>
    </details>

    <?php if ($s['has_saved_password'] && $pw === ''): ?>
      <form method="post" action="/students/<?= h($u) ?>/password" class="fix-inline">
        <?= csrf_field() ?>
        <button type="submit" class="fix-button"><?= icon('eye') ?><span><strong>Show their password</strong><small>For reading it out. Recorded in the admin log.</small></span></button>
      </form>
    <?php endif; ?>
  </div>

  <dl class="facts">
    <div>
      <dt>Disk</dt>
      <dd><?= h(fmt_mb($s['disk_used_mb'])) ?> <span class="muted">of <?= $s['disk_limit_mb'] ? h(fmt_mb($s['disk_limit_mb'])) : 'no limit' ?></span>
        <?php if ($s['disk_limit_mb']): ?><span class="meter meter-<?= level($diskPct) ?>"><span data-pct="<?= $diskPct ?>"></span></span><?php endif; ?></dd>
    </div>
    <div>
      <dt>Database</dt>
      <dd><?= h(fmt_mb($s['db_mb'])) ?> <span class="muted">of <?= h(fmt_mb($s['db_limit_mb'])) ?></span>
        <?php if ($s['db_locked']): ?><span class="warn-danger small">Full, so it is read-only</span><?php endif; ?>
        <span class="meter meter-<?= level($dbPct) ?>"><span data-pct="<?= $dbPct ?>"></span></span></dd>
    </div>
    <div>
      <dt>Last sign-in</dt>
      <dd title="<?= h(fmt_date($s['last_login'])) ?>"><?= $s['last_login'] ? h(fmt_ago($s['last_login'])) : 'Never' ?></dd>
    </div>
    <div>
      <dt>Account made</dt>
      <dd><?= h(fmt_date($s['registered_at']) ?: 'Unknown') ?></dd>
    </div>
  </dl>

  <?php if ($base !== ''): ?>
    <p class="sites">
      <?php foreach (['workshops' => 'Workshops', 'assessment' => 'Assessment', 'exam' => 'Exam'] as $folder => $label): ?>
        <a href="<?= h("{$base}/~{$u}/{$folder}/") ?>" target="_blank" rel="noopener noreferrer"><?= h($label) ?><?= icon('external') ?></a>
      <?php endforeach; ?>
    </p>
  <?php endif; ?>

  <div class="fixes fixes-quiet">
    <details class="fix">
      <summary><?= icon('server') ?><span><strong>Change disk limit</strong><small>Now <?= $s['disk_limit_mb'] ? h(fmt_mb($s['disk_limit_mb'])) : 'not enforced' ?>. The usual limit is <?= h(fmt_mb($s['default_quota_mb'])) ?>.</small></span></summary>
      <form method="post" action="/students/<?= h($u) ?>/quota" class="fix-form" data-busy>
        <?= csrf_field() ?>
        <label class="field">
          <span class="label">Limit in MB</span>
          <input type="number" name="mb" min="50" max="20480" value="<?= (int) ($s['disk_limit_mb'] ?: $s['default_quota_mb']) ?>" required inputmode="numeric">
        </label>
        <div class="chips" data-fill-target="mb">
          <?php foreach ([500, 1024, 2048] as $preset): ?>
            <button type="button" class="chip" data-fill="<?= $preset ?>"><?= h(fmt_mb($preset)) ?></button>
          <?php endforeach; ?>
        </div>
        <div class="row"><button class="btn btn-primary" type="submit" data-busy-text="Saving…">Save limit</button></div>
      </form>
    </details>

    <details class="fix fix-danger">
      <summary><?= icon('trash') ?><span><strong>Remove this student</strong><small>Deletes the account, files and database. There is no backup.</small></span></summary>
      <form method="post" action="/students/<?= h($u) ?>/remove" class="fix-form" data-busy>
        <?= csrf_field() ?>
        <p class="small">This deletes <?= h(fmt_mb($s['disk_used_mb'])) ?> of files and their database for good. They can register again afterwards.</p>
        <label class="field">
          <span class="label">Type <span class="mono"><?= h($u) ?></span> to confirm</span>
          <input name="confirm" autocomplete="off" autocapitalize="off" spellcheck="false" data-confirm="<?= h($u) ?>" required>
        </label>
        <div class="row"><button type="submit" class="btn btn-danger" disabled data-busy-text="Removing…">Remove <?= h($u) ?></button></div>
      </form>
    </details>
  </div>
</div>
