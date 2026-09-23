#!/usr/bin/env python3
"""SSH and SCP load test for the 5CS045 server.

Run it from another machine on the campus network, not from the server itself (the
test's own CPU use would be counted as the server's). It logs in as many throwaway
students at the same time and reports how many got in, how long it took, and why the
rest failed.

  python3 -m pip install asyncssh
  python3 ssh_load.py 10.80.0.250 loadtest-accounts.csv --scenario login --users 800

Scenarios:
  login   Everyone logs in and keeps a terminal open for --hold seconds, running a
          command every 10 seconds, like a student with a shell open during a lab.
  upload  Everyone uploads a --file-size MB file (and --project folder, if given) and
          disconnects. Modern scp uses the same SFTP protocol, so this is what scp does.
  lab     Both: log in, keep a terminal open, upload the project and file, check the
          uploaded PHP with php -l, and stay connected until --hold is over.

The accounts file comes from test/loadtest/create-accounts.sh (username,password).
"""
import argparse
import asyncio
import csv
import multiprocessing as mp
import os
import queue
import statistics
import sys
import time
from collections import Counter

try:
    import asyncssh
except ImportError:
    sys.exit("asyncssh is not installed. Run: python3 -m pip install asyncssh")

REMOTE_DIR = "workshops/loadtest"
TICK_EVERY = 10  # seconds between commands in an open terminal


def raise_open_file_limit():
    """Each connection needs a file descriptor. Raise the soft limit as far as allowed."""
    try:
        import resource
    except ImportError:  # Windows
        return
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    for target in (hard, 65536, 24576, 10240, 4096):
        if target == resource.RLIM_INFINITY or target <= soft:
            continue
        try:
            resource.setrlimit(resource.RLIMIT_NOFILE, (target, hard))
            return
        except (ValueError, OSError):
            continue


def classify(stage, exc, timeout):
    """Turns an exception into a short, groupable reason."""
    if isinstance(exc, asyncio.TimeoutError):
        return f"{stage}: no answer within {timeout}s (server overloaded or dropping connections)"
    if isinstance(exc, asyncssh.PermissionDenied):
        return f"{stage}: password refused (wrong password in the CSV, or the account is missing)"
    if isinstance(exc, ConnectionRefusedError):
        return f"{stage}: connection refused (sshd not listening, or this machine is banned by fail2ban)"
    if isinstance(exc, (ConnectionResetError, asyncssh.ConnectionLost, BrokenPipeError)):
        return f"{stage}: connection dropped by the server (usually MaxStartups, or the server is out of resources)"
    if isinstance(exc, asyncssh.ChannelOpenError):
        return f"{stage}: server refused to open a session ({exc.reason})"
    if isinstance(exc, asyncssh.SFTPError):
        return f"{stage}: SFTP error: {exc.reason}"
    if isinstance(exc, asyncssh.DisconnectError):
        return f"{stage}: server disconnected: {exc.reason}"
    if isinstance(exc, asyncssh.ProcessError):
        return f"{stage}: command failed with exit status {exc.exit_status}"
    msg = str(exc).strip().splitlines()[0][:120] if str(exc).strip() else ""
    return f"{stage}: {type(exc).__name__} {msg}".strip()


def percentile(values, pct):
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round(pct / 100 * (len(ordered) - 1))))
    return ordered[index]


class Shell:
    """An interactive terminal kept open like a student's SSH window."""

    def __init__(self, process, timeout):
        self.process = process
        self.timeout = timeout
        self.counter = 0

    async def run(self, command):
        # The marker is built by the shell, so the typed command (echoed back by the
        # terminal) never matches it. Only real output does.
        self.counter += 1
        marker = f"done{self.counter + 1000}"
        self.process.stdin.write(f"{command}; echo done$(({self.counter}+1000))\n")
        await asyncio.wait_for(self.process.stdout.readuntil(marker), self.timeout)

    async def close(self):
        try:
            self.process.stdin.write("exit\n")
            await asyncio.wait_for(self.process.wait(), 5)
        except Exception:
            pass


async def hold_open(shell, until):
    while time.time() < until:
        await asyncio.sleep(min(TICK_EVERY, max(0.0, until - time.time())))
        if time.time() < until:
            await shell.run("ls -la ~ > /dev/null")


