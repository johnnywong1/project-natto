#!/usr/bin/env python3
"""Automated multiplayer test for Project Natto.

Starts a host and four players as separate headless Godot processes on this machine.
They meet in the lobby, the host starts at 5/5, and test bots play different roles across
zones. Midway one player leaves and a new one joins the game in progress, then a sixth
person tries to join a full game. Every process writes a JSON report; this script
compares them and prints PASS/FAIL for each check.

With --scenarios it instead runs the mechanic scenarios (game/tests/scenarios.gd): a test
player joins a --test host over the network and checks dashes, blocks, telegraphs, fire,
rain, lanterns, ice, chests, gear, stamina, aiming, darkness, shields, hitboxes, the item
wheel, Pepper's lessons and house doors one by one.

With --save-test it plays a solo world (a bot farms, gears up, drops a pin and meets
Pepper), saves it, starts the same world again and checks everything came back.

Usage:
    python tools/mp_test.py --godot /path/to/godot [--project .] [--out mp_results]
    python tools/mp_test.py --godot /path/to/godot --scenarios [--lag 60 --jitter 15 --loss 0.02]
    python tools/mp_test.py --godot /path/to/godot --save-test
"""
import re
import argparse
import json
import math
import os
import subprocess
import sys
import time
from pathlib import Path

MINUTES_PER_SECOND = 1.5  # must match World.MINUTES_PER_SECOND


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", required=True)
    ap.add_argument("--project", default=".")
    ap.add_argument("--out", default="mp_results")
    ap.add_argument("--port", default="7777")
    ap.add_argument("--time-scale", default="20")
    ap.add_argument("--weather-period", default="6")
    ap.add_argument("--label", default="localhost")
    ap.add_argument("--lag", type=float, default=0.0, help="one-way delay in ms through tools/lag_proxy.py")
    ap.add_argument("--jitter", type=float, default=0.0)
    ap.add_argument("--loss", type=float, default=0.0, help="packet loss 0-1")
    ap.add_argument("--scenarios", nargs="?", const="all", default=None,
                    help="run the mechanic scenarios (all, or a comma-separated list) instead of the session")
    ap.add_argument("--save-test", action="store_true",
                    help="play a solo world, save, start it again and check everything came back")
    ap.add_argument("--lobby-test", action="store_true",
                    help="two processes: join, ready, start, leave, rejoin, and the host's exit ending the game")
    args = ap.parse_args()
    if args.scenarios:
        return run_scenarios(args)
    if args.save_test:
        return run_save_test(args)
    if args.lobby_test:
        return run_lobby_test(args)

    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.json"):
        f.unlink()
    common = [f"--time-scale={args.time_scale}", f"--weather-period={args.weather_period}", "--bot"]
    procs = {}
    join_port = args.port
    proxy = None
    if args.lag > 0 or args.loss > 0:
        join_port = str(int(args.port) + 13)
        here = Path(__file__).resolve().parent
        proxy = subprocess.Popen([sys.executable, str(here / "lag_proxy.py"), "--listen", join_port, "--host-port", args.port,
                                  "--delay", str(args.lag), "--jitter", str(args.jitter), "--loss", str(args.loss), "--seconds", "75"],
                                 stdout=open(out / "proxy.log", "w"), stderr=subprocess.STDOUT)
        time.sleep(0.5)

    def launch(name, extra):
        log = open(out / f"{name}.log", "w")
        port = args.port if "--host" in extra else join_port
        cmd = [args.godot, "--headless", "--path", args.project, "--"] + common + [
            f"--port={port}", f"--name={name}", f"--report={out / (name + '.json')}"] + extra
        procs[name] = (subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT), log)

    t0 = time.time()
    # The host stays a few seconds after its report so that players whose start message
    # arrived late on a lossy link still reach their own report time.
    launch("Host", ["--host", "--role=0", "--autostart=5", "--autostart-timeout=40", "--report-at=45", "--linger=5",
                    "--force-weather=middlemost:rain:10:8"])
    time.sleep(1.0)
    for i in range(1, 5):
        leave_early = i == 4
        launch(f"Bot{i}", ["--join=127.0.0.1", f"--role={i}",
                           "--report-at=" + ("20" if leave_early else "44"), "--linger=" + ("0" if leave_early else "15")])
        time.sleep(0.3)
    time.sleep(27.0 - (time.time() - t0))
    launch("Late", ["--join=127.0.0.1", "--role=5", "--report-at=16", "--linger=15"])
    time.sleep(33.0 - (time.time() - t0))
    launch("Extra", ["--join=127.0.0.1", "--role=1", "--report-at=10"])

    deadline = time.time() + 90
    for name, (p, log) in procs.items():
        try:
            p.wait(timeout=max(1, deadline - time.time()))
        except subprocess.TimeoutExpired:
            p.kill()
        log.close()
    if proxy is not None:
        proxy.terminate()
    print(f"all processes finished after {time.time() - t0:.1f}s\n")
    return evaluate(out, args.label, args.lag, args.jitter)


