#!/usr/bin/env bash
set -uo pipefail

DEPLOY_ROOT="/usr/local/sbin/5cs045"
PASS=0
FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

BASE_URL="https://localhost"
# Students' websites are only on their own name (templates/nginx-students.conf). Checks of
# student pages ask for that name, sent straight to this server.
STUDENT_HOST="fullstack-student.heraldcollege.edu.np"
STUDENT_URL="https://${STUDENT_HOST}"
CURL=(curl -k -s --noproxy '*' --resolve "${STUDENT_HOST}:443:127.0.0.1" --resolve "${STUDENT_HOST}:8443:127.0.0.1")
# SSH on this server is not on port 22; log in on the first port sshd answers on
SSH_PORT=22
for p in $("${DEPLOY_ROOT}/bin/ssh-ports.sh" 2>/dev/null | tr ',' ' '); do
  if timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/${p}" 2>/dev/null; then SSH_PORT="$p"; break; fi
done

check_code() {
  local url="$1" expected="$2" label="$3"
  local code
  code="$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)"
  [[ "$code" == "$expected" ]] && ok "$label" || bad "$label (got HTTP $code)"
}

echo "=== setting up two throwaway test accounts ==="
OUT_A="$($DEPLOY_ROOT/bin/add-student.sh -u smoketest_a -n "Smoke Test A")"
OUT_B="$($DEPLOY_ROOT/bin/add-student.sh -u smoketest_b -n "Smoke Test B")"
PW_A="$(echo "$OUT_A" | grep '^Password:' | awk '{print $2}')"

FPM_PID_FILE="/run/php/php8.3-fpm.pid"
[[ -f "$FPM_PID_FILE" ]] && kill -USR2 "$(cat "$FPM_PID_FILE")" && sleep 1

echo ""
echo "=== password login checks ==="
if command -v sshpass >/dev/null; then
  timeout 8 sshpass -p "$PW_A" ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=4 smoketest_a@localhost 'echo ok' 2>/dev/null | grep -q ok \
    && ok "generated password logs in over SSH" \
    || bad "generated password did NOT log in over SSH"
else
  echo "  SKIPPED: sshpass is not installed"
fi
mysql -u smoketest_a -p"$PW_A" -e "SELECT 1;" >/dev/null 2>&1 \
  && ok "generated password logs in to MySQL" \
  || bad "generated password did NOT log in to MySQL"

echo ""
echo "=== student isolation checks ==="
su - smoketest_a -s /bin/bash -c 'ls /srv/students/smoketest_b/' >/dev/null 2>&1 \
  && bad "A can list B's home directory" || ok "A cannot list B's home directory"
su - smoketest_a -s /bin/bash -c 'cat /var/lib/5cs045-credentials/smoketest_b' >/dev/null 2>&1 \
  && bad "A can read B's credentials" || ok "A cannot read B's credentials"
[[ ! -e /srv/students/smoketest_a/credentials.txt ]] \
  && ok "no credentials.txt in the student's home" || bad "credentials.txt is in the student's home"
su - smoketest_a -s /bin/bash -c 'echo x > /srv/students/smoketest_b/assessment/x' >/dev/null 2>&1 \
  && bad "A can write into B's assessment folder" || ok "A cannot write into B's assessment folder"
su - smoketest_a -s /bin/bash -c 'ls /srv/students/' >/dev/null 2>&1 \
  && bad "A can enumerate other student usernames" || ok "A cannot enumerate other student usernames"

echo ""
echo "=== automatic read-access checks ==="
su - smoketest_a -s /bin/bash -c 'mkdir -p /srv/students/smoketest_a/assessment/sub && echo hi > /srv/students/smoketest_a/assessment/sub/f.txt'
su -s /bin/bash www-data -c 'cat /srv/students/smoketest_a/assessment/sub/f.txt' >/dev/null 2>&1 \
  && ok "www-data can read newly-created content without chmod" \
  || bad "www-data could not read newly-created content"
su -s /bin/bash www-data -c 'echo tampered > /srv/students/smoketest_a/assessment/sub/f.txt' >/dev/null 2>&1 \
  && bad "www-data can write to student content" \
  || ok "www-data cannot write to student content"
