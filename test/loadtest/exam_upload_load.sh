#!/usr/bin/env bash
set -u
set -o pipefail

PREFIX="${PREFIX:-loadtest_}"
FILE_SIZE_MB="${FILE_SIZE_MB:-30}"
DEADLINE="${DEADLINE:-60}"
ASSESSMENT_DIR="${ASSESSMENT_DIR:-assessment}"
KEEP_FILES="${KEEP_FILES:-0}"
COUNT="${1:-0}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
WORK_DIR="/tmp/5cs045-exam-${RUN_ID}"
RESULTS="exam-upload-results-${RUN_ID}.csv"
EXPECTED_BYTES=$((FILE_SIZE_MB * 1024 * 1024))
PAYLOAD="${WORK_DIR}/payload.bin"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: run as root (sudo)."
    exit 1
fi
if ! command -v runuser >/dev/null 2>&1; then
    echo "ERROR: runuser is required."
    exit 1
fi
if ! command -v timeout >/dev/null 2>&1; then
    echo "ERROR: timeout is required."
    exit 1
fi
if ! [[ "${FILE_SIZE_MB}" =~ ^[0-9]+$ ]] || [[ "${FILE_SIZE_MB}" -lt 1 ]]; then
    echo "ERROR: FILE_SIZE_MB must be a positive integer."
    exit 1
fi
if ! [[ "${DEADLINE}" =~ ^[0-9]+$ ]] || [[ "${DEADLINE}" -lt 1 ]]; then
    echo "ERROR: DEADLINE must be a positive integer."
    exit 1
fi

mkdir -p "${WORK_DIR}"

cleanup() {
    if [[ "${KEEP_FILES}" -ne 1 ]]; then
        rm -rf "${WORK_DIR}"
    fi
}
trap cleanup EXIT INT TERM

mapfile -t STUDENTS < <(
    getent passwd | awk -F: -v p="${PREFIX}" '
        index($1, p) == 1 {
            s = substr($1, length(p) + 1)
            if (s ~ /^[0-9]+$/) print $1
        }
    ' | sort -V
)

if [[ "${COUNT}" -gt 0 ]] 2>/dev/null; then
    if [[ "${COUNT}" -lt "${#STUDENTS[@]}" ]]; then
        STUDENTS=("${STUDENTS[@]:0:${COUNT}}")
    fi
fi

STUDENT_COUNT="${#STUDENTS[@]}"
if [[ "${STUDENT_COUNT}" -eq 0 ]]; then
    echo "ERROR: no ${PREFIX} accounts found."
    echo "Create them first, for example:"
    echo "  sudo ./test/loadtest/create-accounts.sh 100"
    exit 1
fi

echo "Creating ${FILE_SIZE_MB} MiB payload..."
dd if=/dev/zero of="${PAYLOAD}" bs=1M count="${FILE_SIZE_MB}" status=none
actual="$(stat -c %s "${PAYLOAD}")"
if [[ "${actual}" -ne "${EXPECTED_BYTES}" ]]; then
    echo "ERROR: payload is ${actual} bytes; expected ${EXPECTED_BYTES}."
    exit 1
fi

printf 'username,success,elapsed_seconds,bytes,error\n' > "${RESULTS}"

echo "============================================================"
echo "5CS045 EXAM UPLOAD LOAD TEST"
echo "Students: ${STUDENT_COUNT}"
echo "File:     ${FILE_SIZE_MB} MiB each"
echo "Deadline: ${DEADLINE}s"
echo "Target:   ~/${ASSESSMENT_DIR}/"
echo "============================================================"
echo

