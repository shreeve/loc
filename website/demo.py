#!/usr/bin/env python3
"""Regenerates demo.json, the terminal demo on the page, from loco's real
output. Run from the repository root after `rig/build.sh`:

    python3 website/demo.py ~/Data/Code rip

The second argument is the tree, named relative to the first, so the
page shows `loco rip`.
"""
import json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCO = os.path.join(ROOT, "bin", "loco")
SGR = re.compile(r"\x1b\[([0-9;]*)m")


def styled(cwd, args):
    """loco's output as a terminal shows it: `script` gives it a tty."""
    with tempfile.NamedTemporaryFile() as out:
        subprocess.run(["script", "-q", out.name, LOCO, *args], cwd=cwd,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True)
        text = open(out.name, encoding="utf-8").read()
    text = re.sub(r"^\^D\x08+", "", text.replace("\r\n", "\n"))
    return text.rstrip("\n")


def segments(line):
    """[text, color, bold, dim] runs of one line of SGR-styled text."""
    runs, fg, bold, dim, at = [], None, False, False, 0
    for m in SGR.finditer(line):
        if m.start() > at:
            runs.append([line[at:m.start()], fg, bold, dim])
        codes = [int(c) for c in m.group(1).split(";") if c] or [0]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == 0:
                fg, bold, dim = None, False, False
            elif c == 1:
                bold = True
            elif c == 2:
                dim = True
            elif c in (38, 48) and codes[i + 1] == 2:
                if c == 38:
                    fg = "#%02x%02x%02x" % tuple(codes[i + 2:i + 5])
                i += 4
            i += 1
        at = m.end()
    if at < len(line):
        runs.append([line[at:], fg, bold, dim])
    return runs


def main():
    cwd, tree = sys.argv[1], sys.argv[2]
    table = styled(cwd, [tree])
    lines = [segments(l) for l in table.split("\n")]
    raw = subprocess.run([LOCO, "--json", "-l", "rip", tree], cwd=cwd,
                         capture_output=True, check=True).stdout
    demo = {
        "table": {"cmd": f"loco {tree}", "lines": lines},
        "json": {"cmd": f"loco --json -l rip {tree} | jq", "text": json.dumps(json.loads(raw), indent=2)},
    }
    with open(os.path.join(ROOT, "website", "demo.json"), "w") as f:
        json.dump(demo, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")


main()