# Windows' built-in scp uploads folders as 700 and files as 600, which hides them from the web
# server. bin/student-ssh-session.sh repairs that when the SSH session ends; this does the same.
[[ "$(sshd -T -C "user=smoketest_a,host=localhost,addr=127.0.0.1" 2>/dev/null | awk '$1 == "forcecommand" { print $2 }')" == "${DEPLOY_ROOT}/bin/student-ssh-session.sh" ]] \
  && ok "student SSH sessions go through student-ssh-session.sh" \
  || bad "student SSH sessions do not go through student-ssh-session.sh (see /etc/ssh/sshd_config.d/50-students.conf)"
if command -v sshpass >/dev/null; then
  SSH_A=(timeout 20 sshpass -p "$PW_A" ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=4 smoketest_a@localhost)
  "${SSH_A[@]}" 'mkdir -m 700 ~/workshops/winupload && printf ok > ~/workshops/winupload/index.html && chmod 600 ~/workshops/winupload/index.html' >/dev/null 2>&1
  CODE=""
  for _ in $(seq 1 30); do
    CODE="$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$STUDENT_URL/~smoketest_a/workshops/winupload/" 2>/dev/null)"
    [[ "$CODE" == "200" ]] && break
    sleep 0.5
  done
  [[ "$CODE" == "200" ]] \
    && ok "files uploaded as 700/600 (Windows scp) are on the web once the SSH session ends" \
    || bad "files uploaded as 700/600 (Windows scp) are not on the web (got HTTP $CODE)"
  "${SSH_A[@]}" 'exit 42' >/dev/null 2>&1
  [[ $? -eq 42 ]] && ok "SSH passes a command's exit status through" || bad "SSH did not pass a command's exit status through"
else
  echo "  SKIPPED: sshpass is not installed"
fi

echo ""
echo "=== student folder layout and access checks ==="
su - smoketest_a -s /bin/bash -c 'touch /srv/students/smoketest_a/outside.txt' >/dev/null 2>&1   && bad "student can write directly in their home" || ok "student cannot write directly in their home"
su - smoketest_a -s /bin/bash -c 'touch /srv/students/smoketest_a/workshops/outside.txt' >/dev/null 2>&1   && bad "student can write directly in ~/workshops" || ok "student cannot write directly in ~/workshops"
su - smoketest_a -s /bin/bash -c 'printf ok > /srv/students/smoketest_a/workshops/week1/write-test.txt' >/dev/null 2>&1   && ok "student can write inside an allowed workshop week" || bad "student cannot write inside an allowed workshop week"
"$DEPLOY_ROOT/bin/student-access.sh" set smoketest_a 1 locked 0 locked 0 0 >/dev/null 2>&1   || bad "could not lock Exam and Assessment for folder-access test"
su - smoketest_a -s /bin/bash -c 'touch /srv/students/smoketest_a/exam/locked.txt' >/dev/null 2>&1   && bad "student can write to locked Exam folder" || ok "locked Exam folder rejects student writes"
su - smoketest_a -s /bin/bash -c 'touch /srv/students/smoketest_a/assessment/locked.txt' >/dev/null 2>&1   && bad "student can write to locked Assessment folder" || ok "locked Assessment folder rejects student writes"
"$DEPLOY_ROOT/bin/student-access.sh" set smoketest_a 1 open 0 scheduled "$(( $(date +%s) + 600 ))" >/dev/null 2>&1   || bad "could not schedule Assessment access for folder-access test"
su - smoketest_a -s /bin/bash -c 'touch /srv/students/smoketest_a/assessment/future.txt' >/dev/null 2>&1   && bad "student can write to Assessment before its scheduled time" || ok "scheduled Assessment folder remains locked before its opening time"
"$DEPLOY_ROOT/bin/student-access.sh" set smoketest_a 1 open 0 open 0 >/dev/null 2>&1   || bad "could not restore open folder access after folder-access test"

