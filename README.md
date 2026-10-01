# 5CS045 Student Server

A server for the Full Stack Development module. Every student gets their own login, three website folders and a database. Students sign themselves up on a web page; you look after everything else from the **admin panel** in your browser.

## Quick reference

| I want to... | Do this |
|---|---|
| Open the admin panel | `https://10.80.0.250:8443`, sign in as `fullstack` (the superadmin) |
| Help a student who cannot log in | Admin panel → type their name → Enter → **Reset password** |
| Check the server is working | Admin panel → **Semester** → **Run the health check** (every line should say PASS) |
| Install the latest version | `cd /opt/5cs045-provisioning && git pull && sudo ./setup/update-server.sh` |
| Let my laptop open the panel (it shows "403 Forbidden") | SSH in from that laptop and run `sudo /usr/local/sbin/5cs045/bin/admin-allow.sh add` |
| Check the server from SSH instead | `sudo /usr/local/sbin/5cs045/test/smoke-test.sh` |

## What a student gets

- **A login.** One password for SSH, SCP and phpMyAdmin/MySQL.
- **A database** with the same name as their username.
- **Three websites** on `https://fullstack-student.heraldcollege.edu.np`:
  - `/~<username>/workshops/` for weekly work, one folder per week.
  - `/~<username>/assessment/` for the assessment project.
  - `/~<username>/exam/` for the exam.
- **Limits:** 500 MB of disk space and a 100 MB database (see "Limits").

Students cannot see each other's files. Their username comes from their email: `sarayu.gautam@heraldcollege.edu.np` becomes `sarayu_gautam`.

**How they sign up:** they open `https://fullstack.heraldcollege.edu.np/` and type their college email. It is sent a link; they open it and click **Create my account**, and their login arrives in a second email. Nothing is created until the link is used, so a mistyped or made-up address never gets an account. Each email can sign up once, and the websites work about 10 seconds later. Students cannot reset their own password; you do that on the panel.

**Two names, kept apart.** `fullstack-student.heraldcollege.edu.np` serves students' websites and nothing else. `fullstack.heraldcollege.edu.np` (and the bare IP) serves sign-up, phpMyAdmin and, on port 8443, the admin panel; student pages asked for there are sent to the student name. Students' pages run their own scripts, so they never share an address with anything that holds a login.

## The admin panel

Open `https://<server>:8443` and sign in with `fullstack` (the superadmin), or with a server account that the superadmin has granted the `admin` role. The browser warns about the certificate the first time; choose to continue.

**Helping a student in a lab** (the first page is built for this):

1. Start typing their name, username or email. Press `/` to jump to the search box.
2. Press Enter, or click them. Their account opens on the right.
3. Click **Reset password**. The new password appears with each character spelled out ("Q capital", "8 number") so you can read it aloud. Tick the box to email it too.

If a lab computer is blocked for too many wrong passwords, it shows at the top of the page with an **Unblock** button.

| Page | What it is for |
|---|---|
| **Students** | Find a student. Reset, email or show their password. Change their disk limit or remove them. Add a student. Unblock a lab computer. |
| **Server** | Disk, memory and processor use, which services are running, and anything that needs attention. |
| **Semester** | Add a whole class from a list of emails, run the health check, and remove every student at the end of term. |
| **Security** | Blocked computers, panel allowlist, and test email. |
| **Admin accounts** | Create non-student server accounts, grant/revoke panel admin access, and remove temporary accounts. |
| **Logs** | Sign-ups, account changes, panel activity, and privileged SSH/sudo activity. |

Long jobs (adding a class, the health check, removing everyone) run in the background, so you can leave their page and come back later.

**Logs → Privileged / SSH** shows successful and failed SSH authentication for accounts with sudo or the Unix `admin` group, including the source IP for SSH authentication events. It also shows commands explicitly run through sudo. Student accounts are excluded. Ordinary shell commands are not recorded by sshd/auth.log, so the panel cannot claim to show every command typed in a privileged shell.

### Who can open the panel

