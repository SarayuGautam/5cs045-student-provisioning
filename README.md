# 5CS045 Student Server

A small server for the Full Stack Development module. Each student gets their own login, website folders and database. Students register themselves on a web page, and you look after everything else from the admin panel in your browser.

## What a student gets

- A login (username and password). The same password works for SSH, SCP and MySQL/phpMyAdmin.
- One database, with the same name as the username.
- 500 MB of disk space and a 100 MB database (see "Resource limits").
- Three websites:
  - `https://<server>/~<username>/workshops/` for weekly work, one folder per week (for example `workshops/week1`).
  - `https://<server>/~<username>/assessment/` for the assessment project.
  - `https://<server>/~<username>/exam/` for the exam.

Students cannot see or change each other's files. Their PHP code runs as their own user.

The username comes from the email: `sarayu.gautam@heraldcollege.edu.np` becomes `sarayu_gautam`.

## How students get an account

1. The student opens `https://<server>/` and types their college email.
2. The server creates the account and emails them their username, password and website addresses.
3. Each email can register only once. The website starts working about 10 seconds later.

Students cannot reset their own password. You do that on the admin panel.

## The admin panel

Open **`https://<server>:8443`** (for example `https://10.80.0.250:8443`) and sign in with the server's sudo account, the one you use for SSH (for example `fullstack`). The browser warns about the certificate the first time; choose to continue.

The first page is built for the most common job, a student in a lab who cannot log in:

1. Start typing their name, username or email in the search box (press `/` to jump to it).
2. Press Enter, or click them. Their account opens on the right.
3. Click **Reset password**. The new password appears with every character spelled out ("Q capital", "8 number") so you can read it out without mix-ups. Tick the box to email it too.

If a lab's computer got blocked for too many wrong passwords, it shows at the top of that page with an **Unblock** button.

| Page | What you can do there |
|---|---|
| **Students** | Find a student; reset, email or show their password; change their disk limit; remove them; add a student; unblock a lab computer |
| **Server** | Disk, memory and processor use, whether every service is running, and anything that needs attention |
| **Semester** | **Add a whole class** from a pasted list of emails, **run the health check**, and **remove every student** at the end of term |
| **Security** | Blocked computers, which computers may open the panel, and a test email |
| **Logs** | Registrations, account changes, and everything done on the panel |

Things that take a while (adding a class, the health check, removing everyone) run in the background. Their page updates by itself, and you can leave it and come back from **Recent jobs**.

### Who can open it

Students never see the panel. Three things keep them out:

1. It is on its own port, 8443. The student site on port 443 has no link to it.
2. Only computers on the **allowed list** can open the page at all; every other computer gets "403 Forbidden". The first time you install it, the list holds the computer you ran the update from over SSH. Change the list on the **Security** page.
3. You then need the sudo account's password. After 5 wrong passwords, that account and that computer wait 15 minutes.

You are signed out after 30 minutes without activity. Every change made on the panel is recorded under **Logs → Admin panel**.

**Locked out** (for example your laptop got a new IP address)? SSH in and run:

```bash
sudo /usr/local/sbin/5cs045/bin/admin-allow.sh add
```

With no address it adds the computer you are SSH'd in from. `admin-allow.sh add 10.21.4.0/24` allows a whole range, `admin-allow.sh remove <address>` takes one off, and `admin-allow.sh` alone shows the list.

How it works, for the curious: the panel's PHP runs as its own user, `5cs045-admin`, which has no rights at all except running one program as root: `bin/admin-action` (see `templates/sudoers-5cs045-admin`). That program checks the sudo password itself and refuses every request that does not come with a valid sign-in. So even a bug in the panel's pages cannot change the server without an admin's password.

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

When it finishes, open the admin panel at `https://<server>:8443` from the same computer you ran it from, fill in the email settings (next section), then run the health check on **Semester**.

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

Then send yourself a test email from **Security → Email** on the admin panel. If it fails, the message says what went wrong (wrong password, server unreachable, and so on).

On a server set up before `admin_email` existed, add the line yourself: `'admin_email' => 'you@heraldcollege.edu.np',`

`web/smtp_config.example.php` in this repository is only a template. Never put the real password in it.

## Updating the server

When the repository has new files, on the server:

```bash
cd /opt/5cs045-provisioning
git pull
sudo ./setup/update-server.sh
```

This installs the new scripts, pages and admin panel. It does not touch email settings or students. Afterwards, run the health check.

## Checking the server is healthy

On the admin panel: **Semester → Run the health check**. It creates two temporary students, checks that logins work, that they cannot read each other's files and that every limit is in place, then removes them. It takes about a minute. Every line should say PASS. Run it after setup and after every update.

The **Server** page shows whether each service is running. From SSH the same check is `sudo /usr/local/sbin/5cs045/test/smoke-test.sh`.

## Common problems

