#!/usr/bin/env python3
"""Statistics for a zsh extended-history file."""
import os
import re
import sys
import shlex
from collections import Counter, defaultdict
from datetime import datetime

PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.zsh_history")
TOP = int(os.environ.get("TOP", "25"))

ENTRY = re.compile(r"^: (\d+):(\d+);(.*)$")


def load(path):
    raw = open(path, "rb").read().decode("utf-8", "replace").splitlines()
    entries = []
    for line in raw:
        m = ENTRY.match(line)
        if m:
            entries.append([int(m.group(1)), int(m.group(2)), m.group(3)])
        elif entries:
            entries[-1][2] = entries[-1][2].rstrip("\\") + "\n" + line
    # zsh stores escaped newlines; drop dangling trailing backslashes
    for e in entries:
        e[2] = e[2].rstrip().rstrip("\\").rstrip()
    return entries


def split_pipeline(cmd):
    """Split on ; | && || and return each sub-command string."""
    return [p for p in re.split(r"\|\||&&|\||;|\n", cmd) if p.strip()]


ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
WRAPPERS = {"sudo", "time", "env", "nohup", "command", "nice", "xargs", "watch", "doas"}


def head_tokens(sub):
    try:
        toks = shlex.split(sub, posix=True)
    except ValueError:
        toks = sub.split()
    toks = [t for t in toks if not ASSIGN.match(t)]
    return toks


def base_cmd(toks):
    i = 0
    while i < len(toks) and (toks[i] in WRAPPERS or toks[i].startswith("-")):
        i += 1
    return os.path.basename(toks[i]) if i < len(toks) else None


def subcommand(toks, cmd):
    """First non-flag arg after the command, for multi-tool CLIs."""
    try:
        i = next(i for i, t in enumerate(toks) if os.path.basename(t) == cmd)
    except StopIteration:
        return None
    for t in toks[i + 1:]:
        if t.startswith("-"):
            continue
        return t
    return None


def bar(n, mx, width=40):
    return "#" * max(1, int(n * width / mx)) if n else ""


def section(title):
    print("\n" + "=" * 72)
    print(title)
    print("=" * 72)


def table(counter, total, limit=TOP, label="item"):
    if not counter:
        print("  (none)")
        return
    mx = counter.most_common(1)[0][1]
    for i, (k, n) in enumerate(counter.most_common(limit), 1):
        print(f"{i:3}. {k[:46]:<46} {n:6}  {100*n/total:5.2f}%  {bar(n, mx)}")


