# VAPT test-account lifecycle

This is the current procedure for temporary VAPT access. It replaces the older `5cs045-panel` group instructions.

## Create a VAPT account

Use the `fullstack` superadmin account.

1. Open **Security -> Non-student server accounts**.
2. Create a username such as `vapt_panel`, add the tester's name/email if useful, and leave **Give this account admin-panel access** checked when the tester needs the panel.
3. The panel generates a Linux password and shows it once.
4. Give the tester only the credentials and access they actually need.

The created account is a normal Linux account. It does not receive sudo, student websites, a student database, or student quota settings.

## VAPT panel privileges

A temporary VAPT account granted the `admin` role can use:

- Students
- Server

It cannot use Semester, Security, or Logs. Those URLs return the superadmin-only message from the panel.

## Same email / username rules

A VAPT account may use the same email address as an existing student account because the email is stored as metadata for the non-student account.

The username cannot match a student username because Linux usernames are globally unique on one server.

## After the test

Once the VAPT test is confirmed complete:

1. Use **Security -> Panel administrators** to revoke the temporary account's admin role, if it is still present.
2. If the account was created through the panel, use **Security -> Non-student server accounts -> Remove account** to delete the Linux account and its home directory.
3. Delete any temporary student/VAPT student accounts using the normal student removal flow.
4. Remove any legacy `5cs045-panel` group membership left by an older deployment.

Do not delete the `fullstack` account.

## Recovery for a legacy VAPT account

If `vapt_panel` already existed before the role system was deployed, it is not automatically a panel admin. The superadmin can grant it the `admin` role from **Security -> Panel administrators**. The old `5cs045-panel` group is not required.

## Deployment reminder

After code changes:

```bash
cd /opt/5cs045-provisioning
git pull
sudo ./setup/update-server.sh
```

The live role database and account metadata are under `/var/lib/5cs045-admin-auth/` and should remain root-owned.
