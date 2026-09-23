# 5CS045 Student Server

A small server for the Full Stack Development module. Each student gets their own login, website folders and database. Students register themselves on a web page, or you can create accounts by hand.

Every command below is run on the server, over SSH, unless it says otherwise.

## What a student gets

- A login (username and password). The same password works for SSH, SCP and MySQL.
- Three website folders: `workshops`, `exam` and `assessment`.
- One database, with the same name as the username.
- 500 MB of disk space and a 100 MB database (see "Resource limits").
- Three websites:
  - `https://<server>/~<username>/workshops/` for weekly work. The student makes one folder per week, for example `workshops/week1`.
  - `https://<server>/~<username>/assessment/` for the assessment project (one project).
  - `https://<server>/~<username>/exam/` for the exam.

Opening `https://<server>/~<username>/` shows a welcome page with the student's name. Each new folder starts with a one-line note about what it is for. The note goes away as soon as the student uploads their own `index.html` or `index.php`.

Students cannot see or change each other's files. Their PHP code runs as their own user.

The username comes from the email. `sarayu.gautam@heraldcollege.edu.np` becomes `sarayu_gautam`.

## How registration works

1. The student opens `https://<server>/` and types their college email.
2. The server creates the account and emails them the username, password, database name and the three website addresses.
3. Each email can register only once. A second try is refused.
4. The new student's website starts working about 10 seconds after registration.

Students cannot reset their own password. You do that (see "Everyday tasks").

## Setting up a new server

You need a fresh Ubuntu 24.04 machine. Take a snapshot first if you can.

```bash
sudo -i
cd /opt
git clone https://github.com/SarayuGautam/5cs045-student-provisioning.git 5cs045-provisioning
cd 5cs045-provisioning
./setup/00-server-setup.sh
mysql_secure_installation
```

The setup script installs everything. phpMyAdmin has no separate login of its own — students sign in with their own MySQL username and password.

For `mysql_secure_installation`, answer: switch to unix_socket **Y**, change root password **N**, and **Y** to everything else.

Only run the setup script once. To install newer files later, use "Updating the server".

## Email settings (SMTP)

The server sends email through your college's mail server. The settings live in `/etc/5cs045/smtp_config.php`. This file is only on the server and is never in Git.

```bash
sudo nano /etc/5cs045/smtp_config.php
```

Fill in:

| Setting | Meaning |
|---|---|
| host, port | The mail server address and port (usually port 587) |
| username, password | The login of the sending mailbox |
| from_address, from_name | What students see as the sender |
| use_starttls | Keep `true` for port 587 |
| allowed_email_domain | Only emails ending in this can register |
| server_url | The address students use, for example `https://10.80.0.250` |
| admin_email | Where server alerts go (disk 80% full). Leave empty for no alerts |

Send yourself a test email:

```bash
sudo php /opt/5cs045-provisioning/test/smtp-test.php your.name@heraldcollege.edu.np
```

If it fails, the error message says what went wrong (wrong password, server unreachable, and so on).

On a server set up before `admin_email` existed, add the line yourself: `'admin_email' => 'you@heraldcollege.edu.np',`

`web/smtp_config.example.php` in this repository is only a template. Never put the real password in it.

## Everyday tasks

The admin scripts are in `/usr/local/sbin/5cs045/bin/`. To save typing:

```bash
cd /usr/local/sbin/5cs045/bin
```

### Create a student by hand

```bash
sudo ./add-student.sh -u sarayu_gautam -n "Sarayu Gautam" -e sarayu.gautam@heraldcollege.edu.np
```

- `-u` is the username: 3 to 32 characters, lowercase letters, numbers and underscores, starting with a letter.
- `-n` is the full name (optional).
- `-e` is the email (optional but recommended). It stops the registration page creating a second account for the same person.

The script prints the password once. To email the details to the student:

```bash
sudo php resend-credentials.php sarayu.gautam@heraldcollege.edu.np
```

### A student lost or deleted their email

Send it again. This emails the same password again:

```bash
sudo php resend-credentials.php student@heraldcollege.edu.np
```

If the student changed their password themselves, first give them a new one (next section), then send the email.

### A student forgot their password

```bash
sudo ./reset-student-password.sh -u sarayu_gautam
sudo php resend-credentials.php sarayu.gautam@heraldcollege.edu.np
```

The first command makes a new password and prints it. It changes the SSH and database password together. The second emails it. If email is not working, give the student the password another way.