def load(out, name):
    p = out / f"{name}.json"
    return json.loads(p.read_text()) if p.exists() else None


def evaluate(out: Path, label: str, lag_ms: float = 0.0, jitter_ms: float = 0.0) -> int:
    names = ["Host", "Bot1", "Bot2", "Bot3", "Bot4", "Late", "Extra"]
    rep = {n: load(out, n) for n in names}
    checks = []

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": detail})
        print(("PASS  " if ok else "FAIL  ") + name + (f"   [{detail}]" if detail else ""))

    missing = [n for n in names if rep[n] is None]
    check("every process wrote a report", not missing, "missing: " + ", ".join(missing) if missing else "7 reports")
    if missing:
        save(out, checks, rep, label)
        return 1

    broken = [f"{n}: {rep[n].get('error')} ({rep[n].get('status', '')})" for n in names if "error" in rep[n]]
    check("every player got into the game", not broken, "; ".join(broken))
    if broken:
        return save(out, checks, rep, label)

    host = rep["Host"]
    final = ["Host", "Bot1", "Bot2", "Bot3", "Late"]          # connected at the end
    ids = {n: str(rep[n]["peer_id"]) for n in names if "peer_id" in rep[n]}

    # Lobby and start
    check("lobby reached 5/5 before start", all(rep[n]["lobby_max_players"] == 5 for n in ["Host", "Bot1", "Bot2", "Bot3", "Bot4"]),
          ", ".join(f"{n}:{rep[n]['lobby_max_players']}" for n in ["Host", "Bot1", "Bot2", "Bot3", "Bot4"]))
    timeline = [c for _, c in host["count_timeline"]]
    check("host saw 5 -> 4 (leave) -> 5 (late join)", _subseq(timeline, [5, 4, 5]), "player counts: " + "".join(str(c) for c in timeline))
    check("late player joined a game in progress", rep["Late"]["joined_in_progress"] and rep["Late"]["game_time"] > 10)
    check("6th player turned away", "full" in rep["Extra"].get("rejected", ""), rep["Extra"].get("rejected", "no rejection"))

    # Map beacons: everyone sees everyone, in the right zone
    problems = []
    for viewer in final:
        for target in final:
            if viewer == target:
                continue
            b = rep[viewer]["beacons"].get(ids[target])
            if b is None:
                problems.append(f"{viewer} can't see {target}")
            elif b[0] != rep[target]["zone"]:
                problems.append(f"{viewer} sees {target} in {b[0]}, really {rep[target]['zone']}")
        if ids["Bot4"] in rep[viewer]["beacons"]:
            problems.append(f"{viewer} still shows Bot4 after it left")
    check("friends on the map: all 5 visible to each other, correct zone", not problems, "; ".join(problems[:4]) or "20/20 pairs")

    # Positions over time: what each player saw of a friend vs. where that friend really was.
    # An update is a little old when it arrives, so it must match the friend's real path at
    # some moment within the delay window.
    by_id = {ids[n]: n for n in final}
    delay = 0.30 + 2 * (lag_ms + jitter_ms) / 1000.0 + 0.1
    errs = {"b": [], "r": []}
    for viewer in final:
        t_end = rep[viewer]["wall_time"]
        for t, kind, pid, x, y in rep[viewer]["seen_log"]:
            target = by_id.get(pid)
            if target is None or t < t_end - 24.0:
                continue
            log = rep[target]["pos_log"]
            if not log or t > log[-1][0] or t - delay < log[0][0]:
                continue
            errs[kind].append(path_distance(log, (x, y), t - delay - (0.25 if kind == "r" else 0.0), t + 0.05))
    for kind, title, limit in (("b", "map", 5.0), ("r", "in-zone", 8.0)):
        e = sorted(errs[kind])
        if not e:
            check(f"{title} positions track friends over time", False, "no overlapping samples")
            continue
        p95 = e[int(len(e) * 0.95)]
        check(f"{title} positions track friends' real paths (p95 < {limit:.0f} px)", p95 < limit,
              f"{len(e)} samples over the last 24 s: median {e[len(e) // 2]:.2f}, p95 {p95:.2f}, max {e[-1]:.1f} px")

    # Zone detail (interest management)
    zone_of = {n: rep[n]["zone"] for n in final}
    problems = []
    worst = 0.0
    for viewer in final:
        vis = rep[viewer]["visible_remotes"]
        expected = {ids[t] for t in final if t != viewer and zone_of[t] == zone_of[viewer]}
        if set(vis) != expected:
            problems.append(f"{viewer} in {zone_of[viewer]} shows {sorted(vis)} expected {sorted(expected)}")
    check("zones are separate instances: you only see players in your zone", not problems,
          "; ".join(problems[:3]) or ", ".join(f"{n}@{zone_of[n]}" for n in final))
    # A real leak would be continuous (20 updates a second about players elsewhere). The only
    # allowed strays are the moment someone changes zone, when the 4 Hz map beacon and the
    # 20 Hz zone snapshot briefly disagree, or a last snapshot of the old zone arrives.
    hops = sum(rep[n]["zone_changes"] for n in names if "zone_changes" in rep[n])
    foreign = sum(rep[n]["foreign_sightings"] for n in final)
    old_zone = sum(rep[n].get("other_zone_snapshots", 0) for n in final)
    check("no lasting detail leaks across zones", foreign <= 6 * hops and old_zone <= 3 * hops,
          f"{foreign} momentary map/zone disagreements and {old_zone} late old-zone snapshots across {hops} zone changes")
    zones_used = sorted(set(zone_of.values()))
    check("players spread across several zones", len(zones_used) >= 2, ", ".join(zones_used))
    check("zone travel worked both ways", rep["Bot4"]["zone_changes"] >= 2 and rep["Bot1"]["zone"] == "fernery" and rep["Bot2"]["zone"] == "mossmouth",
          f"Bot4 changed zone {rep['Bot4']['zone_changes']}x and ended in {rep['Bot4']['zone']}")

    # Pins
    pin_sets = {n: sorted(p["id"] for p in rep[n]["pins"]) for n in final}
    same = all(pin_sets[n] == pin_sets["Host"] for n in final)
    labels = sorted(p["label"] for p in host["pins"])
    check("pins: everyone has the same pins", same, f"{len(pin_sets['Host'])} pins: " + ", ".join(labels))
    check("pins from every player arrived (incl. the one who left)", len(labels) >= 6, f"{len(labels)} pins")
    check("late joiner received the pins placed before it arrived", len(rep["Late"]["pins"]) == len(host["pins"]))

    # World state
    crops_same = all(rep[n]["crops"] == host["crops"] for n in final)
    check("crops identical for everyone", crops_same, host["crops"]["middlemost"][:47] + "...")
    bag = {}
    for s in host["inventory"] + host["wheel"]:
        if s:
            bag[s[0]] = bag.get(s[0], 0) + s[1]
    check("host farmed: planted, watered twice, harvested", bag.get("popberry", 0) > 4 and bag.get("popberry_seed", 12) < 12,
          "host bag: " + ", ".join(f"{k} x{v}" for k, v in bag.items()))
    # Compare each player's weather with what the host had at that same moment
    # (a change can land in the second between two players' reports).
    def host_weather_at(t):
        state = {}
        for when, zone, kind in sorted(host["weather_log"]):
            if when <= t:
                state[zone] = kind
        return state
    problems = []
    for n in final:
        t = rep[n]["wall_time"]
        if rep[n]["weather"] not in (host_weather_at(t), host_weather_at(t - 1.0)):
            problems.append(f"{n} has {rep[n]['weather']} but host had {host_weather_at(t)}")
    check("weather identical for everyone (at the same moment)", not problems, "; ".join(problems[:2]) or json.dumps(host["weather"]))
    check("weather changed during the session", all(rep[n]["weather_events"] >= 3 for n in final),
          ", ".join(f"{n}:{rep[n]['weather_events']}" for n in final))
    spread = []
    for n in final:
        expected = (rep[n]["clock"] + (host["wall_time"] - rep[n]["wall_time"]) * MINUTES_PER_SECOND * float(host["time_scale"])) % 1440
        diff = abs((expected - host["clock"] + 720) % 1440 - 720)
        spread.append((n, diff))
    check("clocks agree (day/night in sync)", all(d < 3.0 for _, d in spread),
          ", ".join(f"{n}:{d:.2f}min" for n, d in spread))
    samples = host["light_samples"]
    darkest = min(samples, key=lambda s: s[2] + s[3] + s[4])
    brightest = max(samples, key=lambda s: s[2] + s[3] + s[4])
    check("day/night cycle changes the light", (brightest[2] + brightest[3] + brightest[4]) - (darkest[2] + darkest[3] + darkest[4]) > 1.0,
          f"brightest {brightest[2:]} at t={brightest[0]:.0f}s, darkest {darkest[2:]} at t={darkest[0]:.0f}s")
    cave = [s for s in rep["Bot2"]["light_samples"] if s[1] == "mossmouth"][4:]   # skip the fade-in
    cave_range = max(sum(s[2:5]) for s in cave) - min(sum(s[2:5]) for s in cave) if cave else 99
    check("underground zone stays dim through day and night", cave and cave_range < 0.2,
          f"Mossmouth light range {cave_range:.3f} over {len(cave)} samples")

    # Inventory and item wheel
    problems = []
    for n in final:
        a = host["host"]["avatars"].get(ids[n])
        if a is None:
            problems.append(f"host lost {n}")
            continue
        if a["inv"] != rep[n]["inventory"] or a["wheel"] != rep[n]["wheel"]:
            problems.append(f"{n} bag differs")
        if a["slot"] != rep[n]["selected"]:
            problems.append(f"{n} wheel slot {rep[n]['selected']} vs host {a['slot']}")
    check("bags and item wheels match the host's copy for every player", not [p for p in problems if "bag" in p or "lost" in p], "; ".join(problems))
    check("item wheel choices reach the host", not [p for p in problems if "wheel" in p],
          ", ".join(f"{n} holds {rep[n]['held'] or 'nothing'}" for n in final))

    # ---- Light and darkness
    def bright(sample):
        return (sample[2] + sample[3] + sample[4]) / 3.0
    night = [x for x in host["light_samples"] if x[1] == "middlemost" and (x[5] >= 21 * 60 or x[5] < 4 * 60)]
    dark = min((bright(x) for x in night), default=1.0)
    check("nights are actually dark outdoors", night and dark < 0.12,
          f"Middlemost at night: brightness {dark:.2f} of 1.0 ({len(night)} samples)")
    deep = [bright(x) for x in rep["Bot2"]["light_samples"] if x[1] == "mossmouth"][4:]
    check("underground is dark at every hour", deep and max(deep) < 0.12,
          f"Mossmouth brightness {min(deep):.2f}-{max(deep):.2f} over {len(deep)} samples" if deep else "no samples")
    lit = {n: rep[n]["combat"]["night_lit_s"] / max(rep[n]["combat"]["night_s"], 0.01) for n in final}
    # Host farms bareheaded in random rain (its torch goes out and stays out until relit) and
    # Bot3 swaps the torch for a Pot Lid until late, so only these three are expected to stay lit:
    # Bot1 relit its torch and wears a raincoat, Bot2 has a lantern and a headlamp, Late is underground.
    carriers = ["Bot1", "Bot2", "Late"]
    check("rain-proof lights stay lit in the dark (raincoat torch, lantern, headlamp)", all(lit[n] > 0.9 for n in carriers),
          ", ".join(f"{n} lit {lit[n] * 100:.0f}% of {rep[n]['combat']['night_s']:.0f}s dark" for n in final))
    hlog = (out / "Host.log").read_text(errors="replace")
    snuffed = "Host's torch went out in the rain" in hlog
    relit = "Host relit their torch" in hlog
    check("rain put out a torch and it was relit at a campfire", snuffed and relit, f"went out={snuffed}, relit={relit}")
    b2 = host["host"]["avatars"][ids["Bot2"]]
    oil = sum(sl[1] for sl in b2["inv"] + b2["wheel"] if sl and sl[0] == "oil")
    check("the lantern burns oil", b2["equip"]["offhand"] == "lantern" and (b2["fuel"] < 100 or oil < 2),
          f"Bot2 holds {b2['equip']['offhand']}, fuel {b2['fuel']:.0f}%, oil left {oil}")

    # ---- Enemies and combat
    kinds = sorted({k for z in host["host"]["enemies"].values() for k in z})
    check("several enemy types roam the zones", len(kinds) >= 4,
          "; ".join(f"{z}: " + ", ".join(f"{k} x{c}" for k, c in sorted(v.items())) for z, v in host["host"]["enemies"].items()))
    seen = {n: sorted(rep[n]["enemy_kinds_seen"]) for n in final}
    check("players see their zone's enemy types", "frost_wilt" in seen["Late"] and any(k in seen["Bot3"] for k in ("boar", "puffcap")),
          "; ".join(f"{n}: {', '.join(v) or '-'}" for n, v in seen.items()))
    tele = {n: rep[n]["telegraphs_in"] for n in final}
    check("attack telegraphs reach the players who can see them", tele["Bot3"] >= 1 and sum(tele.values()) >= 3,
          ", ".join(f"{n}:{v}" for n, v in tele.items()))
    c3 = rep["Bot3"]["combat"]
    check("the fighter blocked or dodged telegraphed attacks", c3["blocked"] + c3["dodged"] >= 1,
          f"Bot3: blocked {c3['blocked']} (perfect {c3['perfect']}), dodged {c3['dodged']}, hit {c3['hits']}, dashes {c3['dashes']}")
    check("the fighter moved one way while aiming another", c3["strafe_s"] > 1.0, f"{c3['strafe_s']:.1f}s strafing")
    late_log = " | ".join(rep["Late"].get("bot_log", []))
    check("a frozen enemy was thawed with the torch", "jabbed a frozen frost_wilt" in late_log, late_log[-140:])
    hp_bad = [f"{n} {rep[n]['vitals'].get('hp')} vs host {host['host']['avatars'][ids[n]]['hp']}" for n in final
              if rep[n]["vitals"].get("hp") != host["host"]["avatars"][ids[n]]["hp"]]
    check("hearts match the host's copy", len(hp_bad) <= 1,
          "; ".join(hp_bad) or ", ".join(f"{n} {rep[n]['vitals'].get('hp')}/{rep[n]['vitals'].get('max_hp')}" for n in final))

    # ---- Gear
    gear_bad = [n for n in final if rep[n]["equip"] != host["host"]["avatars"][ids[n]]["equip"]]
    check("equipped gear matches the host for every player", not gear_bad, ", ".join(gear_bad))
    order = ["helmet", "chest", "shoes", "offhand"]
    problems, pairs = [], 0
    for viewer in final:
        for pid, g in rep[viewer]["remote_gear"].items():
            target = by_id.get(pid)
            if target is None:
                continue
            pairs += 1
            want = [rep[target]["equip"].get(k, "") for k in order]
            if g["gear"] != want:
                problems.append(f"{viewer} sees {target} wearing {g['gear']}, really {want}")
    check("friends see each other's gear", pairs >= 2 and not problems, "; ".join(problems[:2]) or f"{pairs} viewer/friend pairs")
    b1 = host["host"]["avatars"][ids["Bot1"]]
    check("climber found the Wayfarer set in the canopy chest and wore it",
          [b1["equip"][k] for k in ("helmet", "chest", "shoes")] == ["leaf_hood", "raincoat", "wellies"] and "fern_chest" in b1["chests"],
          json.dumps(b1["equip"]))
    check("delver melted the ice, looted the Miner's set and wore it",
          [b2["equip"][k] for k in ("helmet", "chest", "shoes")] == ["miner_helmet", "overalls", "steel_toes"]
          and "ember_charm" in [b2["equip"][k] for k in ("trinket1", "trinket2", "trinket3")] and "moss_chest" in b2["chests"], json.dumps(b2["equip"]))
    ice = {n: rep[n]["ice"].get("mossmouth") for n in final}
    check("melted ice is the same for everyone", ice["Host"] and ice["Host"]["melted"] >= 1 and all(v == ice["Host"] for v in ice.values()),
          f"Mossmouth ice: {ice['Host']}")

    # ---- Lifts and movement
    two = re.search(r"works the canopy_lift: bottom -> top with (\d) aboard", hlog)
    check("the pulley lift carries several players at once", two and int(two.group(1)) >= 2,
          two.group(0) if two else "no canopy_lift ride up")
    called = re.search(r"works the deep_lift: bottom -> top with 0 aboard", hlog)
    down = re.search(r"works the deep_lift: top -> bottom with (\d) aboard", hlog)
    check("a lift can be called from the far end, then ridden", called and down, (called.group(0) + "; " + down.group(0)) if called and down else "")
    check("lift positions identical for everyone", all(rep[n]["lifts"] == host["lifts"] for n in final), json.dumps(host["lifts"]))
    # (Positions over the last 35 s: a rider may faint later and wake at the zone entrance.)
    ledge = [p for p in rep["Bot1"]["pos_log"] if p[1] > 2200 and p[2] < 580]
    shelf = [p for p in rep["Bot2"]["pos_log"] if p[2] > 1290]
    check("lift riders reached the other level (cliffs block the way otherwise)", ledge and shelf,
          f"Bot1 on the Canopy Ledge for {len(ledge) / 20:.1f}s, Bot2 on the Deep Shelf for {len(shelf) / 20:.1f}s")
    c1 = rep["Bot1"]["combat"]
    check("dashes spend stamina orbs", c1["dashes"] >= 2 and rep["Bot1"]["avatar"]["max_orbs"] >= 5,
          f"Bot1 dashed {c1['dashes']}x; orbs {rep['Bot1']['avatar']['stamina']:.1f}/{rep['Bot1']['avatar']['max_orbs']}")

    # Performance ("comfortably 5")
    rates = {n: rep[n]["snapshot_hz"] for n in final if n != "Host"}
    check("snapshot rate ~20 Hz for every client", all(r > 15 for r in rates.values()),
          ", ".join(f"{n}:{r:.1f}Hz" for n, r in rates.items()))
    rtts = {n: rep[n]["rtt_ms"] for n in final if n != "Host"}
    check("round trip time measured", all(r.get("n", 0) > 5 for r in rtts.values()),
          ", ".join(f"{n}: avg {r.get('avg', 0):.1f} / p95 {r.get('p95', 0):.1f} ms" for n, r in rtts.items()))
    h = host["host"]
    check("host frame time with 5 players", h["frame_ms_avg"] < 20.0, f"avg {h['frame_ms_avg']:.2f} ms, max {h['frame_ms_max']:.1f} ms over {h['frames']} frames")
    up = host["kbps_up"]
    down = max(rep[n]["kbps_down"] for n in final if n != "Host")
    check("bandwidth is small", up < 1500 and down < 400, f"host upload {up:.0f} kbit/s for 4 clients, client download <= {down:.0f} kbit/s")

    # Logs
    bad = []
    for n in names:
        text = (out / f"{n}.log").read_text(errors="replace")
        for line in text.splitlines():
            if "SCRIPT ERROR" in line or "Parse Error" in line or line.startswith("ERROR"):
                bad.append(f"{n}: {line.strip()[:120]}")
    check("no script errors in any log", not bad, "; ".join(bad[:3]))

    return save(out, checks, rep, label)


