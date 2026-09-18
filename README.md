# 5CS045 Student Server — Provisioning Toolkit

Automates student account creation on the Full Stack VM your IT team is
building: one Linux account per student, a `workshops/` `exams/`
`assessments/` folder each, content that's automatically web-readable with
no manual `chmod`, and total isolation between students — triggered by a
student entering their college email into a web form, which emails back
their username, database name, and a generated password.

Built against your two documents (`5cs045_Assessment_2025-26.docx`,
`5CS045-LessonPlan-2026.docx`) and your old `Server_Access_Guide.docx`, and
tested live, end-to-end, on a real Ubuntu 24.04.4 LTS box — not just
written from memory. See **"How this was tested"** below for exactly what
that means and what's still worth re-checking on the real VM. A new
version of the access guide, reflecting this server, is in `docs/`.

## Quick start

```bash
# On the fresh Ubuntu 24.04 VM from IT, as root:
git clone <wherever-you-put-this-repo> 5cs045-provisioning
cd 5cs045-provisioning
./setup/00-server-setup.sh        # one-time bootstrap
# edit /etc/5cs045/smtp_config.php with real SMTP relay details — see "Email delivery"
./test/smoke-test.sh              # verify isolation actually holds on THIS box

# Then, per student:
./bin/add-student.sh -u s1234567 -n "Full Name"
# ...or point students at https://<server>/register.php (the normal path —
# see docs/Server_Access_Guide.docx, which is what students actually use)

# Made a mistake, or just testing? Full revert:
./setup/uninstall.sh
```

## What's in here

```
setup/00-server-setup.sh    One-time IT bootstrap (installs the stack, deploys everything below)
setup/uninstall.sh          Full revert — see "Reverting / repeated testing"
bin/add-student.sh          Provision one student (idempotent — re-running resets their password)
bin/remove-student.sh       Deprovision one student (backs up their home dir first)
bin/list-students.sh        Audit: who's provisioned, disk usage, last login
templates/                  nginx config, PHP-FPM pool template, sshd hardening, sudoers rule
web/register.php            Self-service registration form (email only)
web/register_handler.php    Its backend (derives username, provisions, emails credentials)
web/lib/smtp_mailer.php     Dependency-free SMTP client — see "Email delivery"
web/smtp_config.php         SMTP relay settings — deployed OUTSIDE the web root, see below
docs/Server_Access_Guide.docx  Student-facing guide — replaces your old one, hand this to students
test/smoke-test.sh          Re-runs the isolation checks below against a live box
```

## Architecture, and why