Students never see it. Four layers matter:

1. **Its own port.** The panel is on port 8443, the student site does not link to it, and it does not answer on the students' name.
2. **The allowed list.** Only computers on the list can open it; everyone else gets "403 Forbidden". The first install allows the computer you ran it from. Change the list on the **Security** page.
3. **A panel role.** Only the `fullstack` account is automatically allowed and it is the only **superadmin**. Other people need an explicit **admin** role. The superadmin manages these accounts from **Admin accounts**.
4. **A password.** The account's own Linux password is checked by `bin/admin-action`. After 5 wrong passwords, that account and that computer have to wait 15 minutes.

You are signed out after 30 minutes without activity, and every change is recorded under **Logs → Admin panel**.

**Locked out** (for example your laptop got a new IP address)? SSH in from that laptop and run:

```bash
sudo /usr/local/sbin/5cs045/bin/admin-allow.sh add
```

That adds the computer you are connected from. You can also:

- Add a whole range: `admin-allow.sh add 10.21.4.0/24`
- Take an address off: `admin-allow.sh remove <address>`
- Show the list: `admin-allow.sh`

**Roles**

| Role | Access |
|---|---|
| `fullstack` / superadmin | Students, Server, Semester, Security, Admin accounts, and Logs |
| `admin` | Students and Server only |
| student | No admin panel access |

An admin who opens Semester, Security, or Logs sees a clear message that super admin access is required. The permission check is enforced by the server-side PHP entry point and again by `bin/admin-action`; hiding a tab in the browser is not the security boundary.

**Creating a non-student server account**

Only the `fullstack` superadmin can create or remove non-student server accounts from **Admin accounts**. A created account is a normal Linux account with a home directory and Bash, but it is not a student: it gets no student website folders, student database, student quota, or sudo.

The form can also grant the **admin** panel role at creation time. When an email address is provided for a new admin, the panel sends the generated username, password, role, and admin-panel URL to that email. The generated password is also shown once in the panel.

The old `5cs045-panel` Unix group is no longer used for panel authorization. Existing VAPT accounts from an older installation can remain as ordinary Linux accounts until the VAPT work is finished; remove their panel role and/or delete the account when you are ready.

**Email vs username**

A Linux username is globally unique on the server, so a student and a non-student account **cannot share the same username**.

The email address is separate metadata. A non-student account **may use the same email address as a student account**. Student registration itself still allows only one student registration per email address.

**How it stays safe:** the panel runs as its own user (`5cs045-admin`), which can do nothing except run one program, `bin/admin-action`. That program is the only root-capable path from the panel and it keeps the role allowlist and managed non-student account metadata root-owned.

## Admin-account lifecycle and deployment

The admin panel's persistent authorization state lives outside the web tree:

- `/var/lib/5cs045-admin-auth/admin-users` - newline-separated usernames with the **admin** panel role.
- `/var/lib/5cs045-admin-auth/accounts/<username>.json` - metadata for non-student accounts created through the panel.
- `/var/lib/5cs045-admin-auth/sessions/` - short-lived signed session records.

These files are root-owned and mode 0600/0700. The PHP panel user cannot edit them directly; all privileged changes go through `bin/admin-action`.

After changing code, always deploy both the PHP panel and the root-owned server script:

```bash
cd /opt/5cs045-provisioning
git pull
sudo ./setup/update-server.sh
```

A plain `git pull` does **not** update the live copy under `/var/www/5cs045-admin` or `/usr/local/sbin/5cs045/bin`.

When moving an older server to the role system, the `5cs045-panel` group is legacy. It is no longer enough to grant panel access. Use **Admin accounts → Panel administrators** to grant the admin role explicitly.

## First-time setup

On a fresh Ubuntu 24.04 machine (take a snapshot first if you can):

```bash
sudo -i
cd /opt
git clone https://github.com/SarayuGautam/5cs045-student-provisioning.git 5cs045-provisioning
cd 5cs045-provisioning
./setup/00-server-setup.sh
mysql_secure_installation
```

