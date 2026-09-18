# Applying the v2 update

This package is an update pack for your existing repository. Replace the matching files in the existing Git repository. Do not delete the other repository files.

## Main behavior changes

1. `register.php` is public and has a clean Herald branded form.
2. `register_handler.php` uses CSRF protection, rejects duplicate registrations, and keeps a registration record after a successful email.
3. `nginx-students.conf` removes Basic Auth from registration but keeps it for phpMyAdmin.
4. `reset-student-password.sh` is the admin-only password reset command.
5. `test/smtp-test.php` sends a single test email using the live SMTP config.
6. `smoke-test.sh` uses HTTPS and checks public registration plus phpMyAdmin protection.
7. `00-server-setup.sh` installs the v2 behavior on a fresh VM and creates the new admin password file with mode 640.

## Current VM

After replacing the files in Git and pulling them onto the current VM:

```bash
cd /opt/5cs045-provisioning
sudo ./setup/apply-v2-existing.sh
```

The helper preserves the existing phpMyAdmin Basic Auth password. It does not overwrite `/etc/5cs045/smtp_config.php` because that file contains the real SMTP secret.

Before testing registration, edit `/etc/5cs045/smtp_config.php` and set:

```text
server_url = your real student-facing HTTPS address
```

Also set the confirmed SMTP values when IT provides them. For the temporary test requested now, you can use the guessed values already supplied in the repository template.
