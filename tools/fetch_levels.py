#!/usr/bin/env python3
"""Download PR2 levels from the server into a local folder for tools/clip_sweep.sh.

Each level is saved exactly as the server sends it (`{id}.txt`), which is the
same payload the game itself loads, so the sweep decodes it with the game's own
LevelDataClient/LevelDecoder.

Examples:
  tools/fetch_levels.py                          # campaign + best + best this week + newest
  tools/fetch_levels.py --lists campaign         # only the campaign
  tools/fetch_levels.py --ids 50815,1234567      # specific levels
  tools/fetch_levels.py --id-range 1000:2000     # every id in a range (slow; be polite)

Already-downloaded levels are skipped, so the command can be re-run to resume.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

# Mirrors ServerConfig.DEFAULT_HOST / listUrl / levelDataUrl.
DEFAULT_HOST = "https://pr2hub.com"
DEFAULT_LISTS = "campaign,best,best_week,newest"
# The lobby shows 9 pages per list; the campaign has 6.
DEFAULT_PAGES = {"campaign": 6}
DEFAULT_PAGE_COUNT = 9


def get(url, timeout):
    request = urllib.request.Request(url, headers={"User-Agent": "pr2-clip-sweep/1.0"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")


def list_levels(host, mode, page, timeout):
    """(level_id, version, title) for one page of a level list."""
    body = get(f"{host}/files/lists/{mode}/{page}", timeout)
    data = json.loads(body)
    return [(int(e["level_id"]), int(e.get("version", 1)), e.get("title", "")) for e in data.get("levels", [])]


def parse_range(value):
    start, end = value.split(":")
    return range(int(start), int(end) + 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default=DEFAULT_HOST)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser.add_argument("--out", default=os.path.join(repo_root, "test", "output", "levels"),
                        help="folder to save levels in (default: test/output/levels in the repo)")
    parser.add_argument("--lists", default=DEFAULT_LISTS, help="comma-separated lists (default: %(default)s); '' for none")
    parser.add_argument("--pages", type=int, default=0, help="pages per list (default: 6 for campaign, 9 otherwise)")
    parser.add_argument("--ids", default="", help="comma-separated level ids to fetch as well")
    parser.add_argument("--id-range", default="", help="fetch every id in START:END (inclusive)")
    parser.add_argument("--delay", type=float, default=0.5, help="seconds between requests (default: %(default)s)")
    parser.add_argument("--timeout", type=float, default=20)
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    wanted = {}  # level_id -> version

    for mode in [m for m in args.lists.split(",") if m]:
        pages = args.pages or DEFAULT_PAGES.get(mode, DEFAULT_PAGE_COUNT)
        for page in range(1, pages + 1):
            try:
                entries = list_levels(args.host, mode, page, args.timeout)
            except (urllib.error.URLError, OSError, ValueError, KeyError) as error:
                print(f"list {mode} page {page}: {error}", file=sys.stderr)
                break
            print(f"list {mode} page {page}: {len(entries)} levels")
            for level_id, version, _title in entries:
                wanted[level_id] = max(version, wanted.get(level_id, 0))
            if not entries:
                break
            time.sleep(args.delay)

    for part in [p for p in args.ids.split(",") if p.strip()]:
        wanted.setdefault(int(part), 1)
    if args.id_range:
        for level_id in parse_range(args.id_range):
            wanted.setdefault(level_id, 1)

    fetched = skipped = failed = 0
    for level_id in sorted(wanted):
        path = os.path.join(args.out, f"{level_id}.txt")
        if os.path.exists(path):
            skipped += 1
            continue
        url = f"{args.host}/levels/{level_id}.txt?version={wanted[level_id]}"
        try:
            body = get(url, args.timeout)
        except (urllib.error.URLError, OSError) as error:
            # Deleted or unpublished ids are expected in --id-range scans.
            print(f"level {level_id}: {error}", file=sys.stderr)
            failed += 1
            time.sleep(args.delay)
            continue
        if "data=" not in body:
            failed += 1
        else:
            with open(path, "w", encoding="utf-8") as f:
                f.write(body)
            fetched += 1
            print(f"level {level_id}: saved")
        time.sleep(args.delay)

    print(f"done: {fetched} downloaded, {skipped} already present, {failed} failed -> {args.out}")


if __name__ == "__main__":
    main()