def run_save_test(args) -> int:
    """Solo world in slot 7: a bot farms, gears up, pins and meets Pepper; the world saves;
    a second run loads the slot and its report is compared with the first."""
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    for f in list(out.glob("*.json")) + list(out.glob("*.log")):
        f.unlink()
    base = [args.godot, "--headless", "--path", args.project, "--", "--solo", "--slot=7", "--name=Saver"]
    runs = [("Save1", ["--wipe-slot", "--bot", "--role=saver", "--report-at=16", "--save-at-report", f"--time-scale={args.time_scale}"]),
            ("Save2", ["--report-at=3", f"--time-scale={args.time_scale}"])]
    for name, extra in runs:
        with open(out / f"{name}.log", "w") as log:
            subprocess.run(base + [f"--report={out / (name + '.json')}"] + extra, stdout=log, stderr=subprocess.STDOUT, timeout=120)
    a, b = load(out, "Save1"), load(out, "Save2")
    checks = []

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": detail})
        print(("PASS  " if ok else "FAIL  ") + name + (f"   [{detail}]" if detail else ""))

    check("both runs wrote a report", a is not None and b is not None)
    if a is None or b is None:
        return save(out, checks, {}, args.label)
    check("the first run saved", a.get("saved") is True and a.get("solo") is True, f"saved={a.get('saved')}, solo={a.get('solo')}")
    log1 = (out / "Save1.log").read_text(errors="replace")
    log2 = (out / "Save2.log").read_text(errors="replace")
    check("the second run loaded the slot", "loaded save slot 7" in log2 and "loaded from the save" in log2,
          next((l for l in log2.splitlines() if "loaded save slot" in l), "no load line"))
    check("item wheel came back", b["wheel"] == a["wheel"], f"{[s[0] for s in b['wheel']]}")
    check("bag came back", b["inventory"] == a["inventory"])
    check("gear came back", b["equip"] == a["equip"] and b["equip"]["helmet"] == "pot_helmet", json.dumps(b["equip"]))
    check("crops came back", b["crops"]["middlemost"] == a["crops"]["middlemost"] and b["crops"]["middlemost"].split(",")[0] != "0",
          b["crops"]["middlemost"][:23] + "...")
    labels = sorted(p["label"] for p in b["pins"])
    check("pins came back", "Saved pin" in labels, ", ".join(labels))
    la, lb = a["vitals"].get("lesson", {}), b["vitals"].get("lesson", {})
    check("Pepper's lessons came back", lb.get("i") == la.get("i") and int(la.get("i", 0)) >= 2,
          f"lesson {lb.get('i')} ({lb.get('title')}), was {la.get('i')}")
    check("play time carries on", b["play_time"] >= a["play_time"], f"{a['play_time']:.1f}s then {b['play_time']:.1f}s")
    t_a = a["day"] * 1440 + a["clock"]
    t_b = b["day"] * 1440 + b["clock"]
    check("the clock carries on from the save", t_b >= t_a, f"day {a['day']} {a['clock']:.0f} -> day {b['day']} {b['clock']:.0f}")
    dist = math.dist(a["pos"], b["pos"])
    check("you're back where you stood", b["zone"] == a["zone"] and dist < 40.0, f"{a['zone']} {a['pos']} -> {b['zone']} {b['pos']}")
    bad = [l for l in (log1 + log2).splitlines() if "SCRIPT ERROR" in l or l.startswith("ERROR")]
    check("no script errors", not bad, "; ".join(bad[:2]))
    return save(out, checks, {}, args.label)


