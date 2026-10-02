#!/usr/bin/env python3
"""
Exam upload load test for the 5CS045 Student Server.

Each account logs in over SSH/SFTP and uploads one file (30 MiB by default)
to its own ~/assessment/ directory. The upload itself must finish within
60 seconds. The script verifies the remote file size and writes a CSV report.

Run from a separate test computer, not from the server.
"""
import argparse
import asyncio
import csv
import os
import secrets
import sys
import time
from collections import Counter

try:
    import asyncssh
except ImportError:
    sys.exit("Missing dependency. Install it with: python3 -m pip install asyncssh")


def load_accounts(path, limit):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    accounts = [(r["username"].strip(), r["password"]) for r in rows
                if r.get("username") and r.get("password")]
    if not accounts:
        raise SystemExit("No valid username,password rows found in accounts CSV.")
    return accounts[:limit] if limit else accounts


async def upload_one(index, username, password, args, payload, run_id, start_at):
    # Ramp controls when each student begins. Upload duration is measured
    # separately from login, against the 60-second upload deadline.
    delay = index * args.ramp / max(args.users - 1, 1)
    await asyncio.sleep(max(0, start_at + delay - time.monotonic()))

    result = {
        "username": username, "success": False, "login_seconds": "",
        "upload_seconds": "", "bytes": 0, "error": "",
    }
    conn = None
    remote_path = f"{args.remote_dir.rstrip('/')}/exam-load-{run_id}-{index:04d}.bin"

    try:
        login_start = time.perf_counter()
        conn = await asyncio.wait_for(
            asyncssh.connect(
                args.host,
                port=args.port,
                username=username,
                password=password,
                known_hosts=None,
                client_keys=None,
                agent_path=None,
                preferred_auth="password",
                login_timeout=args.login_timeout,
            ),
            timeout=args.login_timeout,
        )
        result["login_seconds"] = round(time.perf_counter() - login_start, 3)

        upload_start = time.perf_counter()

        async def do_upload():
            async with conn.start_sftp_client() as sftp:
                await sftp.makedirs(args.remote_dir, exist_ok=True)
                async with sftp.open(remote_path, "wb") as remote_file:
                    await remote_file.write(payload)
                stat = await sftp.stat(remote_path)
                if stat.size != len(payload):
                    raise RuntimeError(
                        f"size mismatch: remote={stat.size}, expected={len(payload)}"
                    )

        await asyncio.wait_for(do_upload(), timeout=args.deadline)
        elapsed = time.perf_counter() - upload_start
        result["upload_seconds"] = round(elapsed, 3)
        result["bytes"] = len(payload)
        result["success"] = elapsed <= args.deadline

        if not result["success"]:
            result["error"] = f"upload exceeded {args.deadline}s"

        # Remove only this test's uniquely named file; assessment work is untouched.
        if not args.keep_files:
            async with conn.start_sftp_client() as sftp:
                await sftp.remove(remote_path)

    except asyncio.TimeoutError:
        result["upload_seconds"] = round(time.perf_counter() - upload_start, 3) \
            if "upload_start" in locals() else ""
        result["error"] = f"timed out (upload deadline {args.deadline}s)"
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {str(exc)[:200]}"
    finally:
        if conn is not None:
            conn.close()
            try:
                await conn.wait_closed()
            except Exception:
                pass

    return result


async def run(args, accounts):
    args.users = len(accounts)
    payload = secrets.token_bytes(args.file_size_mb * 1024 * 1024)
    run_id = time.strftime("%Y%m%d-%H%M%S")
    start_at = time.monotonic() + 2

    print(
        f"Exam upload test: {args.users} students | "
        f"{args.file_size_mb} MiB each | {args.deadline}s upload deadline | "
        f"ramp={args.ramp}s | target=~/{args.remote_dir}"
    )
    tasks = [
        upload_one(i, user, password, args, payload, run_id, start_at)
        for i, (user, password) in enumerate(accounts)
    ]
    results = await asyncio.gather(*tasks)
    return results


def main():
    parser = argparse.ArgumentParser(description="5CS045 exam upload load test")
    parser.add_argument("host", help="Server IP or hostname")
    parser.add_argument("accounts", help="CSV with username,password columns")
    parser.add_argument("--users", type=int, default=0,
                        help="Number of accounts to use (0 = all CSV accounts)")
    parser.add_argument("--file-size-mb", type=int, default=30,
                        help="Upload size per student in MiB (default: 30)")
    parser.add_argument("--deadline", type=float, default=60,
                        help="Maximum seconds for each upload (default: 60)")
    parser.add_argument("--ramp", type=float, default=0,
                        help="Spread student upload starts over N seconds (0 = all together)")
    parser.add_argument("--remote-dir", default="assessment",
                        help="Remote directory relative to each student's home (default: assessment)")
    parser.add_argument("--port", type=int, default=50222,
                        help="SSH port (5CS045 default: 50222)")
    parser.add_argument("--login-timeout", type=float, default=30,
                        help="SSH login timeout in seconds")
    parser.add_argument("--keep-files", action="store_true",
                        help="Keep uploaded test files; default removes only this run's files")
    args = parser.parse_args()

    if args.file_size_mb < 1 or args.deadline <= 0 or args.ramp < 0:
        parser.error("file size and deadline must be positive; ramp cannot be negative")
    if args.remote_dir.startswith("/") or ".." in args.remote_dir.split("/"):
        parser.error("--remote-dir must be a safe path relative to the student's home")

    accounts = load_accounts(args.accounts, args.users)
    results = asyncio.run(run(args, accounts))

    succeeded = [r for r in results if r["success"]]
    failed = [r for r in results if not r["success"]]
    durations = [r["upload_seconds"] for r in succeeded]
    total_mb = sum(r["bytes"] for r in succeeded) / (1024 * 1024)

    print("\n=============== EXAM UPLOAD RESULTS ===============")
    print(f"Students:          {len(results)}")
    print(f"Passed:            {len(succeeded)}/{len(results)}")
    print(f"Failed:            {len(failed)}")
    print(f"Verified uploaded: {total_mb:.1f} MiB")
    if durations:
        print(f"Upload time min:   {min(durations):.2f}s")
        print(f"Upload time mean:  {sum(durations) / len(durations):.2f}s")
        print(f"Upload time max:   {max(durations):.2f}s")
    if failed:
        print("\nFailures:")
        for reason, count in Counter(r["error"] for r in failed).most_common():
            print(f"  {count:4d}  {reason}")

    report = f"exam-upload-results-{time.strftime('%Y%m%d-%H%M%S')}.csv"
    with open(report, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f, fieldnames=["username", "success", "login_seconds",
                           "upload_seconds", "bytes", "error"]
        )
        writer.writeheader()
        writer.writerows(results)
    print(f"\nPer-student report: {report}")
    sys.exit(0 if not failed else 1)


if __name__ == "__main__":
    main()