async def upload(conn, args, payload, rec):
    t0 = time.perf_counter()
    async with conn.start_sftp_client() as sftp:
        await sftp.makedirs(REMOTE_DIR, exist_ok=True)
        if payload:
            remote = f"{REMOTE_DIR}/upload.bin"
            async with sftp.open(remote, "wb") as f:
                await f.write(payload)
            size = (await sftp.stat(remote)).size
            if size != len(payload):
                raise asyncssh.SFTPFailure(f"uploaded {size} of {len(payload)} bytes")
            rec["bytes"] += len(payload)
        if args.project:
            await sftp.put(args.project, REMOTE_DIR, recurse=True)
            rec["bytes"] += rec["project_bytes"]
        # A tiny page, so the upload can also be checked in a browser
        async with sftp.open(f"{REMOTE_DIR}/index.php", "w") as f:
            await f.write("<?php echo 'load test ok';\n")
    rec["upload_s"] = time.perf_counter() - t0


async def one_student(index, user, password, args, start_at, payload, shared):
    rec = {"user": user, "ok": False, "error": "", "login_s": None, "upload_s": None,
           "total_s": None, "bytes": 0, "project_bytes": shared["project_bytes"]}
    delay = (index * args.ramp / args.users) if args.users > 1 else 0
    await asyncio.sleep(max(0.0, start_at + delay - time.time()))
    started = time.perf_counter()
    stage = "login"
    counters = shared["counters"]
    with counters["started"].get_lock():
        counters["started"].value += 1
    try:
        conn = await asyncio.wait_for(
            asyncssh.connect(args.host, port=args.port, username=user, password=password,
                             known_hosts=None, client_keys=None, agent_path=None,
                             preferred_auth="password", login_timeout=args.timeout),
            args.timeout)
        rec["login_s"] = time.perf_counter() - started
        with counters["active"].get_lock():
            counters["active"].value += 1
        try:
            until = time.time() + args.hold
            async with conn:
                shell = None
                if args.scenario in ("login", "lab"):
                    stage = "open terminal"
                    process = await asyncio.wait_for(
                        conn.create_process(term_type="xterm", encoding="utf-8"), args.timeout)
                    shell = Shell(process, args.timeout)
                    stage = "command"
                    await shell.run("cd ~")
                if args.scenario in ("upload", "lab"):
                    stage = "upload"
                    await upload(conn, args, payload, rec)
                if args.scenario == "lab":
                    stage = "command"
                    await shell.run(f"php -l ~/{REMOTE_DIR}/index.php > /dev/null && du -sh ~ > /dev/null")
                if shell:
                    stage = "command"
                    await hold_open(shell, until)
                    await shell.close()
        finally:
            with counters["active"].get_lock():
                counters["active"].value -= 1
        rec["ok"] = True
    except Exception as exc:  # noqa: BLE001 - every failure is reported, none should stop the run
        rec["error"] = classify(stage, exc, args.timeout)
    rec["total_s"] = time.perf_counter() - started
    key = "succeeded" if rec["ok"] else "failed"
    with counters[key].get_lock():
        counters[key].value += 1
    return rec


async def worker_main(assigned, args, start_at, shared):
    payload = os.urandom(int(args.file_size * 1024 * 1024)) if args.scenario in ("upload", "lab") and args.file_size > 0 else b""
    tasks = [one_student(i, u, p, args, start_at, payload, shared) for i, u, p in assigned]
    return await asyncio.gather(*tasks)


def worker(assigned, args, start_at, counters, project_bytes, results):
    raise_open_file_limit()
    shared = {"counters": counters, "project_bytes": project_bytes}
    results.put(asyncio.run(worker_main(assigned, args, start_at, shared)))


def folder_size(path):
    total = 0
    for root, _dirs, files in os.walk(path):
        for name in files:
            total += os.path.getsize(os.path.join(root, name))
    return total


def fmt(seconds):
    return "-" if seconds is None else f"{seconds:.2f}s"


