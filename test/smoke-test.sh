#!/usr/bin/env bash
#
# smoke-test.sh — re-run the isolation checks on the real VM before trusting
# it with real students. Creates two throwaway accounts, tries to break
# isolation between them every way that matters, then cleans up.
#
# Usage: sudo ./smoke-test.sh
#
set -uo pipefail  # deliberately not -e: we want every check to run and report, not stop at the first failure
DEPLOY_ROOT="/usr/local/sbin/5cs045"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

echo "=== setting up two throwaway test accounts ==="
OUT_A="$("$DEPLOY_ROOT/bin/add-student.sh" -u smoketest_a -n "Smoke Test A")"
OUT_B="$("$DEPLOY_ROOT/bin/add-student.sh" -u smoketest_b -n "Smoke Test B")"
PW_A="$(echo "$OUT_A" | grep '^Password:' | awk '{print $2}')"

FPM_PID_FILE="/run/php/php8.3-fpm.pid"
[[ -f "$FPM_PID_FILE" ]] && kill -USR2 "$(cat "$FPM_PID_FILE")" && sleep 1

echo ""
echo "=== password login checks ==="
if command -v sshpass >/dev/null; then
  timeout 8 sshpass -p "$PW_A" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=4 smoketest_a@localhost 'echo ok' 2>/dev/null | grep -q ok \
    && ok "generated password logs in over SSH" \
    || bad "generated password did NOT log in over SSH — check sshd_config PasswordAuthentication and chpasswd in add-student.sh"
else
  echo "  SKIPPED (install sshpass to test SSH login: apt-get install sshpass)"
fi
mysql -u smoketest_a -p"$PW_A" -e "SELECT 1;" >/dev/null 2>&1 \
  && ok "generated password logs in to MySQL" \
  || bad "generated password did NOT log in to MySQL — check the ALTER USER step in add-student.sh"

echo ""
echo "=== isolation checks ==="

su - smoketest_a -s /bin/bash -c 'ls /srv/students/smoketest_b/' >/dev/null 2>&1 \
  && bad "A can list B's home directory" || ok "A cannot list B's home directory"

su - smoketest_a -s /bin/bash -c 'cat /srv/students/smoketest_b/credentials.txt' >/dev/null 2>&1 \
  && bad "A can read B's credentials" || ok "A cannot read B's credentials"

su - smoketest_a -s /bin/bash -c 'echo x > /srv/students/smoketest_b/assessments/x' >/dev/null 2>&1 \
  && bad "A can write into B's assessments folder" || ok "A cannot write into B's assessments folder"

su - smoketest_a -s /bin/bash -c 'ls /srv/students/' >/dev/null 2>&1 \
  && bad "A can enumerate other student usernames" || ok "A cannot enumerate other student usernames"

echo ""
echo "=== automatic read-access checks (no manual chmod) ==="
su - smoketest_a -s /bin/bash -c 'mkdir -p /srv/students/smoketest_a/assessments/sub && echo hi > /srv/students/smoketest_a/assessments/sub/f.txt'
su -s /bin/bash www-data -c 'cat /srv/students/smoketest_a/assessments/sub/f.txt' >/dev/null 2>&1 \
  && ok "www-data can read a file A just created, in a folder A just created, with zero chmod" \
  || bad "www-data could NOT read A's newly-created content — ACL inheritance isn't working"

su -s /bin/bash www-data -c 'echo tampered > /srv/students/smoketest_a/assessments/sub/f.txt' >/dev/null 2>&1 \
  && bad "www-data can WRITE to A's content (should never be able to)" \
  || ok "www-data cannot write to A's content"

echo ""
echo "=== PHP-FPM process isolation (only meaningful if nginx+fpm are already running this config) ==="
if curl -sf http://localhost/~smoketest_a/assessments/sub/ >/dev/null 2>&1 || command -v curl >/dev/null; then
  su - smoketest_a -s /bin/bash -c 'echo "<?php echo posix_getpwuid(posix_geteuid())[\"name\"]; ?>" > /srv/students/smoketest_a/assessments/whoami.php'
  RESULT="$(curl -s http://localhost/~smoketest_a/assessments/whoami.php 2>/dev/null)"
  [[ "$RESULT" == "smoketest_a" ]] \
    && ok "PHP for A's site actually executes as smoketest_a (got: '$RESULT')" \
    || bad "PHP did not execute as smoketest_a over HTTP (got: '$RESULT') — check nginx is deployed and reloaded"

  su - smoketest_a -s /bin/bash -c "cat > /srv/students/smoketest_a/assessments/attack.php" <<-'PHP'
	<?php echo @file_get_contents('/srv/students/smoketest_b/assessments/index.php') === false ? 'BLOCKED' : 'LEAKED';
	PHP
  RESULT="$(curl -s http://localhost/~smoketest_a/assessments/attack.php 2>/dev/null)"
  [[ "$RESULT" == "BLOCKED" ]] \
    && ok "A's PHP code cannot read B's files via a crafted request" \
    || bad "A's PHP code COULD read B's files (got: '$RESULT') — check open_basedir in the FPM pool"

  git -C /srv/students/smoketest_a/assessments init -q 2>/dev/null
  echo "[core]" > /srv/students/smoketest_a/assessments/.git/config 2>/dev/null
  chown -R smoketest_a:smoketest_a /srv/students/smoketest_a/assessments/.git 2>/dev/null
  CODE="$(curl -s -o /dev/null -w '%{http_code}' http://localhost/~smoketest_a/assessments/.git/config 2>/dev/null)"
  [[ "$CODE" == "404" ]] \
    && ok ".git metadata is not servable over HTTP" \
    || bad ".git metadata IS servable over HTTP (got HTTP $CODE) — every student's commit history would be exposed"

  CODE="$(curl -s -o /dev/null -w '%{http_code}' http://localhost/smtp_config.php 2>/dev/null)"
  [[ "$CODE" == "404" ]] \
    && ok "smtp_config.php is not servable over HTTP (SMTP password not exposed)" \
    || bad "smtp_config.php returned HTTP $CODE, not 404 — the SMTP password may be leaking as plain text, check the nginx deny rule"
else
  echo "  SKIPPED: curl not available or nginx not reachable on localhost"
fi

echo ""
echo "=== cleaning up test accounts ==="
"$DEPLOY_ROOT/bin/remove-student.sh" -u smoketest_a --no-backup >/dev/null 2>&1
"$DEPLOY_ROOT/bin/remove-student.sh" -u smoketest_b --no-backup >/dev/null 2>&1

echo ""
echo "============================================"
echo " ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && echo " Looks safe to provision real students." \
                     || echo " DO NOT provision real students until every FAIL above is fixed."
echo "============================================"
exit "$FAIL"
