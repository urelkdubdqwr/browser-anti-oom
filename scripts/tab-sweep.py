#!/usr/bin/python3
"""Tab hygiene for persistent Chrome daemons.

Renderer tab leaks are the #1 RAM killer on a long-lived daemon: a job that
opens a tab and never closes it leaves a whole renderer behind. Measured on a
4 GB VPS: one daemon with 57 leaked tabs = 815 MB RSS, and *other* jobs then
die with "Target crashed" because memory ran out mid-run. Flags don't fix this;
tab hygiene does.

Usage:
  tab-sweep.py                      # sweep every --ports daemon, keep 2 tabs
  tab-sweep.py --port 9447 --keep 1 # one daemon, keep only the newest tab
  tab-sweep.py --list               # just print tab counts, close nothing

Exit 0 always (cron-friendly); prints one line per daemon touched.
NEVER closes the last page of a daemon — doing that kills the browser itself.
"""
import argparse, json, os, sys, urllib.request

PORTS_DEFAULT = os.environ.get("BROWSER_CDP_PORTS", "9222,9223")


def pages(port):
    url = f"http://127.0.0.1:{port}/json/list"
    data = json.load(urllib.request.urlopen(url, timeout=6))
    return [t for t in data if t.get("type") == "page"]


def sweep(port, keep, dry):
    try:
        ps = pages(port)
    except Exception as e:
        print(f":{port} unreachable ({type(e).__name__})")
        return
    if len(ps) <= keep:
        print(f":{port} ok {len(ps)}/{keep}")
        return
    victims = ps[: len(ps) - keep]  # CDP lists oldest first
    if dry:
        print(f":{port} would close {len(victims)}/{len(ps)} (keep {keep})")
        return
    n = 0
    for t in victims:
        try:
            urllib.request.urlopen(
                f"http://127.0.0.1:{port}/json/close/{t['id']}", timeout=6
            ).read()
            n += 1
        except Exception:
            pass
    print(f":{port} closed {n}/{len(ps)} (keep {keep})")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ports", default=PORTS_DEFAULT, help="comma-separated CDP ports")
    ap.add_argument("--port", type=int, help="single port (overrides --ports)")
    ap.add_argument("--keep", type=int, default=2, help="newest tabs kept per daemon")
    ap.add_argument("--list", action="store_true", help="report only, close nothing")
    a = ap.parse_args()
    ports = [a.port] if a.port else [int(p) for p in a.ports.split(",") if p.strip()]
    keep = max(1, a.keep)  # keep>=1: closing the last page kills the browser
    for p in ports:
        sweep(p, keep, a.list)
    return 0


if __name__ == "__main__":
    sys.exit(main())
