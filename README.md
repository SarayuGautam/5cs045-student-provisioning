# 5CS045 Student Server

A simple provisioning system for the Full Stack Development Module. It creates isolated Linux accounts, MySQL databases, PHP-FPM pools, and student web folders.

## Student workflow

1. Open `https://<server>/register.php`.
2. Enter a college email. No login is required.
3. The server creates the account once and emails the username, password, database name, and website URL.
4. The student uses the same password for SSH, SCP, and MySQL.
5. Students cannot reset their own server password. Tutor/admin resets it from the server.

A second registration with the same email is rejected.

## What each student gets

```text
/srv/students/<username>/
├── workshops/
├── exams/
├── assessments/
├── .ssh/
├── .sessions/
└── credentials.txt
```

Student PHP runs as that student. Students cannot read or write another student's files. New content in the three work folders automatically gets web read access without manual `chmod`.

## 1. Fresh Ubuntu 24.04 setup

Use a fresh Ubuntu 24.04 VM. Ask IT to keep a snapshot before setup.

```bash
sudo -i
cd /opt
git clone https://github.com/SarayuGautam/5cs045-student-provisioning.git 5cs045-provisioning
cd /opt/5cs045-provisioning
./setup/00-server-setup.sh
```

The setup installs nginx, PHP 8.3-FPM, MariaDB, phpMyAdmin, Composer, SSH, fail2ban, and ACL support.

The setup asks for one shared username and password for the phpMyAdmin admin page. Registration is public.

## 2. Secure MariaDB

```bash
mysql_secure_installation
```

Use these answers:

```text
Switch to unix_socket authentication: Y
Change the root password: N
Remove anonymous users: Y
Disallow root login remotely: Y
Remove test database: Y
Reload privilege tables: Y
```

## 3. SMTP

The SMTP file is outside the web root:

```bash
nano /etc/5cs045/smtp_config.php
```

Set the real values for:

```text
host
port
username
password
from_address
from_name
use_starttls
allowed_email_domain
server_url
```

The repository only contains a template, `web/smtp_config.example.php`, with a placeholder password. Setup copies it to `/etc/5cs045/smtp_config.php` once; after that, edit only the copy on the server. The real password must never be committed. `.gitignore` blocks `smtp_config.php`.

Test one email with:

```bash
php test/smtp-test.php your.email@heraldcollege.edu.np
```

## 4. Update an already configured VM

After the v2 files have been committed and pushed to Git:

```bash
cd /opt/5cs045-provisioning
git pull
sudo ./setup/apply-v2-existing.sh
```

This makes registration public, keeps Basic Auth on phpMyAdmin, installs the admin password reset script, and updates the nginx configuration. It does not overwrite the live SMTP secret.

Run the security test after the update:

```bash
sudo ./test/smoke-test.sh
```

A clean v2 run should finish with `16 passed, 0 failed`.

## 5. Register a student

Open:

```text
https://<server>/register.php
```

The form asks only for the college email. The student receives:

```text
Your Server Credentials

Welcome to the Server!

Full Stack Development Module Server

Here are your access details:
-----------------------------
Username: ...
Password: ...
Database: ...
Website URL: https://<server>/~username/

Please keep this safe.
```

If the email was already registered, the page rejects the request.

## 6. Reset a student password

Only root/admin should run this:

```bash
sudo /usr/local/sbin/5cs045/bin/reset-student-password.sh -u <username>
```

The script changes the Linux password, MySQL password, and `credentials.txt`. It prints the new password once. Send it to the student using the approved communication method.

## 7. Check the server

```bash
systemctl status nginx --no-pager
systemctl status php8.3-fpm --no-pager
systemctl status mariadb --no-pager
systemctl status ssh --no-pager
systemctl status fail2ban --no-pager
nginx -t
sshd -t
/usr/local/sbin/5cs045/bin/list-students.sh
```

## 8. Student website URLs

```text
https://<server>/~<username>/workshops/
https://<server>/~<username>/exams/
https://<server>/~<username>/assessments/
```

The clean student URL `https://<server>/~<username>/` redirects to `assessments/`.

## 9. Demo portfolio

`demo-student-portfolio-blade/` is a small Blade portfolio for testing the student server. It includes:

- PHP + MySQL
- CRUD for projects
- Prepared statements
- Output escaping
- Server-side validation
- CSRF protection
- Ajax search with Fetch API
- Session-based authentication
- Blade templates

BladeOne is installed with Composer.

## 10. Important files

```text
setup/00-server-setup.sh          Fresh VM setup
setup/apply-v2-existing.sh        Update an existing VM
bin/add-student.sh                Admin/manual account creation
bin/reset-student-password.sh    Admin password reset
bin/remove-student.sh             Remove a student
bin/list-students.sh              List students
web/register.php                  Public registration page
web/register_handler.php          Registration backend
web/smtp_config.example.php       SMTP settings template (real file lives in /etc/5cs045/)
test/smoke-test.sh                Security and isolation test
test/smtp-test.php                Single SMTP test
```

## Security rules

- Keep `/etc/5cs045/smtp_config.php` at `root:www-data` mode `640`.
- Keep the phpMyAdmin Basic Auth file at `root:www-data` mode `640`.
- Do not commit real SMTP passwords or student credentials.
- Do not run the full setup script again on an already configured server.
- Replace the self-signed certificate when IT provides the final DNS name.
