```bash
#!/usr/bin/env bash

# 5CS045 Exam Scenario Load Test
#
# The test accounts are created by create-accounts.sh:
#   loadtest_001, loadtest_002, ...
#
# This script:
#   1. Discovers the load-test accounts directly from the server
#   2. Creates a 30 MiB assessment file for every student
#   3. Writes all students concurrently
#   4. Enforces a 60-second per-student deadline
#   5. Verifies every resulting file size
#   6. Produces a per-student CSV report
#   7. Removes the test files by default
#
# IMPORTANT:
# This is a SERVER-SIDE storage/load test. It does not emulate the
# network path from a student's computer to the server.

set -u

PREFIX="${PREFIX:-loadtest_}"
FILE_SIZE_MB="${FILE_SIZE_MB:-30}"
DEADLINE="${DEADLINE:-60}"
ASSESSMENT_DIR="${ASSESSMENT_DIR:-assessment}"
KEEP_FILES="${KEEP_FILES:-0}"

COUNT="${1:-0}"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
WORK_DIR="/tmp/5cs045-exam-load-${RUN_ID}"
RESULTS="exam-load-results-${RUN_ID}.csv"

EXPECTED_BYTES=$((FILE_SIZE_MB * 1024 * 1024))

# ------------------------------------------------------------
# Checks
# ------------------------------------------------------------

[[ $EUID -eq 0 ]] || {
    echo "ERROR: run this with sudo"
    exit 1
}

if ! [[ "$FILE_SIZE_MB" =~ ^[0-9]+$ ]] || (( FILE_SIZE_MB < 1 )); then
    echo "ERROR: FILE_SIZE_MB must be a positive integer"
    exit 1
fi

if ! [[ "$DEADLINE" =~ ^[0-9]+$ ]] || (( DEADLINE < 1 )); then
    echo "ERROR: DEADLINE must be a positive integer"
    exit 1
fi

mkdir -p "$WORK_DIR"

cleanup() {
    if [[ "$KEEP_FILES" -ne 1 ]]; then
        rm -rf "$WORK_DIR"
    fi
}

trap cleanup EXIT INT TERM

# ------------------------------------------------------------
# Discover test accounts
# ------------------------------------------------------------

mapfile -t STUDENTS < <(
    getent passwd |
    awk -F: -v prefix="$PREFIX" '
        index($1, prefix) == 1 {
            suffix = substr($1, length(prefix) + 1)
            if (suffix ~ /^[0-9]+$/)
                print $1
        }
    ' |
    sort -V
)

if [[ ${#STUDENTS[@]} -eq 0 ]]; then
    echo "ERROR: No ${PREFIX} test accounts found."
    echo
    echo "Create them first, for example:"
    echo
    echo "  sudo ./test/loadtest/create-accounts.sh 100"
    exit 1
fi

if (( COUNT > 0 )); then
    if (( COUNT > ${#STUDENTS[@]} )); then
        COUNT=${#STUDENTS[@]}
    fi

    STUDENTS=( "${STUDENTS[@]:0:COUNT}" )
fi

STUDENT_COUNT=${#STUDENTS[@]}

# ------------------------------------------------------------
# Header
# ------------------------------------------------------------

echo "============================================================"
echo "5CS045 EXAM SCENARIO LOAD TEST"
echo "============================================================"
echo "Student prefix:  $PREFIX"
echo "Students:        $STUDENT_COUNT"
echo "File size:       ${FILE_SIZE_MB} MiB each"
echo "Deadline:        ${DEADLINE} seconds"
echo "Destination:     ~/${ASSESSMENT_DIR}/"
echo "Run ID:          $RUN_ID"
echo "============================================================"
echo

# ------------------------------------------------------------
# Create one common 30 MiB source payload
# ------------------------------------------------------------

PAYLOAD="$WORK_DIR/exam-submission.bin"

echo "Creating ${FILE_SIZE_MB} MiB test submission..."

dd if=/dev/zero \
   of="$PAYLOAD" \
   bs=1M \
   count="$FILE_SIZE_MB" \
   status=none

if [[ $? -ne 0 ]]; then
    echo "ERROR: Could not create payload"
    exit 1
fi

chmod 644 "$PAYLOAD"

ACTUAL_PAYLOAD_SIZE=$(stat -c %s "$PAYLOAD")

if [[ "$ACTUAL_PAYLOAD_SIZE" -ne "$EXPECTED_BYTES" ]]; then
    echo "ERROR: Payload size mismatch"
    echo "Expected: $EXPECTED_BYTES"
    echo "Actual:   $ACTUAL_PAYLOAD_SIZE"
    exit 1
fi

echo "Payload ready: $ACTUAL_PAYLOAD_SIZE bytes"
echo

# ------------------------------------------------------------
# Results
# ------------------------------------------------------------

echo "username,success,elapsed_seconds,bytes,error" > "$RESULTS"

# ------------------------------------------------------------
# Student exam submission
# ------------------------------------------------------------

run_student() {

    local username="$1"
    local result_file="$WORK_DIR/${username}.result"

    local home
    local target_dir
    local target_file

    local start_ns
    local end_ns
    local elapsed_ms
    local elapsed_seconds

    local actual_size
    local status

    home="$(getent passwd "$username" | cut -d: -f6)"

    if [[ -z "$home" || ! -d "$home" ]]; then
        echo "$username,FAIL,0,0,home directory not found" > "$result_file"
        return
    fi

    target_dir="${home}/${ASSESSMENT_DIR}"
    target_file="${target_dir}/exam-load-${RUN_ID}.bin"

    # --------------------------------------------------------
    # Assessment folder
    # --------------------------------------------------------

    if [[ ! -d "$target_dir" ]]; then
        if ! install -d \
            -o "$username" \
            -g "$(id -gn "$username")" \
            -m 700 \
            "$target_dir" 2>/dev/null; then

            echo "$username,FAIL,0,0,cannot create assessment directory" \
                > "$result_file"
            return
        fi
    fi

    # --------------------------------------------------------
    # Start timer
    # --------------------------------------------------------

    start_ns=$(date +%s%N)

    # --------------------------------------------------------
    # Simulate student submission
    #
    # Run as the student so normal filesystem permissions,
    # ownership and user quota are exercised.
    # --------------------------------------------------------

    timeout "${DEADLINE}s" \
        runuser -u "$username" -- \
        dd if="$PAYLOAD" \
           of="$target_file" \
           bs=1M \
           count="$FILE_SIZE_MB" \
           status=none \
        >/dev/null 2>&1

    status=$?

    end_ns=$(date +%s%N)

    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
    elapsed_seconds=$(( elapsed_ms / 1000 ))

    # --------------------------------------------------------
    # Timeout
    # --------------------------------------------------------

    if [[ "$status" -eq 124 ]]; then
        echo "$username,FAIL,$elapsed_seconds,0,upload exceeded ${DEADLINE}s" \
            > "$result_file"

        rm -f "$target_file"
        return
    fi

    # --------------------------------------------------------
    # Write failed
    # --------------------------------------------------------

    if [[ "$status" -ne 0 ]]; then
        echo "$username,FAIL,$elapsed_seconds,0,submission write failed" \
            > "$result_file"

        rm -f "$target_file"
        return
    fi

    # --------------------------------------------------------
    # Verify result
    # --------------------------------------------------------

    actual_size=$(stat -c %s "$target_file" 2>/dev/null || echo 0)

    if [[ "$actual_size" -ne "$EXPECTED_BYTES" ]]; then
        echo "$username,FAIL,$elapsed_seconds,$actual_size,size mismatch" \
            > "$result_file"

        rm -f "$target_file"
        return
    fi

    # --------------------------------------------------------
    # Deadline check
    # --------------------------------------------------------

    if (( elapsed_ms > DEADLINE * 1000 )); then
        echo "$username,FAIL,$elapsed_seconds,$actual_size,deadline exceeded" \
            > "$result_file"

        rm -f "$target_file"
        return
    fi

    # --------------------------------------------------------
    # Success
    # --------------------------------------------------------

    echo "$username,PASS,$elapsed_seconds,$actual_size," \
        > "$result_file"

    if [[ "$KEEP_FILES" -ne 1 ]]; then
        rm -f "$target_file"
    fi
}

# ------------------------------------------------------------
# Launch all students concurrently
# ------------------------------------------------------------

echo "Starting ${STUDENT_COUNT} concurrent exam submissions..."
echo

PIDS=()

for username in "${STUDENTS[@]}"; do

    printf "  starting %-20s\n" "$username"

    run_student "$username" &

    PIDS+=( "$!" )
done

echo
echo "All submissions started."
echo "Waiting for completion..."
echo

# ------------------------------------------------------------
# Wait for all processes
# ------------------------------------------------------------

for pid in "${PIDS[@]}"; do
    wait "$pid"
done

# ------------------------------------------------------------
# Combine results
# ------------------------------------------------------------

for username in "${STUDENTS[@]}"; do
    result_file="$WORK_DIR/${username}.result"

    if [[ -f "$result_file" ]]; then
        cat "$result_file" >> "$RESULTS"
    else
        echo "$username,FAIL,0,0,no result produced" >> "$RESULTS"
    fi
done

# ------------------------------------------------------------
# Statistics
# ------------------------------------------------------------

TOTAL=0
PASSED=0
FAILED=0

MIN_TIME=""
MAX_TIME=0
TOTAL_TIME=0
TOTAL_BYTES=0

while IFS=',' read -r username success elapsed_seconds bytes error; do

    [[ "$username" == "username" ]] && continue

    TOTAL=$((TOTAL + 1))

    if [[ "$success" == "PASS" ]]; then

        PASSED=$((PASSED + 1))
        TOTAL_BYTES=$((TOTAL_BYTES + bytes))
        TOTAL_TIME=$((TOTAL_TIME + elapsed_seconds))

        if [[ -z "$MIN_TIME" || "$elapsed_seconds" -lt "$MIN_TIME" ]]; then
            MIN_TIME="$elapsed_seconds"
        fi

        if [[ "$elapsed_seconds" -gt "$MAX_TIME" ]]; then
            MAX_TIME="$elapsed_seconds"
        fi

    else
        FAILED=$((FAILED + 1))
    fi

done < "$RESULTS"

TOTAL_MB=$((TOTAL_BYTES / 1024 / 1024))

if (( PASSED > 0 )); then
    AVG_TIME=$((TOTAL_TIME / PASSED))
else
    AVG_TIME=0
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

echo
echo "============================================================"
echo "EXAM SCENARIO RESULTS"
echo "============================================================"
echo "Students:            $TOTAL"
echo "Passed:              $PASSED"
echo "Failed:              $FAILED"
echo "File per student:    ${FILE_SIZE_MB} MiB"
echo "Required deadline:   ${DEADLINE} seconds"
echo "Verified data:       ${TOTAL_MB} MiB"

if (( PASSED > 0 )); then
    echo "Submission time min: ${MIN_TIME}s"
    echo "Submission time avg: ${AVG_TIME}s"
    echo "Submission time max: ${MAX_TIME}s"
fi

echo
echo "Per-student report:  $RESULTS"

if (( FAILED > 0 )); then
    echo
    echo "FAILED STUDENTS:"
    awk -F',' '$2 != "PASS" {
        printf "  %-20s %s\n", $1, $5
    }' "$RESULTS"
fi

echo "============================================================"

if (( FAILED > 0 )); then
    exit 1
fi

exit 0
```