def run_lobby_test(args) -> int:
    """Sign-in and session regression (game/tests/lobby_tests.gd): a host and a joiner, each
    checking its own side of joining, Ready, starting, leaving, rejoining and the host's exit."""
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    for f in list(out.glob("*.json")) + list(out.glob("*.log")):
        f.unlink()
    port = str(int(args.port) + 35)
    base = [args.godot, "--headless", "--path", args.project, "--"]
    procs = {}
    logs = {}
    for name, extra, delay in [("LobbyHost", ["--host", f"--port={port}", "--lobby-test=host", "--name=Host"], 0.0),
                               ("LobbyJoin", [f"--join=127.0.0.1", f"--port={port}", "--lobby-test=join", "--name=Joiner"], 1.5)]:
        time.sleep(delay)
        logs[name] = open(out / f"{name}.log", "w")
        procs[name] = subprocess.Popen(base + extra, stdout=logs[name], stderr=subprocess.STDOUT)
    codes = {}
    for name, p in procs.items():
        try:
            codes[name] = p.wait(timeout=150)
        except subprocess.TimeoutExpired:
            p.kill()
            codes[name] = -1
        logs[name].close()
    checks = []
    for name in ["LobbyHost", "LobbyJoin"]:
        for line in (out / f"{name}.log").read_text(errors="replace").splitlines():
            if line.startswith(("PASS  ", "FAIL  ")):
                ok = line.startswith("PASS")
                body = line[6:]
                detail = ""
                if "   [" in body:
                    body, detail = body.split("   [", 1)
                    detail = detail.rstrip("]")
                checks.append({"check": body, "ok": ok, "detail": detail})
                print(line)
        checks.append({"check": f"{name} finished cleanly", "ok": codes[name] == 0, "detail": f"exit code {codes[name]}"})
        print(("PASS  " if codes[name] == 0 else "FAIL  ") + f"{name} finished cleanly   [exit code {codes[name]}]")
    return save(out, checks, {}, args.label)