echo ""
echo "=== PHP-FPM process isolation ==="
su - smoketest_a -s /bin/bash -c 'echo "<?php echo posix_getpwuid(posix_geteuid())[\"name\"]; ?>" > /srv/students/smoketest_a/assessment/whoami.php'
RESULT="$("${CURL[@]}" "$STUDENT_URL/~smoketest_a/assessment/whoami.php" 2>/dev/null)"
[[ "$RESULT" == "smoketest_a" ]] \
  && ok "PHP for A executes as smoketest_a" \
  || bad "PHP did not execute as smoketest_a (got: '$RESULT')"
su - smoketest_a -s /bin/bash -c "cat > /srv/students/smoketest_a/assessment/attack.php" <<-'PHP'
<?php echo @file_get_contents('/srv/students/smoketest_b/assessment/index.php') === false ? 'BLOCKED' : 'LEAKED';
PHP
RESULT="$("${CURL[@]}" "$STUDENT_URL/~smoketest_a/assessment/attack.php" 2>/dev/null)"
[[ "$RESULT" == "BLOCKED" ]] \
  && ok "A's PHP code cannot read B's files" \
  || bad "A's PHP code could read B's files (got: '$RESULT')"
su - smoketest_a -s /bin/bash -c "cat > /srv/students/smoketest_a/assessment/size.php" <<-'PHP'
<?php echo strlen(file_get_contents('php://input'));
PHP
RESULT="$(head -c 2097152 /dev/zero | "${CURL[@]}" --data-binary @- "$STUDENT_URL/~smoketest_a/assessment/size.php" 2>/dev/null)"
[[ "$RESULT" == "2097152" ]] \
  && ok "a 2 MB upload reaches the student's PHP" \
  || bad "a 2 MB upload did not reach PHP (got: '${RESULT:0:60}'); check client_max_body_size in nginx"
git -C /srv/students/smoketest_a/assessment init -q 2>/dev/null
echo "[core]" > /srv/students/smoketest_a/assessment/.git/config 2>/dev/null
chown -R smoketest_a:smoketest_a /srv/students/smoketest_a/assessment/.git 2>/dev/null
check_code "$STUDENT_URL/~smoketest_a/assessment/.git/config" "404" ".git metadata is not servable over HTTPS"
check_code "$BASE_URL/smtp_config.php" "404" "smtp_config.php is not servable over HTTPS"


ROOT_PAGE="$("${CURL[@]}" "$STUDENT_URL/~smoketest_a/" 2>/dev/null)"
[[ "$ROOT_PAGE" == *"Welcome, smoketest_a"* ]] && ok "student root URL shows the welcome page" || bad "student root URL did not show the welcome page"
FOLDER_PAGE="$("${CURL[@]}" "$STUDENT_URL/~smoketest_b/workshops/" 2>/dev/null)"
[[ "$FOLDER_PAGE" == *"weekly workshop work"* ]] && ok "an empty folder shows its short description" || bad "an empty folder did not show its description"

echo ""
echo "=== resource limit checks ==="
UID_A="$(id -u smoketest_a)"
QUOTA_MOUNT="$(df --output=target /srv/students | tail -1)"
if [[ "$(quotaon -pu "$QUOTA_MOUNT" 2>/dev/null)" == *" is on" ]]; then
  QUOTA_OUT="$(quota -vu smoketest_a 2>&1)"
  [[ "$QUOTA_OUT" == *512000* ]] \
    && ok "new student has the 500 MB disk quota" || bad "new student has no disk quota"
else
  echo "  SKIPPED: disk quotas are not enabled (see \"Resource limits\" in README.md)"
fi
[[ "$(systemctl show "user-${UID_A}.slice" -p TasksMax --value 2>/dev/null)" == "200" ]] \
  && ok "new student has the SSH process limit" || bad "new student has no SSH process limit"
# Captured first rather than piped into grep: crontab exits 1 when it refuses, and with pipefail
# that failure would count against the check even though the refusal is what we want.
CRON_OUT="$(su - smoketest_a -s /bin/bash -c 'crontab -l' 2>&1)"
if ! command -v crontab >/dev/null; then
  ok "students cannot use cron (cron is not installed)"
elif [[ "$CRON_OUT" == *"not allowed"* ]]; then
  ok "students cannot use cron"
