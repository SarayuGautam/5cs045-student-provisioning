# Demo student portfolio (Blade)

A small PHP + MySQL project for testing your student server account. Features: CRUD for projects, PDO prepared statements, output escaping (Blade `{{ }}`), server-side validation, CSRF tokens, Fetch API search, session login, BladeOne templates.

## Deploy (run on the server over SSH)

```bash
cd ~/assessments
cp -r /path/to/demo-student-portfolio-blade portfolio   # or scp it up
cd portfolio
composer install --no-dev
cp config.example.php config.php
nano config.php                     # your username, password, student_<username>
mysql -u <username> -p student_<username> < schema.sql
chmod 700 cache
```

Open `https://<server>/~<username>/assessments/portfolio/register.php`, create a user, and log in.

`config.php`, `vendor/` and `cache/` are git-ignored. Never commit `config.php`.
