# Demo student portfolio

A small PHP and MySQL website for trying out a student account. You can add, edit, delete and search projects. It has a login, and it uses prepared statements, escaped output, form checks, CSRF tokens and Blade templates.

## Put it on the server

From your laptop, in the folder that contains this project:

```bash
scp -P 22 -r demo-student-portfolio-blade/. <username>@<server>:~/assessment/
ssh -p 22 <username>@<server>
cd ~/assessment
composer install --no-dev
cp config.example.php config.php
nano config.php
mysql -u <username> -p <username> < schema.sql
```

In `config.php` set your username, your server password and your username again as the database name.

The `/.` after the folder name copies the files inside the project straight into `assessment`. Your tutor must have opened the Assessment folder first. The site opens at `https://fullstack-student.heraldcollege.edu.np/~<username>/assessment/`. Click "Create one" to make a demo user, then log in.

Never commit `config.php`. It holds your password.

## Folder rules

Use `~/workshops/weekN` for weekly workshop work. Do not upload directly to `~/` or `~/workshops/`. The `exam` and `assessment` folders may be locked until your tutor opens them.
