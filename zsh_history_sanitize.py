#!/usr/bin/env python3
"""Sanitize a zsh history file before migrating it to another machine.

Redacts secrets (passwords, tokens, API keys, credentials in URLs, auth
headers) while preserving timestamps, ordering and command structure.

Usage:
    ./zsh_history_sanitize.py ~/.zsh_history -o ~/.zsh_history.clean
    ./zsh_history_sanitize.py ~/.zsh_history -o out --report report.txt --review review.txt
    ./zsh_history_sanitize.py ~/.zsh_history -o out --entropy --mask-ips --drop-unsafe
    ./zsh_history_sanitize.py ~/.zsh_history -o out \
        --secret-words-file ~/.config/zsh-sanitize/secret-words.txt
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from collections import Counter

REDACTED = "<REDACTED>"

# Names that look secret-ish. *PATH* is excluded deliberately (PATH matches
# a naive "PAT" rule, and PYTHONPATH/LD_LIBRARY_PATH are not secrets).
SECRET_NAME = r"(?!.*PATH\b)[A-Za-z0-9_]*(?:PASSWORD|PASSWD|PASSPHRASE|SECRET|TOKEN|APIKEY|API_KEY|ACCESS_KEY|SECRET_KEY|PRIVATE_KEY|CREDENTIAL|AUTH|PAT)[A-Za-z0-9_]*"

# Flags whose argument is a secret.
SECRET_FLAG = r"--?(?:pw|pass|passwd|password|passphrase|token|auth-token|access-token|api-?key|apikey|secret|client-secret|bearer|credential)"

# Value forms: quoted, or bare up to whitespace.
VALUE = r"""(?:"[^"]*"|'[^']*'|[^\s;|&]+)"""

# Vendor token shapes that are unambiguously secrets.
TOKEN_PATTERNS = [
    r"\bghp_[A-Za-z0-9]{20,}",
    r"\bgh[osur]_[A-Za-z0-9]{20,}",
    r"\bgithub_pat_[A-Za-z0-9_]{20,}",
    r"\bglpat-[A-Za-z0-9_-]{15,}",
    r"\bxox[baprse]-[A-Za-z0-9-]{10,}",
    r"\bAKIA[0-9A-Z]{16}\b",
    r"\bASIA[0-9A-Z]{16}\b",
    r"\bAIza[0-9A-Za-z_-]{30,}",
    r"\bsk-(?:proj-|ant-|live-|test-)?[A-Za-z0-9_-]{20,}",
    r"\bnpm_[A-Za-z0-9]{30,}",
    r"\bdop_v1_[a-f0-9]{30,}",
    r"\bshpat_[a-f0-9]{30,}",
    r"\bhf_[A-Za-z0-9]{30,}",
    r"\bpypi-AgEI[A-Za-z0-9_-]{20,}",
    r"\bSG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}",
    r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+",  # JWT
    r"-----BEGIN[A-Z ]*PRIVATE KEY-----",
]

# Commands where a glued -p<value> really is a password.
DB_CMD = r"(?:mysql|mysqldump|mysqladmin|mariadb|redis-cli|mongo|mongosh|psql)"

IP_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
PRIVATE_IP_OK = re.compile(r"^(?:0\.0\.0\.0|127\.|255\.)")

# Entries that are risky but cannot be redacted safely -> candidates to drop.
UNSAFE_ENTRY = [
    (re.compile(r"\bhistory\b.*\b(grep|rg)\b", re.I), "history search"),
    (re.compile(r"\b(cat|less|more|bat|vim?|nano)\b[^|;]*(\.env|credentials|\.pem|\.key|id_rsa|id_ed25519|\.netrc|secrets?\.(ya?ml|json))", re.I), "reads secret file"),
    (re.compile(r"\becho\b[^|]*\|\s*(?:docker|podman|helm|gh|npm)\s+\w*\s*login", re.I), "piped login secret"),
]


def load_secret_words(path):
    """Load custom secret substrings, one per line.

    Lines starting with ``re:`` are treated as regular expressions, ``#`` marks
    a comment. Kept in an external file so the substrings never need to be
    written into this script or typed on a command line (which would land in
    the very history being sanitized).
    """
    words, regexes = [], []
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("re:"):
                regexes.append(line[3:])
            else:
                words.append(re.escape(line))
    return words, regexes