else
  bad "students can use cron (crontab said: ${CRON_OUT//$'\n'/ })"
fi
FPM_LIMIT="$(awk '/Max open files/{ print $4 }' "/proc/$(cat /run/php/php8.3-fpm.pid 2>/dev/null)/limits" 2>/dev/null)"
[[ "${FPM_LIMIT:-0}" =~ ^[0-9]+$ ]] && (( FPM_LIMIT >= 65536 )) \
  && ok "PHP can keep enough files open for 800+ student pools" \
  || bad "PHP's open-file limit is ${FPM_LIMIT:-unknown} (needs 65536; restart php8.3-fpm)"
[[ "$(sshd -T 2>/dev/null | awk '$1 == "maxstartups" { print $2 }')" == "1000:30:1500" ]] \
  && ok "sshd accepts a whole lab logging in at once" \
  || bad "sshd MaxStartups is not 1000:30:1500, so mass logins get dropped"
grep -Eq "^port = ([0-9]+,)*${SSH_PORT}(,[0-9]+)*$" /etc/fail2ban/jail.d/5cs045-sshd.conf 2>/dev/null \
  && ok "fail2ban blocks password guessing on SSH port ${SSH_PORT}" \
  || bad "fail2ban does not guard SSH port ${SSH_PORT} (run setup/update-server.sh)"
[[ -f /etc/dbus-1/system.d/5cs045-limits.conf ]] \
  && ok "the system bus has room for a whole class logging in at once" \
  || bad "/etc/dbus-1/system.d/5cs045-limits.conf is missing, so mass logins lose their limits"
[[ " $(id -nG smoketest_a) " == *" 5cs045-students "* ]] && [[ -f /etc/security/limits.d/5cs045-students.conf ]] \
  && ok "new student has the backup process limit" \
  || bad "new student is not in 5cs045-students, or /etc/security/limits.d/5cs045-students.conf is missing"
[[ "$(systemctl is-enabled "user@${UID_A}.service" 2>/dev/null || true)" == "masked" ]] \
  && ok "new student gets no per-user systemd manager (keeps mass logins fast)" \
  || bad "user@${UID_A}.service is not masked, so every login starts a systemd manager"
grep -q check-logind.sh /etc/cron.d/5cs045 2>/dev/null && timeout 20 loginctl list-sessions --no-legend >/dev/null 2>&1 \
  && ok "the login service answers, and its watchdog is scheduled" \
  || bad "logind is not answering, or check-logind.sh is not in /etc/cron.d/5cs045"
[[ -f /etc/cron.d/5cs045 ]] && "$DEPLOY_ROOT/bin/enforce-limits.sh" \
  && ok "the limits job is scheduled and runs cleanly" || bad "the limits job is missing or failed"

