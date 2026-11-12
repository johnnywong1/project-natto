#!/usr/bin/env python3
"""Runs Project Natto's regression tests and prints one summary.

    python tools/run_tests.py --godot /path/to/godot            # the quick set (~2 min)
    python tools/run_tests.py --godot /path/to/godot --all      # plus the lag profiles (~8 min)
    python tools/run_tests.py --godot /path/to/godot --only unit,menu

Suites (all headless, no window needed):
  unit       game rules: hitboxes, item wheel, shields, lessons, zone collisions, stage files
  ui         the in-game screens: Esc, the bag, the map, controls, settings, exit
  menu       the title screen: pages, name and colour, world slots, hosting, Esc goes back
  lobby      sign-in and sessions: join, Ready, start, leave, rejoin, the host's exit
  lobby-ws   the same lobby story over WebSocket instead of ENet
  save       a solo world is played, saved, loaded again and compared
  session    a 5-player session with bots, a leaver, a late joiner and a 6th player turned away
  scenarios  40 mechanic scenarios over the network (blocks, shields, fire, ice, lifts, doors...)
  lag        (--all) the session and the scenarios again through a lag proxy: home internet
             (~80 ms, 2% loss) and rough Wi-Fi (~150 ms, 5% loss)

Results go to --out (default test_results/): one folder per suite with logs and a
summary.json, plus results.json with every suite's score. Exit code 1 if anything failed.
"""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

QUICK = ["unit", "ui", "menu", "lobby", "lobby-ws", "save", "session", "scenarios"]
LAG = [("home", ["--lag", "40", "--jitter", "8", "--loss", "0.02", "--label", "home internet: ~80 ms ping, 2% loss"]),
       ("rough", ["--lag", "75", "--jitter", "20", "--loss", "0.05", "--label", "rough Wi-Fi: ~150 ms ping, 5% loss"])]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", required=True, help="the Godot 4.7 executable")
    ap.add_argument("--project", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--out", default="test_results")
    ap.add_argument("--all", action="store_true", help="also run the lag profiles")
    ap.add_argument("--only", default="", help="comma-separated suites to run")
    args = ap.parse_args()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    suites = [s for s in args.only.split(",") if s] or (QUICK + (["lag"] if args.all else []))
    results = []
    t0 = time.time()
    for suite in suites:
        for name, passed, total in run_suite(suite, args, out):
            results.append({"suite": name, "passed": passed, "total": total})
            flag = "ok  " if passed == total else "FAIL"
            print(f"{flag} {name:<12} {passed}/{total}")
            sys.stdout.flush()
    (out / "results.json").write_text(json.dumps(results, indent=2))
    bad = [r for r in results if r["passed"] != r["total"]]
    print(f"\n{len(results) - len(bad)}/{len(results)} suites passed in {time.time() - t0:.0f} s"
          + (": " + ", ".join(r["suite"] for r in bad) + " failed" if bad else ""))
    return 1 if bad else 0


def run_suite(suite: str, args, out: Path):
    godot = args.godot
    proj = args.project
    mp = [sys.executable, str(Path(proj) / "tools" / "mp_test.py"), "--godot", godot, "--project", proj]
    if suite == "unit":
        yield "unit", *godot_checks([godot, "--headless", "--path", proj, "-s", "res://game/tests/unit_tests.gd"], out / "unit.txt")
    elif suite == "ui":
        yield "ui", *godot_checks([godot, "--headless", "--path", proj, "--", "--solo", "--ui-test"], out / "ui.txt")
    elif suite == "menu":
        yield "menu", *godot_checks([godot, "--headless", "--path", proj, "--", "--menu-test"], out / "menu.txt")
    elif suite == "lobby-ws":
        yield "lobby-ws", *mp_checks(mp + ["--lobby-test", "--transport", "ws", "--out", str(out / "lobby-ws")], out / "lobby-ws.txt")
    elif suite == "lobby":
        yield "lobby", *mp_checks(mp + ["--lobby-test", "--out", str(out / "lobby")], out / "lobby.txt")
    elif suite == "save":
        yield "save", *mp_checks(mp + ["--save-test", "--out", str(out / "save")], out / "save.txt")
    elif suite == "session":
        yield "session", *mp_checks(mp + ["--out", str(out / "session")], out / "session.txt")
    elif suite == "scenarios":
        yield "scenarios", *mp_checks(mp + ["--scenarios", "--out", str(out / "scenarios")], out / "scenarios.txt")
    elif suite == "lag":
        for tag, extra in LAG:
            port = {"home": "7901", "rough": "7911"}[tag]
            yield f"session-{tag}", *mp_checks(mp + ["--port", port, "--out", str(out / f"session_{tag}")] + extra, out / f"session_{tag}.txt")
            yield f"scenarios-{tag}", *mp_checks(mp + ["--port", port, "--scenarios", "--out", str(out / f"scenarios_{tag}")] + extra, out / f"scenarios_{tag}.txt")
    else:
        print(f"unknown suite {suite}")
        yield suite, 0, 1


def godot_checks(cmd, log: Path):
    """A Godot test script: counts its PASS/FAIL lines."""
    text = run(cmd, log, 300)
    lines = [l for l in text.splitlines() if l.startswith(("PASS  ", "FAIL  "))]
    return sum(l.startswith("PASS") for l in lines), max(len(lines), 1)


def mp_checks(cmd, log: Path):
    """tools/mp_test.py: reads the summary.json it writes."""
    run(cmd, log, 900)
    out_dir = Path(cmd[cmd.index("--out") + 1])
    summary = out_dir / "summary.json"
    if not summary.exists():
        return 0, 1
    data = json.loads(summary.read_text())
    return data["passed"], data["total"]


def run(cmd, log: Path, timeout: int) -> str:
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, text=True, errors="replace")
        text = r.stdout
    except subprocess.TimeoutExpired as e:
        text = (e.stdout or "") + f"\n[timed out after {timeout} s]"
    log.write_text(text)
    return text


if __name__ == "__main__":
    sys.exit(main())