def build_rules(args):
    """Return [(name, compiled_regex, replacement_fn, context)] applied in order.

    ``context`` is an optional regex that must match the whole command before
    the rule fires; it keeps narrow rules from hitting unrelated commands.
    """
    rules = []

    def add(name, pattern, repl, flags=0, context=None):
        rules.append((name, re.compile(pattern, flags), repl,
                      re.compile(context, re.I) if context else None))

    # 0. Custom secret substrings are appended at the end of this function so
    #    that the structural rules below get first chance at well-formed cases
    #    (URLs, flags), keeping more useful context in the command.

    # 1. Credentials embedded in URLs: scheme://user:pass@host
    add(
        "url-credentials",
        r"(?P<pre>[A-Za-z][A-Za-z0-9+.-]*://[^/\s:@]+:)(?P<secret>[^/\s@]+)(?P<post>@)",
        lambda m: m.group("pre") + REDACTED + m.group("post"),
    )

    # 2. Vendor token shapes anywhere in the line.
    for i, pat in enumerate(TOKEN_PATTERNS):
        add(f"vendor-token", pat, lambda m: "<REDACTED_TOKEN>")

    # 3. Secret-bearing flags: --pw X / --pw=X / --pw "X"
    #    Empty values ("" or '') are kept: they carry meaning, not a secret.
    def flag_repl(m):
        val = m.group("val")
        if val in ('""', "''"):
            return m.group(0)
        quote = val[0] if val[:1] in "\"'" else ""
        return f"{m.group('flag')}{m.group('sep')}{quote}{REDACTED}{quote}"

    add(
        "secret-flag",
        rf"(?P<flag>{SECRET_FLAG})(?P<sep>[= ]+)(?P<val>{VALUE})",
        flag_repl,
        re.I,
    )

    # 4. sshpass -p <secret>
    add(
        "sshpass",
        rf"(?P<pre>\bsshpass\s+-p\s*)(?P<val>{VALUE})",
        lambda m: m.group("pre") + REDACTED,
    )

    # 5. mysql/redis style glued password: -p<secret>
    add(
        "db-password",
        rf"(?P<pre>\b{DB_CMD}\b[^|;&]*?\s-p)(?P<val>[^\s;|&]+)",
        lambda m: m.group("pre") + REDACTED,
    )

    # 6. curl -u user:pass / --user user:pass. Scoped to HTTP-ish clients so
    #    that `docker run --user 1000:1000` (uid:gid) is not touched.
    def userpass_repl(m):
        user, val = m.group("user"), m.group("val")
        if user.isdigit() and val.isdigit():
            return m.group(0)
        return f"{m.group('pre')}{user}:{REDACTED}"

    add(
        "basic-auth",
        r"(?P<pre>\s-u\s+|--user[= ]+)(?P<user>[^\s:;|&'\"]+):(?P<val>[^\s;|&'\"]+)",
        userpass_repl,
        context=r"\b(curl|wget|http|httpie|svn|rclone|ldapsearch|ldapdomaindump|smbclient|crackmapexec)\b",
    )

    # 7. Authorization / API-key headers.
    add(
        "auth-header",
        r"(?P<pre>(?:Authorization|X-Api-Key|X-Auth-Token|Private-Token|api-key)\s*:\s*)(?P<scheme>Bearer\s+|Basic\s+|Token\s+)?(?P<val>[^\s'\"]+)",
        lambda m: m.group("pre") + (m.group("scheme") or "") + REDACTED,
        re.I,
    )

    # 8. Environment assignments with secret-looking names.
    def env_repl(m):
        val = m.group("val")
        if val in ('""', "''", ""):
            return m.group(0)
        quote = val[0] if val[:1] in "\"'" else ""
        return f"{m.group('name')}={quote}{REDACTED}{quote}"

    add(
        "env-assignment",
        rf"(?P<name>\b{SECRET_NAME})=(?P<val>{VALUE})",
        env_repl,
    )

    # 9. .netrc-style inline passwords (`machine host login u password p`).
    add(
        "netrc-password",
        rf"(?P<pre>\bpassword\s+)(?P<val>{VALUE})",
        lambda m: m.group("pre") + REDACTED,
        context=r"\bmachine\s+\S+|\.netrc\b",
    )

    # 10. Custom secret substrings: redact the whole token containing the
    #     fragment (so trailing digits/symbols of a password go too), while
    #     keeping a `key=` or `user%` prefix for readability.
    if args.secret_words_file:
        words, regexes = load_secret_words(args.secret_words_file)
        for frag in words + regexes:
            add(
                "custom-secret",
                rf"(?P<pre>[A-Za-z0-9_.-]+[=%])?(?P<sec>[^\s'\"`;|&]*(?:{frag})[^\s'\"`;|&]*)",
                lambda m: (m.group("pre") or "") + REDACTED,
                re.I,
            )

    if args.mask_ips:
        def ip_repl(m):
            ip = m.group(0)
            return ip if PRIVATE_IP_OK.match(ip) else "<IP>"

        add("ip-address", IP_RE.pattern, ip_repl)

    return rules


def shannon_entropy(s: str) -> float:
    if not s:
        return 0.0
    counts = Counter(s)
    n = len(s)
    return -sum((c / n) * math.log2(c / n) for c in counts.values())