echo ""
echo "=== public registration and phpMyAdmin ==="
check_code "$BASE_URL/" "200" "registration page is public at the site root"
check_code "$BASE_URL/register.php" "301" "old /register.php URL redirects to the new site root"
check_code "$BASE_URL/phpmyadmin/" "200" "phpMyAdmin login page loads directly (no Basic Auth prompt)"
# Login details (emails, the panel, add-student.sh) give the websites' name: a private IP means
# nothing off campus, and student websites only answer on their name anyway.
SITE_HOST=""
[[ "$OUT_A" =~ Workshops:\ +https://([^/]+)/ ]] && SITE_HOST="${BASH_REMATCH[1]}"
[[ -n "$SITE_HOST" && ! "$SITE_HOST" =~ ^[0-9.]+(:[0-9]+)?$ && "$SITE_HOST" != \[* ]] \
  && ok "login details give the websites as ${SITE_HOST}, not an IP address" \
  || bad "login details give the websites as '${SITE_HOST}' instead of their name"
# name+1@ reaches the same inbox as name@, so sign-up must refuse it, or one student could make as
# many accounts as they like. The address is refused before anything is created or emailed.
DOMAIN="$(php -r '$c = @include "/etc/5cs045/smtp_config.php"; echo (string) ($c["allowed_email_domain"] ?? "");' 2>/dev/null)"
JAR="$(mktemp)"
TOKEN="$("${CURL[@]}" -c "$JAR" -b "$JAR" "$BASE_URL/" 2>/dev/null | sed -n '/name="csrf_token"/{n;s/.*value="\([0-9a-f]*\)".*/\1/p;q}')"
"${CURL[@]}" -c "$JAR" -b "$JAR" -o /dev/null --data-urlencode "csrf_token=${TOKEN}" \
  --data-urlencode "full_name=Smoke Test Plus" \
  --data-urlencode "email=smoketest.plus+1@${DOMAIN:-heraldcollege.edu.np}" "$BASE_URL/register_handler.php" 2>/dev/null
PAGE="$("${CURL[@]}" -c "$JAR" -b "$JAR" "$BASE_URL/" 2>/dev/null)"
rm -f "$JAR"
[[ "$PAGE" == *"with nothing added to it"* ]] \
  && ok "sign-up refuses name+1@ addresses, which reach the same inbox as name@" \
  || bad "sign-up accepted a name+1@ address, so one student can register again and again"
# Sign-up only emails a link, and the account is made when the student clicks Create my account on
# the page it opens. These checks save a link for a made-up address themselves, so nothing is emailed.
check_code "$BASE_URL/confirm_handler.php" "303" "the create-account step is on the sign-up site"
LINK_DIR="/var/lib/5cs045-signup-links"
[[ "$(stat -c %U:%a "$LINK_DIR" 2>/dev/null)" == "www-data:700" ]] \
  && ok "sign-up links are stored where only the web server can read them" \
  || bad "${LINK_DIR} is missing or readable by others (run setup/update-server.sh)"
LINK_TOKEN="$(openssl rand -hex 32)"
LINK_FILE="${LINK_DIR}/$(printf '%s' "$LINK_TOKEN" | sha256sum | cut -d' ' -f1)"
save_link() { printf '{"email":"smoketest.link@%s","username":"smoketest_link","expires":%d}' "${DOMAIN:-heraldcollege.edu.np}" "$(( $(date +%s) + $1 ))" > "$LINK_FILE"; chown www-data:www-data "$LINK_FILE"; chmod 600 "$LINK_FILE"; }
save_link 600
PAGE="$("${CURL[@]}" "$BASE_URL/?confirm=${LINK_TOKEN}" 2>/dev/null)"
[[ "$PAGE" == *"Create my account"* && "$PAGE" == *smoketest_link* ]] && ! id smoketest_link >/dev/null 2>&1 \
  && ok "opening a sign-up link asks first and creates nothing by itself" \
  || bad "a sign-up link did not show the Create my account button, or made the account just by being opened"
save_link -60
PAGE="$("${CURL[@]}" "$BASE_URL/?confirm=${LINK_TOKEN}" 2>/dev/null)"
[[ "$PAGE" == *"This link has expired"* && "$PAGE" != *"Create my account"* ]] \
  && ok "an expired sign-up link is refused" || bad "an expired sign-up link still offers to create the account"
rm -f "$LINK_FILE"
PAGE="$("${CURL[@]}" "$BASE_URL/?confirm=$(openssl rand -hex 32)" 2>/dev/null)"
[[ "$PAGE" == *"This link is not valid"* ]] \
  && ok "a made-up sign-up link is refused" || bad "a made-up sign-up link was not refused"

echo ""
echo "=== student websites kept apart from everything else ==="
check_code "$STUDENT_URL/" "404" "${STUDENT_HOST} does not show the sign-up page"
check_code "$STUDENT_URL/phpmyadmin/" "404" "${STUDENT_HOST} does not serve phpMyAdmin"
[[ "$("${CURL[@]}" -o /dev/null -w '%{http_code} %{redirect_url}' "$BASE_URL/~smoketest_a/" 2>/dev/null)" == "301 ${STUDENT_URL}/~smoketest_a/" ]] \
  && ok "student pages asked for on the main name are sent to ${STUDENT_HOST}" \
  || bad "student pages are served on the main name (they must only be on ${STUDENT_HOST})"
"${CURL[@]}" -o /dev/null "${STUDENT_URL}:8443/login" 2>/dev/null \
  && bad "the admin panel answers on ${STUDENT_HOST}:8443" \
  || ok "the admin panel does not answer on ${STUDENT_HOST}"

echo ""
echo "=== admin panel ==="
check_code "https://127.0.0.1:8443/login" "200" "admin panel sign-in page loads on port 8443"
# 127.0.0.2 is the server too, but it is not on the allowed list, so it stands in for a student's computer
CODE="$(curl -k -s -o /dev/null -w '%{http_code}' --interface 127.0.0.2 https://127.0.0.1:8443/login 2>/dev/null)"
[[ "$CODE" == "403" ]] && ok "computers not on the allowed list get 403 from the admin panel" \
  || bad "a computer that is not on the allowed list got HTTP $CODE from the admin panel (expected 403)"
ANSWER="$(echo '{"action":"students","ip":"127.0.0.1","token":"'"$(printf '0%.0s' {1..64})"'"}' | "$DEPLOY_ROOT/bin/admin-action" 2>/dev/null)"
[[ "$ANSWER" == *SESSION_EXPIRED* ]] && ok "the panel's server tools refuse requests without a signed-in admin" \
  || bad "admin-action answered a request without a valid sign-in: ${ANSWER:0:80}"
su -s /bin/bash www-data -c "sudo -n $DEPLOY_ROOT/bin/admin-action </dev/null" >/dev/null 2>&1 \
  && bad "www-data (the public website) can run the panel's server tools" \
  || ok "the public website cannot run the panel's server tools"
# A role-granted non-student account can use the panel but must NOT have sudo.
SMOKE_PANEL_PW="$(openssl rand -base64 12)"
useradd -m -s /bin/bash smoketest_panel 2>/dev/null
echo "smoketest_panel:${SMOKE_PANEL_PW}" | chpasswd
printf 'smoketest_panel\n' >> /var/lib/5cs045-admin-auth/admin-users
LOGIN="$(echo '{"action":"login","ip":"127.0.0.1","args":{"username":"smoketest_panel","password":"'${SMOKE_PANEL_PW}'"}}' | "$DEPLOY_ROOT/bin/admin-action" 2>/dev/null)"
[[ "$LOGIN" == *'"token"'* && "$LOGIN" == *'"role":"admin"'* ]]   && ok "an explicitly granted non-student account can sign in to the panel as admin"   || bad "an explicitly granted non-student account could not sign in as admin: ${LOGIN:0:120}"
su -s /bin/bash smoketest_panel -c 'sudo -n true' >/dev/null 2>&1   && bad "a panel admin account has sudo (it must not)"   || ok "a panel admin account has no sudo on the server"
printf '' > /var/lib/5cs045-admin-auth/admin-users
userdel -r smoketest_panel >/dev/null 2>&1
rm -f /var/lib/5cs045-admin-auth/fails-user-* /var/lib/5cs045-admin-auth/fails-ip-*
echo ""
echo "=== managed non-student account checks ==="
CREATE_INPUT='{"action":"create-panel-account","ip":"127.0.0.1","token":"'"$(printf '0%.0s' {1..64})"'","args":{}}'
[[ "$("$DEPLOY_ROOT/bin/admin-action" <<< "$CREATE_INPUT" 2>/dev/null)" == *"SESSION_EXPIRED"* ]]   && ok "managed-account creation requires a signed-in session"   || bad "managed-account creation accepted an unsigned request"

echo ""
echo "=== cleaning up test accounts ==="
"$DEPLOY_ROOT/bin/remove-student.sh" -u smoketest_a >/dev/null 2>&1 || true
"$DEPLOY_ROOT/bin/remove-student.sh" -u smoketest_b >/dev/null 2>&1 || true
# Only exist if the sign-up checks above failed and made an account
for leftover in smoketest_plus_1 smoketest_link; do
  id "$leftover" >/dev/null 2>&1 && { "$DEPLOY_ROOT/bin/remove-student.sh" -u "$leftover" >/dev/null 2>&1 || true; }
done

echo ""
echo "============================================"
echo " ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && echo " Looks safe to provision real students." \
                     || echo " DO NOT provision real students until every FAIL above is fixed."
echo "============================================"
exit "$FAIL"
