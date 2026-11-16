#!/usr/bin/env python3
"""Fail before publishing local captures, credentials, or personal paths.

This check complements review of every new documentation image; it cannot
determine whether arbitrary prose contains confidential information.
"""
import argparse
import os
import pathlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
BLOCKED_PARTS = {".build", ".swiftpm", "dist", "obj", "private", "screenshots", "captures", "release-artifacts"}
BLOCKED_SUFFIXES = {".png", ".jpg", ".jpeg", ".heic", ".gif", ".zip", ".exe", ".dll", ".pdb", ".dmp", ".p12", ".pfx", ".key", ".cer", ".mobileprovision", ".log"}
PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "GitHub credential": re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})"),
    "service credential": re.compile(r"(?:AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9_-]{40,}|xox[baprs]-[A-Za-z0-9-]{24,})"),
    "personal Mac path": re.compile(r"/Users/[A-Za-z0-9_.-]+/"),
    "personal Windows path": re.compile(r"[A-Za-z]:\\{1,2}Users\\{1,2}[A-Za-z0-9_. -]+\\{1,2}"),
}


def inspect_css(value):
    # Documentation illustrations need no escapes or imports. Reject escapes
    # rather than trying to interpret every CSS spelling of url or @import.
    value = re.sub(r"/\*.*?\*/", "", value, flags=re.S)
    if "\\" in value or re.search(r"@\s*import\b", value, re.I):
        return ["SVG includes CSS imports or escapes"]
    urls = re.findall(r"\burl\s*\((.*?)\)", value, re.I | re.S)
    if len(urls) != len(re.findall(r"\burl\s*\(", value, re.I)):
        return ["SVG includes an invalid CSS reference"]
    for url in urls:
        url = url.strip()
        if len(url) >= 2 and url[0] == url[-1] and url[0] in "\"'":
            url = url[1:-1].strip()
        if not re.fullmatch(r"#[A-Za-z_][A-Za-z0-9_.:-]*", url):
            return ["SVG includes an external CSS reference"]
    return []


def inspect_file(relative, content):
    path = pathlib.PurePosixPath(relative)
    findings = []
    if (set(path.parts) & BLOCKED_PARTS or path.suffix.lower() in BLOCKED_SUFFIXES
            or ".local." in path.name or path.name.startswith(".env")
            or relative.startswith("macos/Tools/")):
        return ["local/private artifact is not publishable"]
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError:
        return ["unexpected binary file; document examples must be reviewed SVG illustrations"]
    for name, pattern in PATTERNS.items():
        if pattern.search(text):
            findings.append(name)
    if path.suffix.lower() == ".svg":
        if not relative.startswith("docs/images/"):
            findings.append("illustration must be under docs/images")
        # Check before parsing: XML entity expansion must never read or expand
        # a document type supplied by an illustration.
        if re.search(r"<!\s*DOCTYPE\b|<\?xml-stylesheet\b", text, re.I):
            findings.append("SVG includes a document type or external stylesheet")
            return sorted(set(findings))
        try:
            root = ET.fromstring(text)
            if root.tag.split("}")[-1].lower() != "svg":
                findings.append("invalid SVG root")
            for node in root.iter():
                tag = node.tag.split("}")[-1].lower()
                if tag in {"image", "script", "foreignobject"}:
                    findings.append("SVG includes embedded/external content")
                if tag == "style":
                    findings.extend(inspect_css("".join(node.itertext())))
                for name, value in node.attrib.items():
                    name = name.split("}")[-1].lower()
                    if name.startswith("on"):
                        findings.append("SVG includes an event handler")
                    if name == "href" and not re.fullmatch(r"#[A-Za-z_][A-Za-z0-9_.:-]*", value):
                        findings.append("SVG includes an external reference")
                    findings.extend(inspect_css(value))
            if not any(word in text for word in ["虚构", "示意"]):
                findings.append("SVG must label its fictional/demo content")
        except ET.ParseError:
            findings.append("invalid SVG")
    return sorted(set(findings))


def scan_files(root, *, tracked=False, staged=False):
    """Return checked path count and findings without exposing matched values."""
    if staged:
        entries = subprocess.check_output(["git", "ls-files", "--stage", "-z"], cwd=root)
        failures = []
        paths = set()
        for entry in entries.split(b"\0"):
            if not entry:
                continue
            metadata, raw_path = entry.split(b"\t", 1)
            mode, blob, stage = metadata.decode("ascii").split()
            relative = os.fsdecode(raw_path)
            paths.add(relative)
            if stage != "0":
                failures.append((relative, "unresolved index entry requires review"))
            elif mode == "120000":
                failures.append((relative, "symlinks require explicit review"))
            elif mode not in {"100644", "100755"}:
                failures.append((relative, "unsupported index file type requires review"))
            else:
                content = subprocess.check_output(["git", "cat-file", "blob", blob], cwd=root)
                failures.extend((relative, finding) for finding in inspect_file(relative, content))
        return len(paths), sorted(set(failures))

    command = ["git", "ls-files", "-z", "--cached"]
    if not tracked:
        command += ["--others", "--exclude-standard"]
    paths = sorted(set(os.fsdecode(subprocess.check_output(command, cwd=root)).split("\0")) - {""})
    failures = []
    count = 0
    for relative in paths:
        path = root / relative
        if path.is_symlink():
            failures.append((relative, "symlinks require explicit review"))
            count += 1
            continue
        if not path.exists():
            continue
        count += 1
        if not path.is_file():
            failures.append((relative, "unsupported file type requires review"))
            continue
        for finding in inspect_file(relative, path.read_bytes()):
            failures.append((relative, finding))
    return count, failures


def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--tracked", action="store_true", help="Check working-tree contents of committed/indexed paths only (CI).")
    modes.add_argument("--staged", action="store_true", help="Check exact Git index contents and file types before committing.")
    args = parser.parse_args()
    count, failures = scan_files(ROOT, tracked=args.tracked, staged=args.staged)
    for relative, reason in failures:
        # Print the category, never the potentially sensitive matching value.
        print(f"BLOCKED {relative}: {reason}")
    if failures:
        return 1
    source = "Git index" if args.staged else "working tree"
    print(f"PASS: {count} public source/document files checked ({source}); no local captures or credential patterns found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