HEX_RE = re.compile(r"\b[a-f0-9]{32,}\b", re.I)
B64_RE = re.compile(r"\b[A-Za-z0-9+/]{32,}={0,2}\b")
# Contexts where long hex strings are commit/image digests, not secrets.
DIGEST_CTX = re.compile(r"\b(git|docker|podman|buildah|sha256|md5sum|sha1sum|sha256sum|nix|guix|repo|hg|svn)\b", re.I)


def entropy_redact(cmd: str, threshold: float):
    """Redact standalone high-entropy blobs. Opt-in: can create false positives."""
    hits = 0
    if DIGEST_CTX.search(cmd):
        return cmd, 0

    def repl(m):
        nonlocal hits
        tok = m.group(0)
        if shannon_entropy(tok) < threshold:
            return tok
        hits += 1
        return "<REDACTED_HIGH_ENTROPY>"

    cmd = HEX_RE.sub(repl, cmd)
    cmd = B64_RE.sub(repl, cmd)
    return cmd, hits


ENTRY_RE = re.compile(r"^: (\d+):(\d+);(.*)$", re.S)


def parse(text: str):
    """Yield (header, command) entries. Multi-line commands end with a backslash."""
    entries = []
    current = None
    for line in text.splitlines(keepends=True):
        m = re.match(r"^: \d+:\d+;", line)
        if m and (current is None or not current.endswith("\\\n")):
            if current is not None:
                entries.append(current)
            current = line
        elif current is None:
            current = line  # history without extended timestamps
        else:
            current += line
    if current is not None:
        entries.append(current)
    return entries


def split_entry(entry: str):
    m = re.match(r"^(: \d+:\d+;)(.*)$", entry, re.S)
    if m:
        return m.group(1), m.group(2)
    return "", entry


def main() -> int:
    p = argparse.ArgumentParser(description="Sanitize zsh history for migration.")
    p.add_argument("input")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--report", help="write a redaction report here")
    p.add_argument("--review", help="write entries needing manual review here")
    p.add_argument("--secret-words-file",
                   help="file with custom secret substrings, one per line "
                        "(prefix a line with 're:' for a regex, '#' for a comment)")
    p.add_argument("--entropy", action="store_true",
                   help="also redact standalone high-entropy blobs (may over-redact)")
    p.add_argument("--entropy-threshold", type=float, default=3.5)
    p.add_argument("--mask-ips", action="store_true", help="replace public IPs with <IP>")
    p.add_argument("--drop-unsafe", action="store_true",
                   help="delete entries that cannot be safely redacted")
    args = p.parse_args()

    with open(args.input, "r", encoding="utf-8", errors="surrogateescape") as fh:
        text = fh.read()

    rules = build_rules(args)
    entries = parse(text)

    stats = Counter()
    report_lines = []
    review_lines = []
    out_entries = []
    dropped = 0

    for idx, entry in enumerate(entries, 1):
        header, cmd = split_entry(entry)
        original = cmd

        drop_reason = None
        for rx, reason in UNSAFE_ENTRY:
            if rx.search(cmd):
                drop_reason = reason
                break

        if drop_reason and args.drop_unsafe:
            stats[f"dropped:{drop_reason}"] += 1
            dropped += 1
            report_lines.append(f"[{idx}] DROPPED ({drop_reason}): {original.strip()}")
            continue
        if drop_reason:
            review_lines.append(f"[{idx}] {drop_reason}: {original.strip()}")

        for name, rx, repl, context in rules:
            if context and not context.search(cmd):
                continue
            cmd, n = rx.subn(repl, cmd)
            if n:
                stats[name] += n

        if args.entropy:
            cmd, n = entropy_redact(cmd, args.entropy_threshold)
            if n:
                stats["high-entropy"] += n

        if cmd != original:
            report_lines.append(f"[{idx}] -: {original.strip()}")
            report_lines.append(f"[{idx}] +: {cmd.strip()}")

        out_entries.append(header + cmd)

    out = "".join(out_entries)
    if out and not out.endswith("\n"):
        out += "\n"
    with open(args.output, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(out)

    if args.report:
        with open(args.report, "w", encoding="utf-8", errors="surrogateescape") as fh:
            fh.write("\n".join(report_lines) + "\n")
    if args.review:
        with open(args.review, "w", encoding="utf-8", errors="surrogateescape") as fh:
            fh.write("\n".join(review_lines) + "\n")

    print(f"entries in : {len(entries)}")
    print(f"entries out: {len(out_entries)} (dropped {dropped})")
    print(f"modified   : {sum(1 for l in report_lines if l.startswith('[') and '] -:' in l)}")
    for name, n in sorted(stats.items(), key=lambda kv: -kv[1]):
        print(f"  {name:28} {n}")
    if review_lines:
        print(f"manual review candidates: {len(review_lines)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
