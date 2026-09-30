#!/bin/bash
# sshd runs this for every student connection: a login, scp, sftp, or a single command
# (ForceCommand in templates/sshd-students.conf). It runs what the student asked for, exactly as
# sshd would have, and afterwards lets the web server read what they uploaded.
#
# Why: Windows' built-in scp never sets group permissions, so it uploads folders as 700 and files
# as 600. nginx reads student files through the ACL entry for the www-data group, and those modes
# set the ACL mask to ---, so every page uploaded from Windows gave 403 Forbidden.
#
# Everything here runs as the student, so it can only change the student's own files.

# A dropped connection sends SIGHUP, and Ctrl-C in "ssh -t host command" sends SIGINT. Trap them
# (rather than ignore them, which the student's command would inherit) so the repair still runs.
trap ':' HUP INT

if [[ -n "${SSH_ORIGINAL_COMMAND:-}" ]]; then
  "${SHELL:-/bin/bash}" -c "$SSH_ORIGINAL_COMMAND"
else
  "${SHELL:-/bin/bash}" -l
fi
status=$?

# In the background and detached from the connection, so the student never waits for it. When this
# script exits, a terminal session sends SIGHUP to its process group, and the repair is still in that
# group until setsid moves it out. Ignoring SIGHUP from here on means the repair starts out ignoring
# it too (the student's shell above has already finished, so it is not affected).
trap '' HUP
setsid /usr/local/sbin/5cs045/bin/fix-web-access.sh </dev/null >/dev/null 2>&1 &
exit "$status"