### A student wants to start again

Removing a student deletes the account, database and website. This is permanent - there is no backup:

```bash
sudo ./remove-student.sh -u sarayu_gautam
```

After removal the student can register again with the same email.

### Remove everyone (end of semester)

```bash
sudo ./remove-all-students.sh
```

It asks you to type `DELETE` and the number of students before it does anything. `--prefix loadtest_` only removes usernames that start with `loadtest_`, which is handy for clearing out test accounts.

### See all students

```bash
sudo ./list-students.sh
```

### See who registered and what went wrong

```bash
sudo tail -50 /var/log/5cs045-registration.log
sudo tail -50 /var/log/5cs045-provisioning.log
```

## Putting a website on the server (as a student)

These steps run on the student's own laptop, not on the server. The example uses the demo portfolio in this repository (`demo-student-portfolio-blade`) and the student `sarayu_gautam`.

### 1. Upload the folder

Open a terminal on your laptop, go to the folder that contains the project, then:

```bash
scp -r demo-student-portfolio-blade/. sarayu_gautam@<server>:~/assessment/
```

The `/.` after the folder name matters. It copies the files inside the project straight into `assessment`, so the site opens at `https://<server>/~sarayu_gautam/assessment/` and not in a sub-folder.

Type the password from the email when asked. Answer `yes` if it asks about the server's fingerprint. Anything you upload to `workshops`, `exam` or `assessment` is on the web straight away. There is no need to run `chmod`.

### 2. Log in and finish the setup

```bash
ssh sarayu_gautam@<server>
cd ~/assessment
composer install --no-dev
cp config.example.php config.php
nano config.php
```

In `config.php` put your username, your password and your username again as the database name. Then create the tables. It asks for your password:

```bash
mysql -u sarayu_gautam -p sarayu_gautam < schema.sql
```

### 3. Open it

`https://<server>/~sarayu_gautam/assessment/`

The first time, click "Create one" to make a demo user, then log in.

The browser warns about the certificate because it is self-signed. Choose to continue anyway.

To change the site later, edit the files on your laptop and run the `scp` command again.

## Updating the server

When the repository has new files, on the server:

```bash
cd /opt/5cs045-provisioning
git pull
sudo ./setup/update-server.sh
```

This copies the new scripts and pages into place. It does not touch email settings or students.

## Checking the server is healthy

```bash
sudo ./test/smoke-test.sh
```

It creates two temporary students, checks that they cannot read each other's files, and removes them. Run it after setup and after updates. Every line should say PASS.

To check the services:

```bash
systemctl status nginx php8.3-fpm mariadb ssh fail2ban --no-pager
sudo nginx -t
```

## Load testing (SSH and SCP)

Checks how many students can log in and upload at the same time. Run it before a semester or in a quiet window, never while students are working: at full size it deliberately pushes the server as hard as a whole cohort would.

**1. Create throwaway accounts on the server.** They are real accounts (user, folders, database, PHP pool, limits), named `loadtest_001` upwards. About a second each, so 800 take around 15 minutes. The passwords go into `loadtest-accounts.csv` in your home folder.

```bash
cd /opt/5cs045-provisioning
sudo ./test/loadtest/create-accounts.sh 800
```

**2. Pick a test machine.** Any other computer on the campus network with Python 3 (Linux, macOS or Windows). Not the server itself, because the test would compete with the server for CPU. Copy the passwords file to it, for example `scp <you>@<server>:loadtest-accounts.csv .`

**3. Stop fail2ban banning the test machine.** Hundreds of logins from one address look like an attack. This lasts until fail2ban restarts.

```bash
sudo fail2ban-client set sshd addignoreip <test machine IP>
sudo fail2ban-client set recidive addignoreip <test machine IP>
```

**4. Watch the server.** In a second SSH window on the server run `sudo ./test/loadtest/monitor.sh`. Press Ctrl-C after each test run to see the worst moments (CPU, memory, swap, refused connections).

**5. Run the test on the test machine**, from a copy of this repository:

```bash
python3 -m pip install asyncssh
python3 test/loadtest/ssh_load.py <server IP> loadtest-accounts.csv --scenario login --users 100
```

Go up in steps (`--users 100`, `200`, `400`, `800`) so you can see where it starts to struggle. The scenarios:

