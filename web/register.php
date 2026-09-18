<?php
declare(strict_types=1);
session_start();
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>5CS045 — Server Account Registration</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 640px; margin: 3rem auto; padding: 0 1rem; color: #1a1a1a; }
  label { display: block; margin-top: 1.2rem; font-weight: 600; }
  input { width: 100%; padding: 0.5rem; margin-top: 0.3rem; box-sizing: border-box; font-family: inherit; }
  small { color: #555; }
  button { margin-top: 1.5rem; padding: 0.6rem 1.4rem; font-size: 1rem; cursor: pointer; }
  .msg { padding: 0.8rem; margin-top: 1rem; border-radius: 4px; }
  .msg.ok { background: #e6f4ea; border: 1px solid #34a853; }
  .msg.err { background: #fce8e6; border: 1px solid #ea4335; }
</style>
</head>
<body>
<h1>5CS045 Full Stack Development — Server Account</h1>
<p>Enter your college email. We'll create (or reset) your server account and
   email your username, database name, and password to that address.</p>

<?php if (!empty($_SESSION['register_result'])): ?>
  <div class="msg <?= $_SESSION['register_result']['ok'] ? 'ok' : 'err' ?>">
    <?php
      // htmlspecialchars — this page reflects back state from the student's
      // own submission, so it's a straightforward reflected-XSS spot otherwise.
      echo nl2br(htmlspecialchars($_SESSION['register_result']['message'], ENT_QUOTES));
    ?>
  </div>
  <?php unset($_SESSION['register_result']); ?>
<?php endif; ?>

<form method="post" action="register_handler.php">
  <label for="email">College email</label>
  <input type="email" id="email" name="email" required maxlength="254"
         placeholder="s1234567@heraldcollege.edu.np">
  <small>Already registered? Submitting again resets your password and
    re-sends it — handy if you've lost the original email.</small>

  <button type="submit">Create / reset my account</button>
</form>
</body>
</html>
