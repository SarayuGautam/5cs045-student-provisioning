# Student Server Access Guide

## Connection

SSH and SCP use port **22**.

```bash
ssh -p 22 <username>@<server>
```

```bash
scp -P 22 -r <local-folder>/. <username>@<server>:<remote-folder>/
```

Use the server address supplied by your tutor or IT team.

## Folder layout

Your home directory is a container. Put student work only in the managed folders:

```
~/
├── workshops/
│   ├── week1/
│   ├── week2/
│   └── weekN/
├── assessment/
└── exam/
```

Do **not** upload directly to `~/` or `~/workshops/`. The server deliberately keeps those locations non-writable.

Weekly workshop example:

```bash
scp -P 22 -r week1/. <username>@<server>:~/workshops/week1/
```

## Exam and Assessment folders

The **Exam** and **Assessment** folders are controlled per student by the admin panel.

They can be:

- **Locked** — the student cannot enter or upload.
- **Open now** — available immediately.
- **Scheduled** — opens automatically at the configured time.

Before a scheduled opening, `Permission denied` is expected. Do not change permissions with `chmod`, use `sudo`, or try another account. Upload again after the folder is opened.

Assessment example:

```bash
scp -P 22 -r my-project/. <username>@<server>:~/assessment/
```

Exam example:

```bash
scp -P 22 -r exam-work/. <username>@<server>:~/exam/
```

## Student website

Student websites are served at:

`https://fullstack-student.heraldcollege.edu.np/~<username>/`

Examples:

```
https://fullstack-student.heraldcollege.edu.np/~<username>/workshops/week1/
https://fullstack-student.heraldcollege.edu.np/~<username>/assessment/
https://fullstack-student.heraldcollege.edu.np/~<username>/exam/
```

Only the managed web folders are published.

## PHP/MySQL projects

For a project that needs Composer and MySQL:

```bash
ssh -p 22 <username>@<server>
cd ~/assessment
composer install --no-dev
cp config.example.php config.php
nano config.php
mysql -u <username> -p <username> < schema.sql
```

Keep `config.php` private because it contains your database password.

## Common problems

**SSH connection times out:** check your network/VPN and use port 22.

**Permission denied when uploading:** verify that you are uploading to `~/workshops/weekN/`, `~/assessment/`, or `~/exam/`, and that the destination is currently open for your account.

**Website shows 403:** make sure the folder contains `index.php` or `index.html`. Do not change permissions yourself.

**Website shows 404:** make sure the files are inside `workshops`, `assessment`, or `exam` on the student website host.

**Disk quota exceeded:** remove unnecessary files or ask the tutor/admin to review your disk limit.

This guide reflects the current 5CS045 student-server layout. Class-specific connection details supplied by the tutor or IT team take precedence.
