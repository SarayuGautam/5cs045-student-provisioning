<?php /** @var array $bans @var array $allow @var array $settings @var array $signins */
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
