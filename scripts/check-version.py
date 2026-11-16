#!/usr/bin/env python3
import pathlib
import plistlib
import re
import sys


def without_comments(source):
    # Keep C# strings intact while ignoring commented-out declarations.
    tokens = r'@"(?:[^"]|"")*"|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*.*?\*/'
    return re.sub(tokens, lambda match: " " if match[0].startswith(("//", "/*")) else match[0], source, flags=re.S)


def check_versions(root):
    version = (root / "VERSION").read_text().strip()
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError("VERSION must be a stable three-part version")
    plist = plistlib.loads((root / "macos/Resources/Info.plist").read_bytes())
    if plist.get("CFBundleShortVersionString") != version:
        raise ValueError("macOS version differs from VERSION")
    updates = without_comments((root / "windows/src/Updates.cs").read_text(encoding="utf-8-sig"))
    current = re.findall(r'\bconst\s+string\s+CurrentVersion\s*=\s*"([^"]*)"\s*;', updates)
    if current != [version]:
        raise ValueError("Windows CurrentVersion must appear exactly once and match VERSION")
    app = without_comments((root / "windows/src/App.cs").read_text(encoding="utf-8-sig"))
    for name in ("AssemblyVersion", "AssemblyFileVersion"):
        values = re.findall(r'\[\s*assembly\s*:\s*' + name + r'\s*\(\s*"([^"]*)"\s*\)\s*\]', app)
        if values != [version + ".0"]:
            raise ValueError(f"Windows {name} must appear exactly once and match VERSION + .0")
    return version


def main():
    try:
        print(check_versions(pathlib.Path(__file__).resolve().parents[1]))
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