**A student forgot their password.** Type their name on the **Students** page, press Enter and click **Reset password**. Read the new password out, or tick "Also email it to them".

**A student lost the email with their login.** Open them on the **Students** page and use **Email their login**. It sends the same password again.

**A student says "this email has already been registered".** They registered before: use **Email their login** on their page. If the account was removed by mistake, add them again with **Add student**.

**A student cannot log in over SSH.** Reset their password. If the whole lab cannot log in, look at the top of the **Students** page for a blocked computer: after 5 wrong passwords fail2ban blocks the computer's address for an hour (a week if it happens 3 times in a day), and a lab often shares one address. Click **Unblock**.

**A student gets "Disk quota exceeded".** They have used their 500 MB. Their account on the **Students** page shows how much they use. They need to delete files (big images and videos are the usual cause), or you can raise their **Disk limit**.

**A student's site says "INSERT command denied".** Their database is over 100 MB (their account shows "Full, so it is read-only"), so it is read and delete only. Dropping tables they do not need frees the space straight away. Deleting rows does not always shrink the files, so after a large delete run `sudo mysqlcheck --optimize <username>`. Full access comes back within 15 minutes of being under the limit.

**The registration page says "could not send the email".** The account was created, but the email failed. Fix the email settings (test with **Security → Email**), then use **Email their login** for that student.

**The panel says "403 Forbidden".** Your computer is not on the allowed list. See "Locked out" under "The admin panel".

**The panel says "The panel is not allowed to run the server tools".** Run `sudo ./setup/update-server.sh` again; it puts the panel's permissions back.

**A student's folder shows 403 Forbidden.** The folder is empty, so the web server has nothing to show. Run `sudo /usr/local/sbin/5cs045/bin/refresh-student-folders.sh <username>`. It adds the short note page and repairs the folder permissions. Without a username it checks every student.

**The student's website shows 404.** The file is not in the right folder. It must be inside `workshops`, `exam` or `assessment`. Check with `ls /srv/students/<username>/assessment`.

**The student's website shows 502 or a blank page.** Look at their PHP error log: `sudo tail /srv/students/<username>/.sessions/php-error.log`. If it is a 502, run `sudo systemctl status php8.3-fpm` and check the file `/etc/php/8.3/fpm/pool.d/<username>.conf` exists.

**`composer install` fails on the server.** The server needs internet access to packagist.org. If it is blocked, run `composer install --no-dev` on your laptop instead and upload the whole folder, including `vendor`.

**Nginx will not reload.** Run `sudo nginx -t`. It shows the file and line with the mistake.

**Registration says "Please wait a few minutes".** The same email tried twice within five minutes. Wait, or delete the file for that email in `/var/lib/5cs045-ratelimit/`.

**Registration says "Too many registration attempts from this network".** More than 40 registration attempts came from the same public IP within 15 minutes - normal if a whole class is behind the same campus NAT and unlucky timing pushed them over, or a sign someone is probing the form. Wait 15 minutes, or clear it early for a specific IP by deleting its file (name is the SHA-256 of the IP address) from `/var/lib/5cs045-ip-ratelimit/`.

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

Students also get no per-user systemd manager (`user@<uid>.service` is masked). Nothing they do needs one, and in load testing, starting 800 of them at once overloaded the server. The one visible difference is that `systemctl --user` does not work for students.

`add-student.sh` applies the limits to new students, and `update-server.sh` applies them to everyone already registered. To apply them again by hand: `sudo ./apply-student-limits.sh` (all students) or `sudo ./apply-student-limits.sh sarayu_gautam`. The values are at the top of `bin/apply-student-limits.sh` (disk, CPU, memory, processes) and `bin/enforce-limits.sh` (database, error log, disk alert).

`enforce-limits.sh` runs every 15 minutes (`/etc/cron.d/5cs045`) and writes what it did to `/var/log/5cs045-provisioning.log`. It also emails `admin_email` (see "Email settings") when the disk is 80% full, at most once a day.

To give one student more (or less) disk space, open their page on the admin panel and change **Disk limit**. The new limit is kept in `/var/lib/5cs045-quota-overrides/`, so updates keep it too.

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

## Capacity (tested) and hardware

Load-tested on this server (8 CPU cores, about 11 GB of memory free when idle) with 800 test accounts:

| Test | Result |
|---|---|
| 800 students logging in over 2 minutes, each keeping a terminal open for a minute | All 800 in. Median login 0.2 s, CPU at most 50%, about 5.5 MB of memory per logged-in student |
| 800 students uploading 5 MB plus the demo site over 2 minutes (SFTP, what `scp` uses) | All 800 succeeded, 4 GB in total, CPU at most 61% |
| 800 students pressing Enter in the same second | Only about 300 got a terminal; the login service (systemd-logind) could not set up sessions fast enough and then stayed stuck |

