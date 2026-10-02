```bash
#!/usr/bin/env bash

# 5CS045 Exam Upload Load Test
#
# Scenario:
#   - Each student uploads a 30 MiB file
#   - Upload must complete within 60 seconds
#   - Students run concurrently
#   - Files are uploaded to ~/assessment/
#
# Usage:
#   ./exam_upload_load.sh SERVER_IP accounts.csv
#
# Example:
#   ./exam_upload_load.sh 10.80.0.250 loadtest-accounts.csv
#
# CSV format:
#   username,password

set -u

HOST="${1:-}"
ACCOUNTS_FILE="${2:-}"

SSH_PORT="${SSH_PORT:-50222}"
FILE_SIZE_MB="${FILE_SIZE_MB:-30}"
DEADLINE="${DEADLINE:-60}"
REMOTE_DIR="${REMOTE_DIR:-assessment}"
KEEP_FILES="${KEEP_FILES:-0}"

if [[ -z "$HOST" || -z "$ACCOUNTS_FILE" ]]; then
    echo "Usage: $0 SERVER_IP accounts.csv"
    echo
    echo "Environment variables:"
    echo "  SSH_PORT=50222"
    echo "  FILE_SIZE_MB=30"
    echo "  DEADLINE=60"
    echo "  REMOTE_DIR=assessment"
    echo "  KEEP_FILES=0"
    exit 1
fi

if [[ ! -f "$ACCOUNTS_FILE" ]]; then
    echo "ERROR: Accounts file not found: $ACCOUNTS_FILE"
    exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
    echo "ERROR: ssh is required"
    exit 1
fi

if ! command -v scp >/dev/null 2>&1; then
    echo "ERROR: scp is required"
    exit 1
fi

# ------------------------------------------------------------
# Prepare test payload
# ------------------------------------------------------------

RUN_ID="$(date +%Y%m%d-%H%M%S)"
PAYLOAD="/tmp/exam-upload-${RUN_ID}.bin"
RESULTS="exam-upload-results-${RUN_ID}.csv"

echo "============================================================"
echo "5CS045 EXAM UPLOAD LOAD TEST"
echo "============================================================"
echo "Server:       $HOST"
echo "SSH port:     $SSH_PORT"
echo "File size:    ${FILE_SIZE_MB} MiB"
echo "Deadline:     ${DEADLINE} seconds"
echo "Remote dir:   ~/${REMOTE_DIR}"
echo "============================================================"

echo
echo "Creating ${FILE_SIZE_MB} MiB test file..."

dd if=/dev/zero \
   of="$PAYLOAD" \
   bs=1M \
   count="$FILE_SIZE_MB" \
   status=none

if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to create test file"
    exit 1
fi

echo "Payload: $PAYLOAD"

# ------------------------------------------------------------
# Count students
# ------------------------------------------------------------

STUDENT_COUNT=0

while IFS=',' read -r username password; do
    [[ "$username" == "username" ]] && continue
    [[ -z "$username" ]] && continue
    STUDENT_COUNT=$((STUDENT_COUNT + 1))
done < "$ACCOUNTS_FILE"

if [[ "$STUDENT_COUNT" -eq 0 ]]; then
    echo "ERROR: No students found in $ACCOUNTS_FILE"
    rm -f "$PAYLOAD"
    exit 1
fi

echo "Students:     $STUDENT_COUNT"
echo
echo "Starting concurrent uploads..."
echo

# ------------------------------------------------------------
# Result file
# ------------------------------------------------------------

echo "username,success,upload_seconds,bytes,error" > "$RESULTS"

TMP_DIR="/tmp/exam-upload-results-${RUN_ID}"
mkdir -p "$TMP_DIR"

# ------------------------------------------------------------
# Upload function
# ------------------------------------------------------------

upload_student() {
    local index="$1"
    local username="$2"
    local password="$3"

    local start_time
    local end_time
    local elapsed
    local remote_file
    local result_file
    local ssh_opts

    result_file="${TMP_DIR}/${index}.result"
    remote_file="${REMOTE_DIR}/exam-load-${RUN_ID}-${index}.bin"

    # Disable host-key checking for a temporary load test.
    # This avoids interactive prompts.
    ssh_opts=(
        -p "$SSH_PORT"
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o ConnectTimeout=30
        -o BatchMode=no
    )

    start_time="$(date +%s)"

    # sshpass is required for password-based automated SSH.
    if ! command -v sshpass >/dev/null 2>&1; then
        echo "$username,FAIL,,0,sshpass not installed" > "$result_file"
        return
    fi

    # Make sure assessment directory exists.
    sshpass -p "$password" ssh "${ssh_opts[@]}" \
        "$username@$HOST" \
        "mkdir -p '$REMOTE_DIR'" \
        >/dev/null 2>&1

    if [[ $? -ne 0 ]]; then
        echo "$username,FAIL,,0,SSH login/directory creation failed" > "$result_file"
        return
    fi

    # Upload using scp.
    timeout "$DEADLINE" \
        sshpass -p "$password" scp \
        -P "$SSH_PORT" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 \
        "$PAYLOAD" \
        "$username@$HOST:$remote_file" \
        >/dev/null 2>&1

    local upload_status=$?

    end_time="$(date +%s)"
    elapsed=$((end_time - start_time))

    if [[ "$upload_status" -eq 0 && "$elapsed" -le "$DEADLINE" ]]; then

        # Verify remote file size.
        local expected_bytes
        local remote_bytes

        expected_bytes=$((FILE_SIZE_MB * 1024 * 1024))

        remote_bytes="$(
            sshpass -p "$password" ssh "${ssh_opts[@]}" \
                "$username@$HOST" \
                "stat -c %s '$remote_file'" \
                2>/dev/null
        )"

        if [[ "$remote_bytes" == "$expected_bytes" ]]; then
            echo "$username,PASS,$elapsed,$remote_bytes," > "$result_file"

            # Remove only the test file unless KEEP_FILES=1.
            if [[ "$KEEP_FILES" -ne 1 ]]; then
                sshpass -p "$password" ssh "${ssh_opts[@]}" \
                    "$username@$HOST" \
                    "rm -f '$remote_file'" \
                    >/dev/null 2>&1
            fi
        else
            echo "$username,FAIL,$elapsed,$remote_bytes,size mismatch" > "$result_file"
        fi

    elif [[ "$upload_status" -eq 124 ]]; then
        echo "$username,FAIL,$DEADLINE,0,upload exceeded ${DEADLINE}s" > "$result_file"

    else
        echo "$username,FAIL,$elapsed,0,scp upload failed" > "$result_file"
    fi
}

# ------------------------------------------------------------
# Launch all students concurrently
# ------------------------------------------------------------

INDEX=0
PIDS=()

while IFS=',' read -r username password; do

    # Skip CSV header
    if [[ "$username" == "username" ]]; then
        continue
    fi

    # Skip empty rows
    [[ -z "$username" ]] && continue

    INDEX=$((INDEX + 1))

    echo "Starting student $INDEX/$STUDENT_COUNT: $username"

    upload_student "$INDEX" "$username" "$password" &

    PIDS+=("$!")

done < "$ACCOUNTS_FILE"

echo
echo "All $STUDENT_COUNT student uploads started."
echo "Waiting for results..."
echo

# ------------------------------------------------------------
# Wait for all uploads
# ------------------------------------------------------------

for pid in "${PIDS[@]}"; do
    wait "$pid"
done

# ------------------------------------------------------------
# Combine results
# ------------------------------------------------------------

for result in "$TMP_DIR"/*.result; do
    [[ -f "$result" ]] || continue
    cat "$result" >> "$RESULTS"
done

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

TOTAL=0
PASSED=0
FAILED=0
TOTAL_BYTES=0
MAX_TIME=0
MIN_TIME=999999
TOTAL_TIME=0
TIMED_UPLOADS=0

while IFS=',' read -r username success upload_seconds bytes error; do

    [[ "$username" == "username" ]] && continue

    TOTAL=$((TOTAL + 1))

    if [[ "$success" == "PASS" ]]; then
        PASSED=$((PASSED + 1))
        TOTAL_BYTES=$((TOTAL_BYTES + bytes))

        if [[ -n "$upload_seconds" ]]; then
            TOTAL_TIME=$((TOTAL_TIME + upload_seconds))
            TIMED_UPLOADS=$((TIMED_UPLOADS + 1))

            if [[ "$upload_seconds" -gt "$MAX_TIME" ]]; then
                MAX_TIME="$upload_seconds"
            fi

            if [[ "$upload_seconds" -lt "$MIN_TIME" ]]; then
                MIN_TIME="$upload_seconds"
            fi
        fi
    else
        FAILED=$((FAILED + 1))
    fi

done < "$RESULTS"

TOTAL_MB=$((TOTAL_BYTES / 1024 / 1024))

echo
echo "============================================================"
echo "EXAM UPLOAD RESULTS"
echo "============================================================"
echo "Students:           $TOTAL"
echo "Passed:             $PASSED/$TOTAL"
echo "Failed:             $FAILED"
echo "Verified uploaded:  ${TOTAL_MB} MiB"

if [[ "$TIMED_UPLOADS" -gt 0 ]]; then
    AVG_TIME=$((TOTAL_TIME / TIMED_UPLOADS))

    echo "Upload time min:    ${MIN_TIME}s"
    echo "Upload time avg:    ${AVG_TIME}s"
    echo "Upload time max:    ${MAX_TIME}s"
fi

echo
echo "Per-student report: $RESULTS"

if [[ "$FAILED" -gt 0 ]]; then
    echo
    echo "FAILED STUDENTS:"
    awk -F',' '$2 != "PASS" {print "  " $1 " - " $5}' "$RESULTS"
fi

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

rm -rf "$TMP_DIR"
rm -f "$PAYLOAD"

echo
echo "Test completed."

if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
```