For `mysql_secure_installation`, answer **Y** to "switch to unix_socket", **N** to "change root password", and **Y** to everything else. Run the setup script only once. After that, use "Updating the server".

Then do these three things.

**1. Email settings.** The server sends logins through the college mail server. Edit `sudo nano /etc/5cs045/smtp_config.php`:

| Setting | What to put |
|---|---|
| `host`, `port` | The mail server and port (usually 587) |
| `username`, `password` | The login of the sending mailbox |
| `from_address`, `from_name` | What students see as the sender |
| `use_starttls` | Keep `true` for port 587 |
| `allowed_email_domain` | Only emails ending in this can sign up, for example `heraldcollege.edu.np` |
| `server_url` | The address of the student websites, used in the login email. Leave it out to use `https://fullstack-student.heraldcollege.edu.np` (the address in the student guide). An IP address here is ignored, because the websites only answer on their name. |
| `signup_url` | The sign-up page's address, used in the link students click to create their account. Leave it out to use `https://fullstack.heraldcollege.edu.np`. An IP address is ignored here too. |
| `admin_email` | Where server alerts go (disk nearly full, login service restarted). Empty means no alerts. |
| `admin_panel_url` | Optional URL included in new admin credential emails. Defaults to `https://fullstack.heraldcollege.edu.np:8443`. |

This file is never in Git; never put the real password anywhere else. Test it on the panel: **Security → Send a test email**.

**2. Disk limits.** They need quotas switched on, once per server:

```bash
sudo apt-get install -y quota
# In /etc/fstab, add usrquota,grpquota to the options of the / line, then:
sudo mount -o remount /
sudo quotacheck -cum /
sudo quotaon /
sudo /usr/local/sbin/5cs045/bin/apply-student-limits.sh
```

**3. Health check.** Open the panel and run **Semester → Run the health check**.

## Updating the server

```bash
cd /opt/5cs045-provisioning
git pull
sudo ./setup/update-server.sh
```

This installs the new scripts, pages and admin panel. It does not touch email settings or students. Run the health check afterwards.

## Common problems

**A student forgot their password.** On **Students**, type their name, press Enter and click **Reset password**.

**A student lost their login email, or says "this email has already been registered".** Open them on **Students** and click **Email their login**.

**A whole lab cannot log in over SSH.** After 5 wrong passwords a computer is blocked for an hour (a week if it happens 3 times in a day), and a lab often shares one address. Click **Unblock** at the top of **Students**.

**"403 Forbidden" on the admin panel.** Your computer is not on the allowed list. Run `sudo /usr/local/sbin/5cs045/bin/admin-allow.sh add` over SSH from that computer.

**The panel says it "is not allowed to run the server tools".** Run `sudo ./setup/update-server.sh` again.

**"Disk quota exceeded".** The student has used their 500 MB. They should delete big files, or you can raise their **Disk limit** on their account.

**"INSERT command denied".** Their database is over 100 MB, so it has become read-only. Dropping unused tables frees space straight away. After deleting many rows, run `sudo mysqlcheck --optimize <username>`. Full access comes back within 15 minutes.

**Sign-up says "We could not send an email".** Nothing was made. If the address is right, the email settings are wrong: check them with **Security → Send a test email**. The student can try again straight away.

**A student never got the link.** It may be in Spam. They can ask for a new one on the sign-up page after 5 minutes, and each link works for 1 hour. If their mail never arrives, add them yourself on **Students**.

**"Your account is ready, but the email with your password did not send".** The account exists. Click **Email their login** for that student once email works again.

**Sign-up says "A link was sent to this email in the last 5 minutes" or "Too many registration attempts from this network".** It allows one link per email every 5 minutes and 40 per network every 15 minutes. Wait, or delete the matching file in `/var/lib/5cs045-ratelimit/` or `/var/lib/5cs045-ip-ratelimit/`.

