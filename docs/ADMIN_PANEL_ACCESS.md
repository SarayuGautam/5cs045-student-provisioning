# Admin panel access and account model

This document is the technical reference for the admin-panel authorization model.

## Roles

There are exactly two panel roles:

| Role | Account | Panel access |
|---|---|---|
| superadmin | `fullstack` only | Students, Server, Semester, Security, Admin accounts, Logs |
| admin | Explicitly granted server account | Students and Server only |

The `fullstack` username is the superadmin identity. It cannot be revoked from the panel.

An admin opening **Semester**, **Security**, or **Logs** receives:

> You need super admin access to interact with [tab name].

The authorization decision is server-side. Navigation links are not the security boundary.

## Authentication flow

1. nginx exposes the panel only on HTTPS port 8443 and applies `/etc/5cs045/admin-allow.conf` before PHP runs.
2. PHP runs as the unprivileged `5cs045-admin` user.
3. PHP sends requests to `/usr/local/sbin/5cs045/bin/admin-action` through the single sudoers rule in `templates/sudoers-5cs045-admin`.
4. `admin-action` checks the submitted Linux account password against the account's shadow password hash.
5. The account must be `fullstack` or must appear in the root-owned `admin-users` file.
6. Successful authentication creates a random token stored in `/var/lib/5cs045-admin-auth/sessions/`.
7. Every subsequent request re-checks that the account still has a panel role. Removing a role invalidates existing sessions.

The web application never receives a reusable root password and never runs arbitrary root commands.

## Persistent state

The following paths are root-owned:

- `/var/lib/5cs045-admin-auth/admin-users`
- `/var/lib/5cs045-admin-auth/accounts/`
- `/var/lib/5cs045-admin-auth/sessions/`
- `/var/lib/5cs045-admin-auth/fails-user-*`
- `/var/lib/5cs045-admin-auth/fails-ip-*`

The install script creates the first three with restrictive permissions.

## Non-student accounts

The **Admin accounts** page lets the superadmin create a non-student server account.

A created account uses:

- a unique Linux username;
- a normal home directory;
- `/bin/bash`;
- a generated password shown once to the superadmin;
- optional full name and email metadata;
- no sudo membership;
- no student website folders;
- no student database;
- no student quota configuration.

The account can be granted the `admin` panel role during creation.

The superadmin can also remove accounts created through this interface. Removal first revokes panel access, invalidates sessions, and then runs `userdel --remove`.

## Email and username rules

Linux usernames are globally unique, so a student and a non-student account cannot have the same username.

Email is metadata and is not the Linux account key for non-student accounts. Therefore a non-student account may use an email address that is already associated with a student account.

The student registration workflow is separate and still treats the student email as unique.

## Existing VAPT accounts

Older deployments used a `5cs045-panel` Unix group. That group is no longer the authorization mechanism.

After deploying the role system:

- `fullstack` remains superadmin.
- Existing accounts are not automatically granted the new `admin` role.
- To keep an existing non-student account as a panel admin, use **Admin accounts -> Panel administrators**.
- The old `5cs045-panel` group may be removed after the VAPT accounts are no longer needed.

## Student folder controls

The **Students** page also controls each student's workspace layout:

- **Workshop folders through week** creates `~/workshops/week1` through `weekN` and locks any already-created later week folders.
- The student's home directory and `~/workshops` itself are not writable, so files cannot be uploaded outside a managed work folder.
- **Exam access** and **Assessment access** can each be **Locked**, **Open now**, or **Scheduled**. Scheduled times are stored outside the student home and applied automatically every minute.
- A locked Exam/Assessment folder is inaccessible to the student until the admin opens it or its scheduled time arrives.
- Folder-access changes are written to the admin log.

The root-owned policy files live under `/var/lib/5cs045-student-access/`.

## Deployment

Role changes touch both application code and the root-owned server action. Deploy with:

```bash
cd /opt/5cs045-provisioning
git pull
sudo ./setup/update-server.sh
```

The update script installs:

- `bin/admin-action` under `/usr/local/sbin/5cs045/bin/`;
- the PHP application under `/var/www/5cs045-admin/`;
- the sudoers rule;
- the role/account state directories.

Do not edit the live PHP tree or `admin-users` manually unless recovering a broken server.

## Security-page responsibilities

Only the superadmin can:

- grant or revoke the `admin` role from **Admin accounts**;
- create non-student server accounts;
- remove panel-managed non-student accounts;
- change the admin allowlist;
- use Security, Admin accounts, and Logs.

An `admin` can:

- work with student accounts;
- inspect server health and services.

An `admin` cannot reach the Semester, Security, Admin accounts, or Logs application paths successfully, even if they submit the URL directly.

## Logging

Role changes and non-student account creation/removal are written to `/var/log/5cs045-admin.log`.

The Logs page converts timestamps to the Nepal timezone (`Asia/Kathmandu`) for display.

## Credential email

When the superadmin creates a non-student account and checks the **admin** role, an email address can be supplied. The server then emails that new admin:

- the admin-panel URL;
- their username;
- their generated password;
- their `admin` role.

The password is still shown once to the superadmin. A mail failure does not roll back account creation; the panel reports the error so the superadmin can deliver the password by another secure method.

The URL comes from the optional `admin_panel_url` value in `/etc/5cs045/smtp_config.php`. If it is absent or contains an IP address, the default is `https://fullstack.heraldcollege.edu.np:8443`.