| Scenario | What each student does |
|---|---|
| `login` | Logs in and keeps a terminal open for `--hold` seconds (default 60), running a command every 10 seconds |
| `upload` | Uploads a `--file-size` MB file (default 5) and, with `--project demo-student-portfolio-blade`, the demo site. Modern `scp` uses the same protocol |
| `lab` | Both: logs in, keeps the terminal open, uploads, and checks the uploaded PHP |

`--ramp 60` spreads the logins over a minute, like a real class arriving. Without it, everyone connects in the same second, which is the worst case.

A healthy result: every student succeeds, the median login is a few seconds, free memory never gets close to zero, no swap is used, and the monitor reports no MaxStartups throttling. "Most login sessions" should also match "Most SSH connections": fewer sessions means some logins got in without their CPU and memory limits (check with `journalctl --since "10 min ago" | grep -c "Failed to create session"`). The script lists the reason for every failure, and saves a line per student to a CSV.

**6. Clean up.**

```bash
sudo /usr/local/sbin/5cs045/bin/remove-all-students.sh --prefix loadtest_ --yes
sudo fail2ban-client set sshd delignoreip <test machine IP>
sudo fail2ban-client set recidive delignoreip <test machine IP>
rm ~/loadtest-accounts.csv
```

## Resource limits

Every student gets these limits automatically, so one account cannot fill the disk or slow the server down for everyone else:

| Limit | Value | What happens when it is reached |
|---|---|---|
| Disk (website files, uploads, anything in their home) | 500 MB | Writes fail with "Disk quota exceeded" |
| Database | 100 MB | Checked every 15 minutes. Over the limit, the database becomes read and delete only ("INSERT command denied"). Full access comes back by itself once it is under 100 MB again |
| Programs run over SSH | 1 CPU core, 1 GB memory, 200 processes | The program is slowed down, or stopped if it runs out of memory |
| PHP for their websites | 4 workers, 128 MB and 30 seconds per request | The request fails |
| PHP error log (`.sessions/php-error.log`) | 5 MB | Cut down to its last 1 MB, so a noisy bug cannot eat the disk quota |

Students cannot use `cron` or `at`: those jobs would run outside the limits. Only root can schedule jobs, so use `sudo crontab -e` for your own.

The SSH limits depend on each login getting a systemd session. When a whole class logs in within the same few seconds, the system bus has to handle hundreds of session requests at once, so the setup scripts raise its connection limits (`/etc/dbus-1/system.d/5cs045-limits.conf`). As a safety net, students are also in the `5cs045-students` group, which caps them at 300 processes at every SSH login (`/etc/security/limits.d/5cs045-students.conf`) even if a session could not be created.

`add-student.sh` applies the limits to new students, and `update-server.sh` applies them to everyone already registered. To apply them again by hand: `sudo ./apply-student-limits.sh` (all students) or `sudo ./apply-student-limits.sh sarayu_gautam`. The values are at the top of `bin/apply-student-limits.sh` (disk, CPU, memory, processes) and `bin/enforce-limits.sh` (database, error log, disk alert).

`enforce-limits.sh` runs every 15 minutes (`/etc/cron.d/5cs045`) and writes what it did to `/var/log/5cs045-provisioning.log`. It also emails `admin_email` (see "Email settings") when the disk is 80% full, at most once a day.

To see or change one student's disk use and limit:

```bash
sudo quota -vu sarayu_gautam
sudo setquota -u sarayu_gautam 1024000 1024000 0 0 /   # in 1K blocks; 1024000 = 1 GB
```

A change made by hand like this lasts until the next `update-server.sh` or `apply-student-limits.sh`, which put back the standard 500 MB.

### Turning on disk quotas (once per server)

The disk quota needs quota accounting on the filesystem that holds `/srv/students`. `00-server-setup.sh` does not do this, because disk layouts differ between servers. Until it is on, accounts are still created, and a warning is logged that they have no disk cap.

```bash
sudo apt-get install -y quota
# In /etc/fstab, add usrquota,grpquota to the options of the / line, then:
sudo mount -o remount /
sudo quotacheck -cum /
sudo quotaon /
sudo /usr/local/sbin/5cs045/bin/apply-student-limits.sh
```

### Growing the disk

If `/srv/students` is on LVM and running low on room, grow it live - no downtime, no reboot:

```bash
sudo vgs                              # confirm there is free space in the volume group (VFree)
sudo lvextend -L +100G /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
df -h /
```

Adjust the volume group and logical volume names, and the amount to grow by, to match `sudo vgs` / `sudo lvs` on your server.

## Common problems