**Accounts made for addresses that do not exist.** Sign-up used to create the account before sending the email, so a typo or a made-up address still got one. Now nothing is made until the emailed link is used. To find the old ones, look in the sending mailbox for "Address not found" bounces (and on **Logs → Registrations** for "EMAIL SEND FAILED"), and remove those students on **Students**.

**A student has extra accounts made with `name+1@`.** College mail delivers `name+anything@` to `name@`, so sign-up used to let one student register again and again. It now accepts only plain addresses. To find accounts made before that, type `+` in the search box on **Students**, and remove the extras.

**A student's site shows 403.** Usually the folder has no index.php or index.html. Files uploaded over SSH, SCP or SFTP are made readable by the web server automatically when the session ends (Windows' scp uploads files only the student can read). If a folder still shows 403, run `sudo /usr/local/sbin/5cs045/bin/refresh-student-folders.sh <username>`.

**A student's site shows 404.** The files must be inside `workshops`, `exam` or `assessment`.

**A student's site shows 502 or a blank page.** Read `sudo tail /srv/students/<username>/.sessions/php-error.log`.

**`composer install` fails on the server.** The server cannot reach packagist.org. Run `composer install --no-dev` on a laptop and upload the whole folder, including `vendor`.

**The disk is filling up.** If it is on LVM, you can grow it without downtime:

```bash
sudo vgs                                  # check there is free space (VFree)
sudo lvextend -L +100G /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
```

## Limits

Every student gets these automatically, so one account cannot slow down or fill up the server for everyone else:

| Limit | Value | When it is reached |
|---|---|---|
| Disk (everything they store) | 500 MB (change per student on the panel) | Saving fails with "Disk quota exceeded" |
| Database | 100 MB, checked every 15 minutes | The database becomes read-only until it is smaller |
| Programs run over SSH | 1 CPU core, 1 GB memory, 200 processes | The program slows down, or stops if out of memory |
| PHP on their websites | 4 at a time, 128 MB and 30 seconds each | That page fails |
| PHP error log | 5 MB | Trimmed to its last 1 MB |

Students cannot use `cron` or `at`, because those jobs would run outside the limits. The values are at the top of `bin/apply-student-limits.sh` and `bin/enforce-limits.sh`.

## For students: putting a website up

These steps run on the student's own laptop. The example uses the demo project in this repository and the student `sarayu_gautam`.

```bash
# 1. Upload (the "/." puts the files straight into assessment/)
scp -P 50222 -r demo-student-portfolio-blade/. sarayu_gautam@<server>:~/assessment/

# 2. Log in and finish the setup (SSH on this server is on port 50222, not 22)
ssh -p 50222 sarayu_gautam@<server>
cd ~/assessment
composer install --no-dev
cp config.example.php config.php
nano config.php              # your username, password, and username again as the database name
mysql -u sarayu_gautam -p sarayu_gautam < schema.sql
```

**3. Open it:** `https://fullstack-student.heraldcollege.edu.np/~sarayu_gautam/assessment/`. Anything uploaded is live straight away, with no `chmod` needed. To change the site, edit it on the laptop and run the `scp` command again.

## Capacity and hardware

Tested with 800 accounts on this server (8 cores, about 11 GB of memory free when idle):

| Test | Result |
|---|---|
| 800 students logging in over 2 minutes | All got in. Median login 0.2 s, CPU at most 50% |
| 800 students uploading 5 MB each over 2 minutes | All succeeded, CPU at most 61% |
| 800 students logging in in the same second | Only about 300 got in, then the login service got stuck |

A class arriving over a few minutes is fine. If the login service ever gets stuck, `check-logind.sh` restarts it within two minutes and emails `admin_email`; reboot if logins still fail.

**To ask IT for** (not urgent), in a message you can send as it is:

> For the 5CS045 server (10.80.0.250), could we increase it to 32 GB RAM and 12-16 vCPUs, with those resources reserved rather than shared? Please also confirm the disk is on SSD/NVMe storage and the network link is at least 1 Gbps. Load testing showed the current size handles 800 students logging in, but real coursework (composer, PHP, MySQL) needs more memory headroom during busy lab sessions.