def main():
    entries = load(PATH)
    if not entries:
        sys.exit("no entries parsed")

    cmds = Counter()
    subcmds = defaultdict(Counter)
    full = Counter()
    first_seen, last_seen = {}, {}
    by_hour = Counter()
    by_dow = Counter()
    by_month = Counter()
    days = Counter()
    lengths = []
    sudo_n = pipe_n = 0
    flags = Counter()
    paths = Counter()
    ts_list = []
    bigrams = Counter()
    repeats = 0
    prev_cmd = None
    prev_prog = None
    prev_ts = None
    gaps = []
    sessions = 1
    session_sizes = []
    cur_session = 0

    for ts, dur, cmd in entries:
        cmd = cmd.strip()
        if not cmd:
            continue
        ts_list.append(ts)
        dt = datetime.fromtimestamp(ts)
        by_hour[dt.hour] += 1
        by_dow[dt.weekday()] += 1
        by_month[dt.strftime("%Y-%m")] += 1
        days[dt.date()] += 1
        lengths.append(len(cmd))
        full[cmd] += 1
        if cmd == prev_cmd:
            repeats += 1
        prev_cmd = cmd
        if prev_ts is not None:
            gap = ts - prev_ts
            if gap > 2 * 3600:
                sessions += 1
                session_sizes.append(cur_session)
                cur_session = 0
            elif gap >= 0:
                gaps.append(gap)
        cur_session += 1
        prev_ts = ts
        if "|" in cmd and "||" not in cmd:
            pipe_n += 1
        entry_prog = None
        for sub in split_pipeline(cmd):
            toks = head_tokens(sub)
            if not toks:
                continue
            if toks[0] == "sudo":
                sudo_n += 1
            c = base_cmd(toks)
            if not c:
                continue
            cmds[c] += 1
            if entry_prog is None:
                entry_prog = c
            first_seen.setdefault(c, ts)
            last_seen[c] = ts
            s = subcommand(toks, c)
            if s and not s.startswith(("/", "~", ".", "$")) and "=" not in s:
                subcmds[c][s] += 1
            for t in toks[1:]:
                if t.startswith("-") and len(t) > 1:
                    flags[f"{c} {t}"] += 1
                elif "/" in t:
                    paths[t.rsplit("/", 1)[0] + "/"] += 1

        if entry_prog:
            if prev_prog and prev_prog != entry_prog:
                bigrams[f"{prev_prog} -> {entry_prog}"] += 1
            prev_prog = entry_prog

    total_cmd = sum(cmds.values())
    t0, t1 = min(ts_list), max(ts_list)
    span_days = max(1, (t1 - t0) / 86400)

    section("OVERVIEW")
    print(f"  history file        : {PATH}")
    print(f"  entries (lines)     : {len(entries)}")
    print(f"  unique full commands: {len(full)}  ({100*len(full)/len(entries):.1f}% unique)")
    print(f"  distinct programs   : {len(cmds)}")
    print(f"  invocations counted : {total_cmd}")
    print(f"  period              : {datetime.fromtimestamp(t0):%Y-%m-%d} .. {datetime.fromtimestamp(t1):%Y-%m-%d}  ({span_days:.0f} days)")
    print(f"  active days         : {len(days)}  ({100*len(days)/span_days:.1f}% of period)")
    print(f"  cmds / active day   : {len(entries)/len(days):.1f}")
    print(f"  avg command length  : {sum(lengths)/len(lengths):.1f} chars (max {max(lengths)})")
    print(f"  with pipes          : {pipe_n} ({100*pipe_n/len(entries):.1f}%)")
    print(f"  with sudo           : {sudo_n} ({100*sudo_n/len(entries):.1f}%)")
    session_sizes.append(cur_session)
    gaps.sort()
    med = gaps[len(gaps)//2] if gaps else 0
    print(f"  shell sessions      : {sessions} (gap > 2h)  avg {sum(session_sizes)/len(session_sizes):.1f} cmds/session")
    print(f"  median think-time   : {med}s between consecutive commands")
    print(f"  immediate repeats   : {repeats} ({100*repeats/len(entries):.1f}%)  <- retries / re-runs")

    section("COMMAND TRANSITIONS (what you typically run after what)")
    table(bigrams, sum(bigrams.values()), limit=20)

    section(f"TOP {TOP} PROGRAMS")
    table(cmds, total_cmd)

    section("COVERAGE / CONCENTRATION")
    cum = 0
    marks = [50, 80, 90, 95, 99]
    mi = 0
    for i, (k, n) in enumerate(cmds.most_common(), 1):
        cum += n
        while mi < len(marks) and 100 * cum / total_cmd >= marks[mi]:
            print(f"  top {i:4} programs  = {marks[mi]}% of all invocations")
            mi += 1
    once = sum(1 for v in cmds.values() if v == 1)
    print(f"  used exactly once  : {once} programs ({100*once/len(cmds):.1f}% of your vocabulary)")

    section(f"TOP {TOP} FULL COMMAND LINES (verbatim repeats -> alias/script candidates)")
    table(full, len(entries))

    section("SUB-COMMAND BREAKDOWN (multi-tool CLIs)")
    for c, _ in cmds.most_common(60):
        sc = subcmds[c]
        if len(sc) >= 3 and sum(sc.values()) >= 10:
            top = ", ".join(f"{k}:{v}" for k, v in sc.most_common(8))
            print(f"  {c:<12} ({sum(sc.values())}) -> {top}")

    section("TOP FLAGS")
    table(flags, total_cmd, limit=20)

    section("TOP DIRECTORIES REFERENCED IN ARGUMENTS")
    table(paths, total_cmd, limit=15)

    section("ACTIVITY BY HOUR OF DAY")
    mx = max(by_hour.values())
    for h in range(24):
        n = by_hour.get(h, 0)
        print(f"  {h:02}:00 {n:6} {bar(n, mx, 50)}")

    section("ACTIVITY BY WEEKDAY")
    names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    mx = max(by_dow.values())
    for d in range(7):
        n = by_dow.get(d, 0)
        print(f"  {names[d]} {n:6} {bar(n, mx, 50)}")

    section("ACTIVITY BY MONTH")
    mx = max(by_month.values())
    for m in sorted(by_month):
        print(f"  {m} {by_month[m]:6} {bar(by_month[m], mx, 50)}")

    section("BUSIEST DAYS")
    for d, n in days.most_common(10):
        print(f"  {d}  {n}")

    section("TOOL LIFECYCLE (recently adopted vs abandoned)")
    now = t1
    new = [(c, first_seen[c]) for c in cmds if cmds[c] >= 5 and now - first_seen[c] < 90 * 86400]
    old = [(c, last_seen[c]) for c in cmds if cmds[c] >= 20 and now - last_seen[c] > 180 * 86400]
    print("  Adopted in last 90 days (>=5 uses):")
    for c, ts in sorted(new, key=lambda x: -x[1])[:15]:
        print(f"    {c:<20} since {datetime.fromtimestamp(ts):%Y-%m-%d}  ({cmds[c]} uses)")
    if not new:
        print("    (none)")
    print("  Dropped >180 days ago (>=20 uses historically):")
    for c, ts in sorted(old, key=lambda x: -x[1])[:15]:
        print(f"    {c:<20} last  {datetime.fromtimestamp(ts):%Y-%m-%d}  ({cmds[c]} uses)")
    if not old:
        print("    (none)")

    section("ALIAS / SCRIPT SUGGESTIONS")
    print("  (repeated long command lines - biggest typing savings)")
    scored = sorted(((n * len(c), n, c) for c, n in full.items() if n >= 3 and len(c) > 25),
                    reverse=True)[:15]
    for saved, n, c in scored:
        print(f"    {n:4}x {len(c):4}ch  ~{saved:6} keystrokes  {c[:70]}")

    section("TYPO / FAILURE SIGNALS")
    short = Counter({k: v for k, v in cmds.items() if len(k) <= 3 and v <= 3})
    print("  Rare very short tokens (likely typos / aborted lines):")
    print("   ", ", ".join(f"{k}({v})" for k, v in short.most_common(30)) or "(none)")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        os._exit(0)