So a whole cohort arriving over a couple of minutes is fine; hundreds in the same second is not. If the login service does get stuck, `check-logind.sh` (every minute, from `/etc/cron.d/5cs045`) restarts it after two minutes and emails `admin_email`. Restarting it does not log anyone out. If logins still fail after that, reboot.

The tests used light commands (`ls`, `php -l`), so they measure logins and uploads, not heavy student work. `composer install`, PHP and MySQL can each use a few hundred MB, so a busy lab needs more memory than the test did.

### Hardware to request from IT

Not urgent - the server copes today - but worth asking for before a full cohort is on it:

1. **32 GB RAM** (check the current total with `free -h`). The main one: headroom for a lab running `composer install` at the same time. Each student is capped at 1 GB.
2. **Reserved, not shared, CPU and RAM** on the host, so they are there at the busy moments.
3. **12-16 vCPUs, fast per core.** Helps the rush at the start of a lab. The login service uses one core at a time, so speed per core matters more than the count.
4. **SSD/NVMe storage.** Composer and MariaDB do lots of small reads and writes.
5. **At least 1 Gbps** network to the server.

Text that can be sent as it is:

> For the 5CS045 server (10.80.0.250), could we increase it to 32 GB RAM and 12-16 vCPUs, with those resources reserved rather than shared? Please also confirm the disk is on SSD/NVMe storage and the network link is at least 1 Gbps. Load testing showed the current size handles 800 students logging in, but real coursework (composer, PHP, MySQL) needs more memory headroom during busy lab sessions.

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

## Doing it from the command line

Everything on the panel can also be done over SSH, which is handy if the panel is down. The scripts are in `/usr/local/sbin/5cs045/bin/`:

```bash
cd /usr/local/sbin/5cs045/bin
```

| Task | Command |
|---|---|
| Create a student | `sudo ./add-student.sh -u sarayu_gautam -n "Sarayu Gautam" -e sarayu.gautam@heraldcollege.edu.np` |
| Email a student their login | `sudo php resend-credentials.php sarayu.gautam@heraldcollege.edu.np` |
| New password (prints it) | `sudo ./reset-student-password.sh -u sarayu_gautam` |
| See a student's password | `sudo cat /var/lib/5cs045-credentials/sarayu_gautam` |
| Remove a student | `sudo ./remove-student.sh -u sarayu_gautam` |
| Remove everyone | `sudo ./remove-all-students.sh` (asks you to type `DELETE` and the number of students) |
| Remove only test accounts | `sudo ./remove-all-students.sh --prefix loadtest_` |
| List students | `sudo ./list-students.sh` |
| Disk use of one student | `sudo quota -vu sarayu_gautam` |
| Unblock an address | `sudo fail2ban-client set sshd unbanip <address>` (and `recidive` for week-long blocks) |
| Allowed computers for the panel | `sudo ./admin-allow.sh`, `sudo ./admin-allow.sh add [address]`, `sudo ./admin-allow.sh remove <address>` |
| Logs | `sudo tail -50 /var/log/5cs045-registration.log`, `/var/log/5cs045-provisioning.log`, `/var/log/5cs045-admin.log` |

For `add-student.sh`: `-u` is the username (3 to 32 characters: lowercase letters, numbers and underscores, starting with a letter), `-n` the full name and `-e` the email. Both are optional, but the email stops the registration page creating a second account for the same person. After removal a student can register again with the same email.

## Safety rules

- The real SMTP password stays only in `/etc/5cs045/smtp_config.php` (owner `root`, group `www-data`, mode `640`). Never commit it or paste it into chat or email.
- Saved student passwords are in `/var/lib/5cs045-credentials/`, readable only by root. Seeing one on the panel is recorded in the admin log.
- Keep the panel's allowed list short: your own computers, not whole student labs.
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
bin/check-logind.sh             Every minute: restart the login service if it stops answering
bin/admin-action                The admin panel's only way to change the server (runs as root, checks the sudo password)
bin/admin-allow.sh              Choose which computers may open the admin panel
admin/                          The admin panel (installed to /var/www/5cs045-admin, port 8443)
admin/DESIGN.md                 How the panel looks and why: colours, type, spacing, motion
setup/00-server-setup.sh        First-time setup
setup/update-server.sh          Install new files on a working server
setup/install-admin-panel.sh    Install the admin panel (called by the two scripts above)
setup/uninstall.sh              Remove everything
templates/                      nginx, PHP, SSH, fail2ban, sudo and cron settings used by the scripts
test/smoke-test.sh              Security and isolation check (the panel's "health check")
test/admin-panel-e2e.js         Browser test of the admin panel (Playwright), run from a laptop
test/smtp-test.php              Send one test email
test/loadtest/                  SSH/SCP load test: accounts, load generator, server monitor
web/                            Registration page and email code
demo-student-portfolio-blade/   Example website for students to deploy
docs/Server_Access_Guide.docx   Guide for students
```