def main():
    parser = argparse.ArgumentParser(description="SSH/SCP load test for the 5CS045 server.",
                                     formatter_class=argparse.RawDescriptionHelpFormatter,
                                     epilog=__doc__.split("Scenarios:")[1])
    parser.add_argument("host", help="server address, for example 10.80.0.250")
    parser.add_argument("accounts", help="CSV from create-accounts.sh (username,password)")
    parser.add_argument("--scenario", choices=["login", "upload", "lab"], default="login")
    parser.add_argument("--users", type=int, help="how many students (default: everyone in the CSV)")
    parser.add_argument("--ramp", type=float, default=0, help="spread the logins over this many seconds (0 = all at once)")
    parser.add_argument("--hold", type=float, default=60, help="seconds to keep each terminal open (login and lab)")
    parser.add_argument("--file-size", type=float, default=5, help="MB each student uploads (upload and lab, 0 = none)")
    parser.add_argument("--project", help="a local folder each student uploads too, for example demo-student-portfolio-blade")
    parser.add_argument("--timeout", type=float, default=60, help="seconds before a login or command counts as failed")
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--workers", type=int, default=max(1, min(8, os.cpu_count() or 1)),
                        help="client processes (default: CPU cores, up to 8), so this machine is not the bottleneck")
    args = parser.parse_args()

    with open(args.accounts, newline="") as f:
        accounts = [(row["username"], row["password"]) for row in csv.DictReader(f)]
    if not accounts:
        sys.exit("The accounts file is empty.")
    args.users = min(args.users or len(accounts), len(accounts))
    accounts = accounts[: args.users]
    if args.project and not os.path.isdir(args.project):
        sys.exit(f"--project {args.project} is not a folder")
    project_bytes = folder_size(args.project) if args.project else 0

    workers = min(args.workers, args.users)
    assigned = [[] for _ in range(workers)]
    for i, (user, password) in enumerate(accounts):
        assigned[i % workers].append((i, user, password))

    counters = {name: mp.Value("i", 0) for name in ("started", "active", "succeeded", "failed")}
    results = mp.Queue()
    start_at = time.time() + 3
    print(f"{args.scenario} test: {args.users} students on {args.host}, "
          f"{'all at once' if args.ramp == 0 else f'spread over {args.ramp:g}s'}, "
          f"{workers} client processes")
    procs = [mp.Process(target=worker, args=(a, args, start_at, counters, project_bytes, results)) for a in assigned]
    for p in procs:
        p.start()

    records, peak_active, batches, last_print = [], 0, 0, 0.0
    while batches < workers:
        try:
            records.extend(results.get(timeout=1))
            batches += 1
        except queue.Empty:
            pass
        peak_active = max(peak_active, counters["active"].value)
        if time.time() >= start_at and time.time() - last_print >= 5:
            last_print = time.time()
            print(f"  {time.time() - start_at:6.0f}s  started {counters['started'].value:4d}  "
                  f"logged in now {counters['active'].value:4d}  succeeded {counters['succeeded'].value:4d}  "
                  f"failed {counters['failed'].value:4d}", flush=True)
    for p in procs:
        p.join()
    wall = time.time() - start_at

    ok = [r for r in records if r["ok"]]
    failed = [r for r in records if not r["ok"]]
    logins = [r["login_s"] for r in records if r["login_s"] is not None]
    uploads = [r["upload_s"] for r in ok if r["upload_s"] is not None]

    print("\n================ RESULT ================")
    print(f"Scenario:        {args.scenario}, {args.users} students, "
          f"{'all at once' if args.ramp == 0 else f'over {args.ramp:g}s'}"
          + (f", terminals held {args.hold:g}s" if args.scenario != "upload" else ""))
    print(f"Succeeded:       {len(ok)}/{len(records)} ({100 * len(ok) / len(records):.1f}%)")
    print(f"Peak logged in:  {peak_active} at the same time")
    print(f"Login time:      median {fmt(statistics.median(logins) if logins else None)}  "
          f"p90 {fmt(percentile(logins, 90))}  p99 {fmt(percentile(logins, 99))}  max {fmt(max(logins) if logins else None)}")
    if uploads:
        total_mb = sum(r["bytes"] for r in ok) / 1024 / 1024
        print(f"Upload time:     median {fmt(statistics.median(uploads))}  p90 {fmt(percentile(uploads, 90))}  "
              f"p99 {fmt(percentile(uploads, 99))}  max {fmt(max(uploads))}")
        print(f"Uploaded:        {total_mb:.0f} MB in total")
    print(f"Test took:       {wall:.0f}s")
    if failed:
        print("Failures:")
        for reason, count in Counter(r["error"] for r in failed).most_common():
            print(f"  {count:5d}  {reason}")

    out = f"loadtest-{args.scenario}-{args.users}-{time.strftime('%Y%m%d-%H%M%S')}.csv"
    with open(out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["user", "ok", "login_s", "upload_s", "total_s", "bytes", "error"],
                                extrasaction="ignore")
        writer.writeheader()
        writer.writerows(sorted(records, key=lambda r: r["user"]))
    print(f"Per-student results: {out}")
    sys.exit(0 if not failed else 1)


if __name__ == "__main__":
    main()