**A student gets "Disk quota exceeded".** They have used their 500 MB. `sudo quota -vu <username>` shows their use. They need to delete files (big images and videos are the usual cause), or you can raise their limit (see "Resource limits").

**A student's site says "INSERT command denied".** Their database is over 100 MB, so it is read and delete only. Dropping tables they do not need frees the space straight away. Deleting rows does not always shrink the files, so after a large delete run `sudo mysqlcheck --optimize <username>`. Full access comes back within 15 minutes of being under the limit.

**The registration page says "could not send the email".** The account was created but the email failed. Fix the email settings (run the SMTP test), then run `resend-credentials.php` for that student.

**A student says "this email has already been registered".** They registered before. Run `resend-credentials.php` with their email. If the account was removed by mistake, run `add-student.sh` again.

**A student's folder shows 403 Forbidden.** The folder is empty, so the web server has nothing to show. Run `sudo /usr/local/sbin/5cs045/bin/refresh-student-folders.sh <username>`. It adds the short note page and repairs the folder permissions. Without a username it checks every student.

**The student's website shows 404.** The file is not in the right folder. It must be inside `workshops`, `exam` or `assessment`. Check with `ls /srv/students/<username>/assessment`.

**The student's website shows 502 or a blank page.** Look at their PHP error log: `sudo tail /srv/students/<username>/.sessions/php-error.log`. If it is a 502, run `sudo systemctl status php8.3-fpm` and check the file `/etc/php/8.3/fpm/pool.d/<username>.conf` exists.

**A student cannot log in over SSH.** Reset their password. Repeated wrong passwords get an address blocked for an hour by fail2ban. To unblock: `sudo fail2ban-client set sshd unbanip <address>`. An address banned three separate times in a day is banned again for a week by the `recidive` jail - unblock that one with `sudo fail2ban-client set recidive unbanip <address>`.

**`composer install` fails on the server.** The server needs internet access to packagist.org. If it is blocked, run `composer install --no-dev` on your laptop instead and upload the whole folder, including `vendor`.

**Nginx will not reload.** Run `sudo nginx -t`. It shows the file and line with the mistake.

**Registration says "Please wait a few minutes".** The same email tried twice within five minutes. Wait, or delete the file for that email in `/var/lib/5cs045-ratelimit/`.

**Registration says "Too many registration attempts from this network".** More than 40 registration attempts came from the same public IP within 15 minutes - normal if a whole class is behind the same campus NAT and unlucky timing pushed them over, or a sign someone is probing the form. Wait 15 minutes, or clear it early for a specific IP by deleting its file (name is the SHA-256 of the IP address) from `/var/lib/5cs045-ip-ratelimit/`.

## Safety rules

- The real SMTP password stays only in `/etc/5cs045/smtp_config.php` (owner `root`, group `www-data`, mode `640`). Never commit it or paste it into chat or email.
- To see a student's saved password: `sudo cat /var/lib/5cs045-credentials/sarayu_gautam`. Only root can read these files.
- Never commit student passwords or the files in `/var/lib/5cs045-credentials`.
- phpMyAdmin has no separate password of its own: students log in there with the same username and password they use for SSH and MySQL.
- The certificate is self-signed. Replace it when the college gives you a proper server name.
- To remove everything (students, settings, web files): `sudo ./setup/uninstall.sh`.

## What is in this repository

```text
bin/add-student.sh              Create a student
bin/remove-student.sh           Remove a student
bin/reset-student-password.sh   New password for a student
bin/resend-credentials.php      Email a student their details again
bin/list-students.sh            List students
bin/refresh-student-folders.sh  Fix folder permissions and add the short note pages
bin/apply-student-limits.sh     Disk quota and SSH CPU/memory/process limits
bin/enforce-limits.sh           Every 15 min: database cap, error log trim, disk alert
bin/send-admin-alert.php        Email the admin (used by enforce-limits.sh)
bin/remove-all-students.sh      Remove every student, or every one with a name prefix
setup/00-server-setup.sh        First-time setup
setup/update-server.sh          Install new files on a working server
setup/uninstall.sh              Remove everything
templates/                      nginx, PHP, SSH, fail2ban and cron settings used by the scripts
test/smoke-test.sh              Security and isolation check
test/smtp-test.php              Send one test email
test/loadtest/                  SSH/SCP load test: accounts, load generator, server monitor
web/                            Registration page and email code
demo-student-portfolio-blade/   Example website for students to deploy
docs/Server_Access_Guide.docx   Guide for students
```
