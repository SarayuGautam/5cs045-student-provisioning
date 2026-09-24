<?php /** @var ?string $error @var string $username @var array $flashes */ ?>
<main class="login">
  <div class="login-box">
    <p class="wordmark">5CS045 <span>admin</span></p>
    <h1>Sign in</h1>
    <p class="muted">Use the server's sudo account, the same one you use for SSH.</p>
    <?php require __DIR__ . '/_flashes.php'; ?>
    <?php if ($error): ?>
      <div class="flash flash-error" role="alert"><?= icon('alert') ?><p><?= h($error) ?></p></div>
    <?php endif; ?>
    <form method="post" action="/login" class="stack" data-busy>
      <?= csrf_field() ?>
      <label class="field">
        <span class="label">Username</span>
        <input name="username" value="<?= h($username) ?>" autocomplete="username" autocapitalize="off" spellcheck="false" required>
      </label>
      <label class="field">
        <span class="label">Password</span>
        <input type="password" name="password" autocomplete="current-password" required <?= $username !== '' ? 'autofocus' : '' ?>>
      </label>
      <button class="btn btn-primary btn-wide" type="submit" data-busy-text="Checking…">Sign in</button>
    </form>
    <p class="small muted">Only computers on the allowed list can open this page. Yours is <span class="mono"><?= h(client_ip()) ?></span>.</p>
  </div>
</main>