def run_scenarios(args) -> int:
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    for f in list(out.glob("*.json")) + list(out.glob("*.log")):
        f.unlink()
    port = args.port
    join_port = port
    proxy = None
    if args.lag > 0 or args.loss > 0:
        join_port = str(int(port) + 13)
        here = Path(__file__).resolve().parent
        proxy = subprocess.Popen([sys.executable, str(here / "lag_proxy.py"), "--listen", join_port, "--host-port", port,
                                  "--delay", str(args.lag), "--jitter", str(args.jitter), "--loss", str(args.loss), "--seconds", "400"],
                                 stdout=open(out / "proxy.log", "w"), stderr=subprocess.STDOUT)
        time.sleep(0.5)
    base = [args.godot, "--headless", "--path", args.project, "--"]
    hlog = open(out / "Host.log", "w")
    host = subprocess.Popen(base + ["--host", "--test", "--autostart=2", "--weather-period=999", f"--time-scale={args.time_scale}",
                                    "--name=Host", f"--port={port}"], stdout=hlog, stderr=subprocess.STDOUT)
    time.sleep(1.5)
    tlog = open(out / "Tester.log", "w")
    tester = subprocess.Popen(base + [f"--join=127.0.0.1", f"--port={join_port}", f"--scenario={args.scenarios}", "--name=Tester",
                                      f"--report={out / 'Tester.json'}", "--report-at=380", "--linger=0.5"],
                              stdout=tlog, stderr=subprocess.STDOUT)
    t0 = time.time()
    try:
        tester.wait(timeout=420)
    except subprocess.TimeoutExpired:
        tester.kill()
    host.kill()
    host.wait()
    if proxy is not None:
        proxy.terminate()
    hlog.close()
    tlog.close()
    print(f"scenarios finished after {time.time() - t0:.0f}s\n")
    rep = load(out, "Tester") or {}
    results = rep.get("scenarios", {})
    checks = []
    for name, r in results.items():
        checks.append({"check": name, "ok": r["ok"], "detail": r["detail"]})
        print(("PASS  " if r["ok"] else "FAIL  ") + name + f"   [{r['detail']}]")
    if not rep.get("scenarios_done"):
        checks.append({"check": "all scenarios finished", "ok": False, "detail": f"{len(results)} ran"})
        print(f"FAIL  all scenarios finished   [{len(results)} ran]")
    bad = []
    for n in ("Host", "Tester"):
        for line in (out / f"{n}.log").read_text(errors="replace").splitlines():
            if "SCRIPT ERROR" in line or "Parse Error" in line or line.startswith("ERROR"):
                bad.append(f"{n}: {line.strip()[:120]}")
    checks.append({"check": "no script errors in either log", "ok": not bad, "detail": "; ".join(bad[:3])})
    print(("PASS  " if not bad else "FAIL  ") + "no script errors in either log" + (f"   [{'; '.join(bad[:3])}]" if bad else ""))
    passed = sum(c["ok"] for c in checks)
    print(f"\n{passed}/{len(checks)} scenario checks passed ({args.label})")
    (out / "summary.json").write_text(json.dumps({"label": args.label, "passed": passed, "total": len(checks), "checks": checks}, indent=2))
    return 0 if passed == len(checks) else 1