## Load testing

Only run this in a quiet window, never while students are working.

**On the server**, create throwaway accounts and let the test computer in:

```bash
cd /opt/5cs045-provisioning
sudo ./test/loadtest/create-accounts.sh 800          # about 15 minutes; passwords go to ~/loadtest-accounts.csv
sudo fail2ban-client set sshd addignoreip <test computer IP>
sudo fail2ban-client set recidive addignoreip <test computer IP>
sudo ./test/loadtest/monitor.sh                      # in a second window; Ctrl-C shows the busiest moments
```

**On another computer**, with a copy of this repository and the CSV:

```bash
python3 -m pip install asyncssh
python3 test/loadtest/ssh_load.py <server IP> loadtest-accounts.csv --scenario login --users 100 --ramp 60
```

- Go up in steps: 100, 200, 400, 800.
- `--scenario` can be `login`, `upload` or `lab` (both).
- `--ramp 60` spreads the logins over a minute, like a real class arriving.

**Clean up afterwards:**

```bash
sudo /usr/local/sbin/5cs045/bin/remove-all-students.sh --prefix loadtest_ --yes
sudo fail2ban-client set sshd delignoreip <test computer IP>
sudo fail2ban-client set recidive delignoreip <test computer IP>
rm ~/loadtest-accounts.csv
```

## Command-line reference

Everything on the panel also works over SSH, which is handy if the panel is down. First run `cd /usr/local/sbin/5cs045/bin`.

| Task | Command |
|---|---|
| Add a student | `sudo ./add-student.sh -u sarayu_gautam -n "Sarayu Gautam" -e sarayu.gautam@heraldcollege.edu.np` |
| Email a student their login | `sudo php resend-credentials.php sarayu.gautam@heraldcollege.edu.np` |
| New password (prints it) | `sudo ./reset-student-password.sh -u sarayu_gautam` |
| See a student's password | `sudo cat /var/lib/5cs045-credentials/sarayu_gautam` |
| Remove a student | `sudo ./remove-student.sh -u sarayu_gautam` |
| Remove everyone | `sudo ./remove-all-students.sh` |
| List students | `sudo ./list-students.sh` |
| Unblock an address | `sudo fail2ban-client set sshd unbanip <address>` |
| Let a computer open the panel | `sudo ./admin-allow.sh add` (this computer) or `sudo ./admin-allow.sh add <address>` |
| Health check | `sudo /usr/local/sbin/5cs045/test/smoke-test.sh` |
| Logs | `sudo tail -50 /var/log/5cs045-registration.log` (also `-provisioning.log`, `-admin.log`) |

## Safety rules

- The real email password lives only in `/etc/5cs045/smtp_config.php`. Never commit it or paste it anywhere.
- Saved student passwords are in `/var/lib/5cs045-credentials/`, readable only by root. Viewing one on the panel is logged.
- Keep the panel's allowed list short: your own computers, not student labs.
- The certificate is self-signed for now. Replace it when the college domains go live.
- To remove everything: `sudo ./setup/uninstall.sh`.

## What is in this repository

```text
admin/                      The admin panel (port 8443); admin/DESIGN.md explains its look
bin/                        The server tools: student lifecycle, limits, admin roles/accounts, and admin-allow.sh
setup/                      00-server-setup.sh (first time), update-server.sh (updates), uninstall.sh
templates/                  nginx, PHP, SSH, fail2ban, sudo and cron settings
test/smoke-test.sh          The health check
test/admin-panel-e2e.js     Browser test of the admin panel (Playwright)
test/loadtest/              SSH and SCP load test
web/                        The student sign-up page and email code
demo-student-portfolio-blade/  Example website for students
docs/Server_Access_Guide.docx  Guide for students
docs/ADMIN_PANEL_ACCESS.md    Technical admin-role, authentication, and account lifecycle reference
docs/VAPT-TEST-ACCOUNTS.md    Temporary VAPT/non-student account lifecycle
```
