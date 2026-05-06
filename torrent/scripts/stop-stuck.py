#!/usr/bin/env python3
"""Stop qBittorrent torrents that have been stuck downloading metadata.

Many torrents queued by Sonarr/Radarr backfill are magnet links pointing to
swarms with no peers holding the metadata. They sit in metaDL state
indefinitely, eating active-download slots and starving real downloads.

This script identifies metaDL torrents older than a threshold and stops
them so their slots free up.

Usage:
  stop-stuck.py [--apply] [--threshold SECONDS] [--qbit-url URL] [--delete]

Options:
  --apply              Actually stop torrents (default is dry run)
  --threshold SECONDS  Minimum metaDL age to stop (default: 3600 = 1 hour)
  --qbit-url URL       qBittorrent WebUI URL (default: http://localhost:8080)
  --delete             Delete instead of stop (irreversible)

Optional env vars (only needed if qBit's IP-bypass list excludes the host):
  QBIT_USERNAME        qBittorrent WebUI username
  QBIT_PASSWORD        qBittorrent WebUI password

Examples:
  stop-stuck.py                              # dry run, default 1h threshold
  stop-stuck.py --apply                      # stop torrents stuck >1h
  stop-stuck.py --apply --threshold 7200     # stop torrents stuck >2h
  stop-stuck.py --apply --delete             # delete instead of stop
"""

import argparse
import http.cookiejar
import json
import os
import sys
import time
import urllib.parse
import urllib.request


def build_opener(base_url):
    """Return a urllib opener with cookie jar; logs in if credentials are set."""
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    user = os.environ.get("QBIT_USERNAME")
    pw = os.environ.get("QBIT_PASSWORD")
    if user and pw:
        body = urllib.parse.urlencode({"username": user, "password": pw}).encode()
        req = urllib.request.Request(f"{base_url}/api/v2/auth/login", data=body)
        resp = opener.open(req).read().decode()
        if resp.strip() != "Ok.":
            raise RuntimeError(f"qBit login failed: {resp!r}")
    return opener


def qbit_get(opener, base_url, path):
    return json.loads(opener.open(f"{base_url}{path}").read())


def qbit_post(opener, base_url, path, data):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(f"{base_url}{path}", data=body, method="POST")
    opener.open(req).read()


def main():
    p = argparse.ArgumentParser(
        description="Stop stuck metaDL torrents in qBittorrent.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("Usage:", 1)[1] if "Usage:" in __doc__ else None,
    )
    p.add_argument("--apply", action="store_true", help="Actually stop (default: dry run)")
    p.add_argument("--threshold", type=int, default=3600,
                   help="Min metaDL age in seconds (default: 3600)")
    p.add_argument("--qbit-url", default="http://localhost:8080",
                   help="qBit WebUI URL (default: http://localhost:8080)")
    p.add_argument("--delete", action="store_true",
                   help="Delete instead of stop (irreversible)")
    args = p.parse_args()

    print(f"Querying {args.qbit_url} ...")
    try:
        opener = build_opener(args.qbit_url)
        torrents = qbit_get(opener, args.qbit_url, "/api/v2/torrents/info?filter=downloading")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    now = time.time()
    stuck = [t for t in torrents
             if t["state"] == "metaDL" and (now - t["added_on"]) > args.threshold]

    print(f"Found {len(stuck)} metaDL torrents older than {args.threshold}s")
    if not stuck:
        return

    for t in stuck[:10]:
        age_h = (now - t["added_on"]) / 3600
        name = t.get("name") or t["hash"][:8]
        print(f"  {age_h:5.1f}h  {name[:70]}")
    if len(stuck) > 10:
        print(f"  ... and {len(stuck) - 10} more")

    if not args.apply:
        print("\nDry run. Pass --apply to execute.")
        return

    hashes = "|".join(t["hash"] for t in stuck)
    if args.delete:
        qbit_post(opener, args.qbit_url, "/api/v2/torrents/delete",
                  {"hashes": hashes, "deleteFiles": "true"})
        print(f"\nDeleted {len(stuck)} torrents.")
    else:
        qbit_post(opener, args.qbit_url, "/api/v2/torrents/stop", {"hashes": hashes})
        print(f"\nStopped {len(stuck)} torrents (state -> stoppedDL).")


if __name__ == "__main__":
    main()