**One Linux user per student, home directory locked to `700`/`750`, no
sudo, password-based SSH.** This is the same model most shared university
Linux servers use — and matches your old server's model too. I considered
a full chroot jail instead (stronger in theory — a student literally can't
see anything outside it), but rejected it: your students need real shell
access for git, composer, and general PHP CLI work (confirmed by Week 6's
"install Blade" and Week 1's git workflow), and a chroot that supports
that needs a full mirrored toolchain — bash, git, composer, php-cli, CA
certificates for HTTPS — copied into *every* student's jail and kept in
sync by hand forever. That's a maintenance burden that will quietly break
(a `command not found` here, a TLS error there) for a lecturer without a
dedicated sysadmin, in exchange for isolation you already get from plain
Unix permissions. I also didn't use `rbash` (restricted shell) for the
same reason it's usually skipped in practice: it's well-known to be
escapable and would add friction to students' git/composer workflows
without providing a real boundary — Unix permissions are the actual
boundary here, not the shell.

**Password, not SSH key, and why.** The first version of this used
SSH-key-only auth (no password fallback), which is the stronger default
for most servers. I switched to password-based auth because that's what
you asked the registration form to deliver, and it's a defensible choice
for this specific context: Week 1 of the lesson plan is students' *first*
contact with the server, many won't have an SSH keypair yet, and asking
~100+ first/second-years to generate one and paste the public half
correctly into a web form is real support burden for a module, not a
security team, to absorb. It also matches your old server's model, so
students already know the pattern. The trade-off is real — passwords are
more brute-forceable than keys — so I added compensating controls:
`fail2ban` bans an IP after 5 failed SSH attempts in 10 minutes, passwords
are 14 characters of randomly generated, non-ambiguous characters
(`add-student.sh`, avoids `0/O/1/l/I`), no student has sudo, and
`MaxAuthTries 4` in `sshd_config` limits guesses per connection. `-k` in
`add-student.sh` still exists if you want to *additionally* give a
specific account (e.g. a TA) a key — it layers on top of the password,
it doesn't replace it.

**Each student's PHP runs as *that student*, via their own PHP-FPM pool**
(`pm = ondemand`, so an idle pool costs ~0 resources), not as a shared
`www-data` process. This matters for exactly the same reason the shell
isolation does: if PHP execution ran as `www-data` for everyone, one
student's code (buggy or malicious) could read any file `www-data` can
read — which by definition includes everyone's folders, since `www-data`
needs read access to serve them. Running PHP *as the student* means a PHP
script has exactly the access that student has over SSH, no more.
`open_basedir` is set too, as a second, independent layer.

**Automatic read access uses POSIX default ACLs, not `chmod`/`umask`/setgid.**
`setfacl -d -m g:www-data:rx` on each of the three folders means *any* new
file or folder created underneath — including ones a student creates
themselves, arbitrarily deep — automatically gets a `www-data:r-x` ACL
entry, regardless of the student's umask. This is what makes "they never
have to manually give access" actually true rather than aspirational; I
verified it cascades into a subfolder a student creates herself, not just
the three folders `add-student.sh` sets up (see testing section).

**One shared nginx server block for all students**, routing by URL path
(`/~username/workshops/...`) to per-user document roots and per-user
FPM sockets via regex capture groups. This means adding student #200
never touches nginx config or needs an nginx reload — only PHP-FPM gets a
new pool file (and a `reload`, not `restart`, so nobody else is
disconnected).

## Email delivery

`register_handler.php` needs to actually send an email. I didn't use
PHPMailer (the usual choice) because it needs `composer require
phpmailer/phpmailer`, which needs the box to reach `repo.packagist.org` —
unreachable from my sandbox's network allowlist, same limitation noted
below for `composer require` generally. Rather than hand you an
integration I couldn't verify, `web/lib/smtp_mailer.php` is about 120
lines of plain SMTP protocol (STARTTLS, AUTH LOGIN) with no dependencies,
which I *could* test end-to-end against a real local SMTP server:
plain send, STARTTLS negotiation, AUTH LOGIN with both correct and
incorrect credentials (correctly rejected), dot-stuffing in the message
body, and — importantly — that PHP's default strict certificate
verification correctly refuses a self-signed/untrusted cert, so a real
relay's cert gets properly validated rather than silently accepted. If
you'd rather use PHPMailer, the one call site in `register_handler.php`
is a small, isolated swap.

**You need to edit `/etc/5cs045/smtp_config.php`** with your actual SMTP
relay host, port, and credentials before registration emails will send —
ask IT for the college's outgoing mail relay (often the same server
handles staff email, or your email provider's own SMTP relay if you're on
Google Workspace/Office 365). It's pre-filled with placeholder
`heraldcollege.edu.np` values inferred from your old server's URLs, not
verified — confirm the real relay and the real student email domain
(`allowed_email_domain`) with IT/registry.

**A security issue I found and fixed while building this:** my first
version put `smtp_config.php` inside the web root (`/var/www/html/`)
alongside `register.php`. Nothing in the nginx config would have matched
a direct request for it, which meant it would have fallen through to
being served as **plain-text PHP source** — leaking the SMTP password to
anyone who requested that URL. I caught this on review, not by accident
in testing, which is exactly why it's worth someone other than the
original author reviewing security-sensitive code. Fixed two ways:
`smtp_config.php` is now deployed *outside* the web root entirely
(`/etc/5cs045/`, loaded by an absolute path), and there's also an explicit
nginx `deny` on that path and on `/lib/` as a second layer, in case a
future change ever puts a similar file back inside `/var/www/html/`.

## About your testing question: skip the CentOS Docker idea

Two separate issues with that plan:

