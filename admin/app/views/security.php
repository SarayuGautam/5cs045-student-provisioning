<?php /** @var array $bans @var array $allow @var array $settings @var array $signins @var array $admin_users */
$jails = [
    'sshd' => 'Blocked for an hour after 5 wrong SSH passwords in 10 minutes.',
    'recidive' => 'Blocked for a week after being blocked 3 times in one day.',
];
$blocked = [];
foreach ($bans as $jail) foreach ($jail['banned'] as $addr) $blocked[] = [$jail['jail'], $addr];
$stopped = array_filter($bans, fn($j) => !$j['running']);
?>
<header class="page-head">
  <h1>Security</h1>
  <p class="lead">Blocked computers, who can open this panel, and email.</p>
</header>

<section class="section" aria-labelledby="bans-title">
  <h2 id="bans-title">Blocked computers</h2>
  <p class="muted">A whole lab often shares one address, so one student's typos can lock everyone out. Unblocking is safe: the address is blocked again if the guessing carries on.</p>
  <?php if ($blocked): ?>
    <ul class="blocked-list">
      <?php foreach ($blocked as [$jail, $addr]): ?>
        <li>
          <span class="mono"><?= h($addr) ?></span>
          <span class="small muted"><?= h($jails[$jail] ?? $jail) ?></span>
          <form method="post" action="/security/unban" data-busy>
            <?= csrf_field() ?>
            <input type="hidden" name="jail" value="<?= h($jail) ?>">
            <input type="hidden" name="address" value="<?= h($addr) ?>">
            <button class="btn btn-small" type="submit" data-busy-text="Unblocking…"><?= icon('unlock') ?><span>Unblock</span></button>
          </form>
        </li>
      <?php endforeach; ?>
    </ul>
  <?php else: ?>
    <p class="nothing"><?= icon('check') ?>No computers are blocked.</p>
  <?php endif; ?>
  <?php if ($stopped): ?><p class="small warn-danger">fail2ban is not running, so nothing is being blocked. See the Server page.</p><?php endif; ?>
</section>

<section class="section" id="allow" aria-labelledby="allow-title">
  <h2 id="allow-title">Who can open this panel</h2>
  <p class="muted">One address or range per line, like <span class="mono">10.21.4.57</span> or <span class="mono">10.21.4.0/24</span>. Every other computer gets "403 Forbidden". The server itself is always allowed.</p>
  <form method="post" action="/security/allowlist" class="stack" data-busy>
    <?= csrf_field() ?>
    <label class="field">
      <span class="label">Allowed addresses</span>
      <textarea name="entries" rows="4" spellcheck="false" class="mono"><?= h(implode("\n", $allow['entries'])) ?></textarea>
      <span class="hint">You are on <span class="mono"><?= h($allow['you']) ?></span>, which has to stay on the list.</span>
    </label>
    <div class="row"><button class="btn" type="submit" data-busy-text="Saving…">Save the list</button></div>
  </form>
  <p class="small muted">Locked out, or your laptop got a new address? SSH in and run <span class="mono">sudo /usr/local/sbin/5cs045/bin/admin-allow.sh add</span></p>
</section>

<?php if ($secret && ($secret['kind'] ?? '') === 'panel-account'): ?>
<section class="secret" aria-labelledby="new-account-title">
  <h2 id="new-account-title">New non-student account</h2>
  <p class="muted">The password below is shown once. Store it securely or pass it to the account owner.</p>
  <p><strong>Username:</strong> <span class="mono"><?= h($secret['username']) ?></span></p>
  <p class="secret-pw"><span class="mono" id="new-account-password"><?= h($secret['password']) ?></span>
    <button type="button" class="btn btn-small" data-copy="#new-account-password"><?= icon('copy') ?><span>Copy password</span></button>
  </p>
  <p class="small">
    Panel admin: <?= !empty($secret['admin']) ? 'yes - Students and Server access' : 'no' ?>.
    <?php if (($secret['email'] ?? '') !== ''): ?>Email: <?= h($secret['email']) ?>.<?php endif; ?>
    This box goes away when you leave the page.
  </p>
</section>
<?php endif; ?>

<section class="section" id="panel-accounts" aria-labelledby="panel-accounts-title">
  <h2 id="panel-accounts-title">Non-student server accounts</h2>
  <p class="muted">These are normal Linux accounts, separate from student accounts. They do not get sudo, student websites, or student databases.</p>
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
            <?php if (($account['role'] ?? '') === 'admin'): ?><span class="small">Panel admin</span><?php endif; ?>
            <form method="post" action="/security/delete-panel-account" data-busy>
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

  <form method="post" action="/security/create-panel-account" class="stack" data-busy>
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
      <span class="hint">This may be the same email address already used by a student account.</span>
    </label>
    <label class="check">
      <input type="checkbox" name="grant_admin" value="1" checked>
      <span>Give this account admin-panel access to Students and Server</span>
    </label>
    <button class="btn" type="submit" data-busy-text="Creating…">Create non-student account</button>
  </form>
</section>

<section class="section" id="panel-admins" aria-labelledby="panel-admins-title">
  <h2 id="panel-admins-title">Panel administrators</h2>
  <p class="muted">The <span class="mono">fullstack</span> account is the only superadmin. People listed here can use the Students and Server tabs only.</p>
  <?php if ($admin_users): ?>
    <ul class="blocked-list">
      <?php foreach ($admin_users as $user): ?>
        <li>
          <span class="mono"><?= h($user) ?></span>
          <form method="post" action="/security/admin-revoke" data-busy>
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
  <form method="post" action="/security/admin-grant" class="inline-form" data-busy>
    <?= csrf_field() ?>
    <label class="field">
      <span class="label">Server username</span>
      <input type="text" name="username" pattern="[a-z_][a-z0-9_-]{2,31}" maxlength="32" autocomplete="off" required>
      <span class="hint">This must be an existing non-student server account with a password.</span>
    </label>
    <button class="btn" type="submit" data-busy-text="Granting…">Give admin access</button>
  </form>
</section>

<section class="section" id="email" aria-labelledby="email-title">
  <h2 id="email-title">Email</h2>
  <p class="muted">Students get their login by email.
    <?php if (!$settings['smtp_ready']): ?><strong class="warn-danger">The email settings still look like the example.</strong> Edit <span class="mono">/etc/5cs045/smtp_config.php</span>.<?php endif; ?>
    <?= $settings['admin_email'] !== '' ? 'Server alerts go to ' . h($settings['admin_email']) . '.' : 'No admin_email is set, so server alerts are not emailed to anyone.' ?></p>
  <form method="post" action="/security/test-email" class="inline-form" data-busy>
    <?= csrf_field() ?>
    <label class="field">
      <span class="label">Send a test email to</span>
      <input type="email" name="email" value="<?= h($settings['admin_email']) ?>" placeholder="you@<?= h($settings['email_domain'] ?: 'example.edu') ?>" required>
    </label>
    <button class="btn" type="submit" data-busy-text="Sending…"><?= icon('mail') ?><span>Send test</span></button>
  </form>
</section>

<section class="section" aria-labelledby="signins-title">
  <h2 id="signins-title">Recent sign-ins to this panel</h2>
  <?php if (!$signins): ?>
    <p class="nothing">None yet.</p>
  <?php else: ?>
    <?php $rows = $signins; require __DIR__ . '/_loglines.php'; ?>
    <p class="small"><a href="/logs?log=admin">Everything done on this panel</a></p>
  <?php endif; ?>
</section>