def path_distance(log, p, t0, t1):
    """Distance from point p to the path a player actually walked between t0 and t1."""
    pts = [(s[1], s[2]) for s in log if t0 - 0.05 <= s[0] <= t1 + 0.05]
    if not pts:
        return float("inf")
    if len(pts) == 1:
        return math.dist(p, pts[0])
    best = float("inf")
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        dx, dy = bx - ax, by - ay
        L = dx * dx + dy * dy
        u = 0.0 if L == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L))
        best = min(best, math.dist(p, (ax + u * dx, ay + u * dy)))
    return best


def closest(target_rep, seen, t, window):
    """How far what a viewer saw is from where the target really was during the last
    `window` seconds before the viewer's report (updates take a moment to arrive)."""
    near = [math.dist(seen, s[1:]) for s in target_rep["pos_log"] if t - window <= s[0] <= t + 0.05]
    return min(near) if near else math.dist(seen, target_rep["pos"])


def _subseq(seq, pattern):
    i = 0
    for x in seq:
        if i < len(pattern) and x == pattern[i]:
            i += 1
    return i == len(pattern)


def save(out, checks, rep, label):
    passed = sum(c["ok"] for c in checks)
    print(f"\n{passed}/{len(checks)} checks passed ({label})")
    (out / "summary.json").write_text(json.dumps({"label": label, "passed": passed, "total": len(checks), "checks": checks}, indent=2))
    return 0 if passed == len(checks) else 1


if __name__ == "__main__":
    sys.exit(main())
