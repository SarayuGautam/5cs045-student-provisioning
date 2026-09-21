# Demo student portfolio

A small PHP and MySQL website for trying out a student account. You can add, edit, delete and search projects. It has a login, and it uses prepared statements, escaped output, form checks, CSRF tokens and Blade templates.

## Put it on the server

From your laptop, in the folder that contains this project:

```bash
scp -r demo-student-portfolio-blade <username>@<server>:~/assessments/portfolio
ssh <username>@<server>
cd ~/assessments/portfolio
composer install --no-dev
cp config.example.php config.php
nano config.php
mysql -u <username> -p <username> < schema.sql
```

In `config.php` set your username, your server password and your username again as the database name.

Then open `https://<server>/~<username>/assessments/portfolio/register.php`, create a user and log in.

Never commit `config.php`. It holds your password.