run_student() {
    local username="$1"
    local result_file="${WORK_DIR}/${username}.result"
    local home target_dir target_file start end elapsed actual status

    home="$(getent passwd "${username}" | cut -d: -f6)"
    if [[ -z "${home}" || ! -d "${home}" ]]; then
        printf '%s,FAIL,0,0,home directory not found\n' "${username}" > "${result_file}"
        return
    fi

    target_dir="${home}/${ASSESSMENT_DIR}"
    target_file="${target_dir}/exam-load-${RUN_ID}.bin"

    if [[ ! -d "${target_dir}" ]]; then
        if ! install -d -o "${username}" -g "$(id -gn "${username}")" -m 700 "${target_dir}" 2>/dev/null; then
            printf '%s,FAIL,0,0,cannot create assessment directory\n' "${username}" > "${result_file}"
            return
        fi
    fi

    start="$(date +%s%N)"

    timeout "${DEADLINE}" runuser -u "${username}" -- \
        cp "${PAYLOAD}" "${target_file}" >/dev/null 2>&1
    status="$?"

    end="$(date +%s%N)"
    elapsed=$(( (end - start) / 1000000000 ))

    if [[ "${status}" -eq 124 ]]; then
        printf '%s,FAIL,%s,0,upload exceeded %ss\n' "${username}" "${elapsed}" "${DEADLINE}" > "${result_file}"
        rm -f "${target_file}"
        return
    fi

    if [[ "${status}" -ne 0 ]]; then
        printf '%s,FAIL,%s,0,copy failed (quota or permission)\n' "${username}" "${elapsed}" > "${result_file}"
        rm -f "${target_file}"
        return
    fi

    actual="$(stat -c %s "${target_file}" 2>/dev/null || echo 0)"
    if [[ "${actual}" -ne "${EXPECTED_BYTES}" ]]; then
        printf '%s,FAIL,%s,%s,size mismatch\n' "${username}" "${elapsed}" "${actual}" > "${result_file}"
        rm -f "${target_file}"
        return
    fi

    printf '%s,PASS,%s,%s,\n' "${username}" "${elapsed}" "${actual}" > "${result_file}"

    if [[ "${KEEP_FILES}" -ne 1 ]]; then
        rm -f "${target_file}"
    fi
}

PIDS=()
for username in "${STUDENTS[@]}"; do
    echo "Starting ${username}"
    run_student "${username}" &
    PIDS+=("$!")
done

for pid in "${PIDS[@]}"; do
    wait "${pid}"
done

TOTAL=0
PASSED=0
FAILED=0
MIN_TIME=""
MAX_TIME=0
TOTAL_TIME=0
TOTAL_BYTES=0

for username in "${STUDENTS[@]}"; do
    result_file="${WORK_DIR}/${username}.result"
    if [[ -f "${result_file}" ]]; then
        cat "${result_file}" >> "${RESULTS}"
    else
        printf '%s,FAIL,0,0,no result produced\n' "${username}" >> "${RESULTS}"
    fi
done

while IFS=',' read -r username success elapsed bytes error; do
    [[ "${username}" == "username" ]] && continue
    TOTAL=$((TOTAL + 1))
    if [[ "${success}" == "PASS" ]]; then
        PASSED=$((PASSED + 1))
        TOTAL_BYTES=$((TOTAL_BYTES + bytes))
        TOTAL_TIME=$((TOTAL_TIME + elapsed))
        if [[ -z "${MIN_TIME}" || "${elapsed}" -lt "${MIN_TIME}" ]]; then MIN_TIME="${elapsed}"; fi
        if [[ "${elapsed}" -gt "${MAX_TIME}" ]]; then MAX_TIME="${elapsed}"; fi
    else
        FAILED=$((FAILED + 1))
    fi
done < "${RESULTS}"

TOTAL_MB=$((TOTAL_BYTES / 1024 / 1024))
AVG_TIME=0
if [[ "${PASSED}" -gt 0 ]]; then AVG_TIME=$((TOTAL_TIME / PASSED)); fi

echo
echo "============================================================"
echo "RESULTS"
echo "============================================================"
echo "Students:            ${TOTAL}"
echo "Passed:              ${PASSED}"
echo "Failed:              ${FAILED}"
echo "File per student:    ${FILE_SIZE_MB} MiB"
echo "Deadline:            ${DEADLINE}s"
echo "Verified data:       ${TOTAL_MB} MiB"
if [[ "${PASSED}" -gt 0 ]]; then
    echo "Submission time min: ${MIN_TIME}s"
    echo "Submission time avg: ${AVG_TIME}s"
    echo "Submission time max: ${MAX_TIME}s"
fi
echo "Report:              ${RESULTS}"
echo "============================================================"

if [[ "${FAILED}" -gt 0 ]]; then
    exit 1
fi
exit 0