1. **Wrong OS family.** Your VM is Ubuntu 24.04 (systemd, apt, AppArmor,
   Debian-style paths like `/etc/php/8.3/fpm/pool.d/`). CentOS is a
   different family (SELinux, yum/dnf, different default paths and
   permission defaults). Testing there won't surface the Ubuntu-specific
   issues that would actually bite you — and I hit several while building
   this (see below) that are exactly the kind of thing that wouldn't
   translate from a CentOS test.
2. **Containers vs. this specific workload.** What you're building leans
   heavily on systemd service management (nginx, PHP-FPM, MariaDB, sshd
   all running as proper services) and OpenSSH daemon behaviour. Docker
   containers typically don't run systemd as PID 1, so `systemctl` calls
   either fail outright or need workarounds — which is realistic risk, not
   a hypothetical: I hit exactly this in my own test sandbox (also a
   container) and had to hand-start daemons and use raw `SIGUSR2` signals
   instead of `systemctl reload`. That's a fine workaround for me to
   validate script *logic*, but it means a Docker test wouldn't actually
   prove your SSH daemon, service supervision, or reload behaviour work —
   the exact things you most want to catch before IT sees this.

**What I did instead:** built and tested this against a genuine
**Ubuntu 24.04.4 LTS** environment with root access — the same OS, PHP
version range, and MariaDB version your IT team specified. For final
sign-off, I'd still recommend a real VM over a container — a container
adds risk for this specific workload for the same systemd/sshd reasons
above, even on the right OS. **[Multipass](https://multipass.run/)**
(Canonical's own tool, `multipass launch 24.04`) is the fastest way to get
a real, disposable Ubuntu 24.04 VM for a final pre-handoff check; a scratch
cloud VM works just as well if that's easier for you.

## How this was tested

I ran this live, not just read it back to check it looked right. On a real
Ubuntu 24.04.4 LTS box with nginx 1.24 / PHP 8.3.6 / MariaDB 10.11.14
(matching your spec), I created real Linux accounts and:

- Confirmed one student **cannot** list, read, write, or even detect the
  existence of another's home directory, database credentials, or
  `/srv/students/` listing itself — over both `su` and a genuine SSH
  session
- Confirmed a file — and a whole subfolder a student created herself,
  two levels deep — automatically got `www-data` read access with **zero**
  manual `chmod`, and that `www-data` still **couldn't write** to it or see
  `.ssh`/database credentials
- Sent real HTTP requests through nginx → PHP-FPM and confirmed PHP
  actually executes *as the student* (not `www-data`), that a crafted PHP
  script attempting to read another student's file is blocked, and that
  `.git/config` is **not** servable
- Confirmed `smtp_config.php` is genuinely blocked (HTTP 404, no source
  leak) after fixing the issue described above
- Generated a real password, confirmed **both** SSH login and MySQL login
  work with it, then re-ran `add-student.sh` (simulating a student
  resubmitting the form) and confirmed a genuinely different password came
  back, the **old MySQL password is rejected** while the new one works,
  and SSH rejects a wrong password (I directly confirmed a wrong-password
  SSH rejection and the equivalent old/new MySQL pair; a final joint
  "old SSH password specifically, post-reset" run kept hitting my
  sandbox's process instability rather than revealing anything new — see
  below — so that exact pairing is confirmed by construction, via the
  identical `chpasswd`/`ALTER USER` replace-not-append mechanism, rather
  than one final clean empirical run)
- Ran the *entire* registration form flow over real HTTP with just an
  email address — including a wrong-domain attempt (correctly rejected)
  and confirmed `www-data` can run `add-student.sh` as root via `sudo` but
  **nothing else** (`sudo cat /etc/shadow` correctly refused) — and
  separately confirmed the SMTP mailer itself (STARTTLS, AUTH, correct and
  incorrect credentials, dot-stuffing) against a real local SMTP server
- Ran a full add → remove round trip, and a full
  **setup → provision → uninstall → setup again → provision again** cycle,
  confirming `uninstall.sh` genuinely returns the box to a re-provisionable
  clean state (nginx default site restored, no orphaned students,
  databases, or FPM pools)
- Confirmed HTTPS with a self-signed cert works end-to-end, including the
  exact Week 10 scenario: a `Secure`-flagged cookie is correctly sent only
  over HTTPS

Bugs this process found and fixed (not left for you to hit):

1. `tr </dev/urandom | head -c24` for password generation triggered
   `SIGPIPE` under `set -o pipefail` (a classic, easy-to-miss shell
   footgun) and silently killed the whole script partway through. I hit
   this **twice** — once for the original DB password, fixed it, then
   reintroduced the identical pattern for the unified SSH/MySQL password
   and caught it again in testing. Both now avoid piping a
   possibly-longer-than-N stream into `head -c N`.
2. The PHP-FPM pool template path was resolved relative to the script's
   own location, which broke depending on exactly how the deploy
   directory was laid out — fixed by standardizing on `bin/` and
   `templates/` as fixed sibling directories.
3. The registration audit log had no file pre-created with `www-data`
   write access, so failures were being silently swallowed — the setup
   script now pre-creates it with correct ownership.
4. `apt-get update` returns a non-zero exit code if *any* configured repo
   fails — even one nothing in this toolkit depends on — which silently
   killed `00-server-setup.sh` under `set -e` before it installed
   anything. Now tolerated explicitly; a package that's actually needed
   still fails loudly at the install step.
5. `smtp_config.php` inside the web root with no matching nginx location
   would have leaked the SMTP password as plain text — see "Email
   delivery" above.

**What I couldn't fully test here, and would spot-check on the real VM:**
`systemctl`-based service management and reload (my sandbox has no real
systemd — I used direct daemon invocation and manual `SIGUSR2`/foreground
signals as a stand-in throughout, and wrote the actual scripts to use
`systemctl` for you); a full `composer require` package install
(`repo.packagist.org` isn't reachable from my sandbox's network allowlist
— `composer` itself and `git clone` both work); and IPv6 (disabled in my
sandbox, harmless — just delete the `listen [::]` lines if the real VM
doesn't have IPv6 either). My sandbox also could not keep background
services (MariaDB, sshd, the SMTP server) alive between separate commands
— every restart needed re-doing in the same breath as whatever depended
on it, which is why some of the testing above describes pairs of checks
run separately rather than one continuous session; this is a quirk of my
test container's process handling, unrelated to anything that will affect
the real VM.

## Two gaps in your original spec I filled in

**phpMyAdmin.** Not in your VM's stack list, but Task 1 in the assessment
brief has students "Creating a table in MySQL via phpMyAdmin" — without it,
that task can't be completed as written. Added it (`setup/` installs it
non-interactively, `templates/nginx-students.conf` serves it behind the
same HTTP Basic Auth as the registration form), and tested that it serves
correctly and that each student's own MariaDB grant (created by
`add-student.sh`) scopes them to their own database inside it.

**HTTPS.** Not in the original stack either, but Week 10 has students
testing the `Secure` cookie flag — which only actually takes effect over
HTTPS; over plain HTTP the flag does nothing testable. `setup/` generates
a self-signed cert so this works immediately (students will see a one-time
browser trust warning to click past). Swap in a real cert once you know
whether you have a domain pointed at this VM:
- **Have a domain?** `certbot --nginx` (Let's Encrypt) for a trusted cert,
  no warnings.
- **Internal-only / no domain?** Keep the self-signed cert — it's genuinely
  fine for teaching purposes, students just need one click past the
  warning, or install the college's own internal CA if you have one.

I also blocked `.git/` from being served over HTTP in the nginx config —
not asked for, but since your rubric explicitly checks Git commit logs
("Git commit logs will be checked"), students will have real `.git`
folders inside their web-served folders. An unblocked `.git/` directory
lets anyone reconstruct a student's entire repo and history with an
off-the-shelf tool (`git-dumper` and similar) — this would otherwise
affect every single student on the server, not just a theoretical risk.

## Day to day

**Add a student manually** (normally students do this themselves via
`register.php` — see below):
```bash
sudo ./bin/add-student.sh -u s1234567 -n "Full Name"
```
Safe to re-run for the same username — it generates a **new** password
(same as resubmitting the form does) and refreshes ACLs/FPM config.

**Remove a student** (backs up their home directory to
`/srv/students-archive/` first):
```bash
sudo ./bin/remove-student.sh -u s1234567
```

**See who's provisioned:**
```bash
sudo ./bin/list-students.sh
```

**Their URLs:**
```
https://<server>/~s1234567/workshops/
https://<server>/~s1234567/exams/
https://<server>/~s1234567/assessments/
```

## Reverting / repeated testing

Since you mentioned you're testing this first: the cleanest revert, if
it's available to you, is a **VM snapshot** taken before you run
`setup/00-server-setup.sh` — reverting the snapshot undoes literally
everything, including anything an uninstall script might miss. If that's
not an option (e.g. testing directly on the VM IT already gave you),
`setup/uninstall.sh` removes every provisioned student (backed up first),
all 5CS045 nginx/sshd/sudoers config, and restores the stock nginx default
site — while leaving nginx/PHP/MariaDB/phpMyAdmin themselves *installed*,
since re-installing the base stack every time you want to retest isn't
meaningfully cleaner, just slower. Pass `--purge-packages` if you want
those removed too. I ran the full
**setup → provision → uninstall → setup again → provision again** cycle
myself (see "How this was tested") to confirm it actually leaves things
re-provisionable, not just tidy-looking.

## About the registration form

`register.php` takes a single college email address. It's still gated
with a shared HTTP Basic Auth password (set during
`setup/00-server-setup.sh`) rather than full institutional SSO — I don't
have any details of Wolverhampton's or Herald's actual login system to
integrate against, and a fake integration would be worse than an honest,
simple gate. This is the same trust model as a Moodle enrolment key. If
you do have institutional SSO available (Shibboleth, LDAP, etc.) and want
it properly integrated, that's a reasonable upgrade — worth a separate
conversation with IT about what's actually available.

**The username is derived automatically** from the local part of the
email (`s1234567@heraldcollege.edu.np` → `s1234567`), lowercased and
sanitized to the same safe character set `add-student.sh` enforces. If
your students' real emails aren't ID-based, this still produces a valid,
unique username — just not as tidy — from whatever's before the `@`.
**The email domain is restricted** to `allowed_email_domain` in
`smtp_config.php` (currently `heraldcollege.edu.np`, inferred from your
old server's URLs — confirm this is actually your student email domain).
**Resubmitting is the reset path**: there's no separate "forgot my
password" flow because submitting the same email again *is* one —
`add-student.sh` generates a fresh password every run. A simple
per-email rate limit (`/var/lib/5cs045-ratelimit/`, one request per 5
minutes) stops someone hammering the form with a classmate's email as a
minor harassment vector.

Every field is validated server-side, and nothing reaches a shell without
`escapeshellarg()` — see the comments in `register_handler.php` for the
exact security model. The password itself is never written anywhere
`www-data` can read on an ongoing basis; it's parsed from
`add-student.sh`'s output at the moment `www-data` itself just caused it
to be generated via the narrowly-scoped sudo rule, not read back from the
student's private credentials file (which stays `600`, owned by the
student, exactly as tested above).

## Before you hand this to IT

1. Run `./setup/00-server-setup.sh` on a real (ideally disposable) Ubuntu
   24.04 VM — Multipass is the quickest way to get one locally, or take a
   snapshot first if you're testing on a persistent VM (see "Reverting").
2. Edit `/etc/5cs045/smtp_config.php` with real SMTP relay details and
   confirm `allowed_email_domain` — registration emails silently fail
   until this is done.
3. Run `./test/smoke-test.sh` and confirm everything passes.
4. Decide on the HTTPS path (self-signed is fine to start; swap later).
5. Spot-check a real `composer require`, a real `systemctl reload
   php8.3-fpm`, and register a test account through the actual form end
   to end (confirm the email arrives) — the things my sandbox couldn't
   fully prove out (see "How this was tested").
6. Fill in the real server address in `docs/Server_Access_Guide.docx`
   (search for `<server-address>`) and give it to students.
7. Hand the whole repo to IT along with this README.
