<?php /** @var array $admin_users @var array $panel_accounts @var ?array $secret */ ?>
<header class="page-head">
  <h1>Admin accounts</h1>
  <p class="lead">Manage non-student server accounts and who can use this panel.</p>
</header>

<?php if ($secret && ($secret['kind'] ?? '') === 'panel-account'): ?>
<section class="secret" aria-labelledby="new-account-title">
  <h2 id="new-account-title">New admin account</h2>
  <p class="muted">The password below is shown once. It was also emailed when an email address was provided and the mail server accepted it.</p>
  <p><strong>Username:</strong> <span class="mono"><?= h($secret['username']) ?></span></p>
  <p class="secret-pw"><span class="mono" id="new-account-password"><?= h($secret['password']) ?></span>
    <button type="button" class="btn btn-small" data-copy="#new-account-password"><?= icon('copy') ?><span>Copy password</span></button>
  </p>
  <p class="small">
    Panel admin: <?= !empty($secret['admin']) ? 'yes - Students and Server access' : 'no' ?>.
    <?php if (($secret['email'] ?? '') !== ''): ?>Email: <?= h($secret['email']) ?>.<?php endif; ?>
    <?php if (!empty($secret['email_sent'])): ?>
      Credentials were emailed successfully.
    <?php elseif (!empty($secret['email_error'])): ?>
      <strong class="warn-danger">The credential email could not be sent:</strong> <?= h($secret['email_error']) ?>
    <?php elseif (!empty($secret['email']) && !empty($secret['admin'])): ?>
      The account was created, but no credential email was sent.
    <?php endif; ?>
    This box goes away when you leave the page.
  </p>
</section>
<?php endif; ?>

<section class="section" id="panel-accounts" aria-labelledby="panel-accounts-title">
  <h2 id="panel-accounts-title">Non-student server accounts</h2>
  <p class="muted">These are normal Linux accounts, separate from student accounts. They do not get sudo, student websites, student databases, or student quotas.</p>

  <?php if ($panel_accounts): ?>
    <ul class="blocked-list">
      <?php foreach ($panel_accounts as $account): ?>
        <li>
          <span>
            <span class="mono"><?= h($account['username']) ?></span>
            <?php if (($account['full_name'] ?? '') !== ''): ?><span class="small muted"><?= h($account['full_name']) ?></span><?php endif; ?>
            <?php if (($account['email'] ?? '') !== ''): ?><span class="small muted"><?= h($account['email']) ?></span><?php endif; ?>
          </span>
          <span class="row">
            <?php if (($account['role'] ?? '') === 'admin'): ?><span class="small">Panel admin</span><?php else: ?><span class="small muted">Server account only</span><?php endif; ?>
            <?php if (($account['role'] ?? '') !== 'admin'): ?>
              <form method="post" action="/accounts/admin-grant" data-busy>
                <?= csrf_field() ?>
                <input type="hidden" name="username" value="<?= h($account['username']) ?>">
                <button class="btn btn-small" type="submit" data-busy-text="Granting…">Give admin access</button>
              </form>
            <?php else: ?>
              <form method="post" action="/accounts/admin-revoke" data-busy>
                <?= csrf_field() ?>
                <input type="hidden" name="username" value="<?= h($account['username']) ?>">
                <button class="btn btn-small" type="submit" data-busy-text="Removing…">Remove admin access</button>
              </form>
            <?php endif; ?>
            <form method="post" action="/accounts/delete-panel-account" data-busy>
              <?= csrf_field() ?>
              <input type="hidden" name="username" value="<?= h($account['username']) ?>">
              <button class="btn btn-small" type="submit" data-busy-text="Removing…" onclick="return confirm('Remove this non-student server account and its home directory?')">Remove account</button>
            </form>
          </span>
        </li>
      <?php endforeach; ?>
    </ul>
  <?php else: ?>
    <p class="nothing">No non-student accounts have been created through the panel.</p>
  <?php endif; ?>
</section>

<section class="section" id="create-account" aria-labelledby="create-account-title">
  <h2 id="create-account-title">Create a non-student account</h2>
  <p class="muted">Create a normal Linux account for staff, VAPT testers, or other trusted helpers. Check admin access when the account should be able to use Students and Server.</p>
  <form method="post" action="/accounts/create-panel-account" class="stack" data-busy>
    <?= csrf_field() ?>
    <label class="field">
      <span class="label">Username</span>
      <input type="text" name="username" pattern="[a-z_][a-z0-9_-]{2,31}" maxlength="32" autocomplete="off" required>
    </label>
    <label class="field">
      <span class="label">Full name</span>
      <input type="text" name="full_name" maxlength="100">
    </label>
    <label class="field">
      <span class="label">Email <span class="muted">(optional)</span></span>
      <input type="email" name="email" maxlength="254">
      <span class="hint">May be the same email address used by a student account. If admin access is enabled, the new credentials are emailed here.</span>
    </label>
    <label class="check">
      <input type="checkbox" name="grant_admin" value="1" checked>
      <span>Give this account admin-panel access to Students and Server</span>
    </label>
    <button class="btn" type="submit" data-busy-text="Creating…">Create account</button>
  </form>
</section>

<section class="section" id="panel-admins" aria-labelledby="panel-admins-title">
  <h2 id="panel-admins-title">Panel administrators</h2>
  <p class="muted">The <span class="mono">fullstack</span> account is always the superadmin. Everyone listed here can use Students and Server only.</p>
  <?php if ($admin_users): ?>
    <ul class="blocked-list">
      <?php foreach ($admin_users as $user): ?>
        <li>
          <span class="mono"><?= h($user) ?></span>
          <form method="post" action="/accounts/admin-revoke" data-busy>
            <?= csrf_field() ?>
            <input type="hidden" name="username" value="<?= h($user) ?>">
            <button class="btn btn-small" type="submit" data-busy-text="Removing…">Remove admin access</button>
          </form>
        </li>
      <?php endforeach; ?>
    </ul>
  <?php else: ?>
    <p class="nothing">No panel admins have been added yet.</p>
  <?php endif; ?>
</section>
