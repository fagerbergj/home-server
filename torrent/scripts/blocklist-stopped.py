#!/usr/bin/env python3
"""Blocklist stoppedDL qBittorrent torrents in Sonarr/Radarr and re-search.

After running stop-stuck.py to park dead-swarm torrents, those magnet links
are still in Sonarr/Radarr's queue. This script:

  1. Reads stoppedDL hashes from qBittorrent
  2. Finds matching items in Sonarr and Radarr queues
  3. Removes them from the download client + adds the release to the
     blocklist + triggers a fresh search for a replacement

The blocklist prevents Sonarr/Radarr from grabbing the same dead release
again on the next search.

Usage:
  blocklist-stopped.py [--apply] [--qbit-url URL] [--sonarr-url URL] [--radarr-url URL]

Required env vars:
  SONARR_API_KEY    Sonarr API key (Settings > General)
  RADARR_API_KEY    Radarr API key (Settings > General)

Optional env vars (only needed if qBit's IP-bypass list excludes the host):
  QBIT_USERNAME     qBittorrent WebUI username
  QBIT_PASSWORD     qBittorrent WebUI password

Options:
  --apply           Actually delete + blocklist (default: dry run)
  --qbit-url URL    qBittorrent WebUI URL (default: http://localhost:8080)
  --sonarr-url URL  Sonarr URL (default: http://localhost:8989)
  --radarr-url URL  Radarr URL (default: http://localhost:7878)
  --no-redownload   Skip the auto-search after blocklisting

Examples:
  export SONARR_API_KEY=xxx RADARR_API_KEY=yyy
  blocklist-stopped.py                          # dry run
  blocklist-stopped.py --apply                  # blocklist + re-search
  blocklist-stopped.py --apply --no-redownload  # blocklist only, no re-search
"""

import argparse
import http.cookiejar
import json
import os
import sys
import urllib.parse
import urllib.request


def qbit_opener(base_url):
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


def arr_call(base, key, path, method="GET"):
    req = urllib.request.Request(f"{base}{path}", method=method,
                                 headers={"X-Api-Key": key})
    return urllib.request.urlopen(req).read()


def process_arr(name, base, key, hashes, apply_changes, redownload):
    try:
        q = json.loads(arr_call(base, key, "/api/v3/queue?pageSize=2000"))
    except Exception as e:
        print(f"\n{name}: ERROR fetching queue: {e}")
        return

    matches = [r for r in q.get("records", [])
               if r.get("downloadId", "").lower() in hashes]
    print(f"\n{name}: {len(matches)} queue items match stoppedDL hashes")
    if not matches:
        return

    for r in matches[:10]:
        title = (r.get("title")
                 or (r.get("series") or {}).get("title")
                 or (r.get("movie") or {}).get("title")
                 or "(unknown)")
        print(f"  - {title[:80]}")
    if len(matches) > 10:
        print(f"  ... and {len(matches) - 10} more")

    if not apply_changes:
        return

    skip = "false" if redownload else "true"
    failed = 0
    for r in matches:
        path = (f"/api/v3/queue/{r['id']}"
                f"?removeFromClient=true&blocklist=true&skipRedownload={skip}")
        try:
            arr_call(base, key, path, method="DELETE")
        except Exception as e:
            failed += 1
            print(f"  WARN: failed for id={r['id']}: {e}")

    ok = len(matches) - failed
    print(f"  Blocklisted {ok}/{len(matches)} releases (re-search: {redownload}).")


def main():
    p = argparse.ArgumentParser(
        description="Blocklist stoppedDL torrents in Sonarr/Radarr.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("Usage:", 1)[1] if "Usage:" in __doc__ else None,
    )
    p.add_argument("--apply", action="store_true", help="Actually blocklist (default: dry run)")
    p.add_argument("--qbit-url", default="http://localhost:8080")
    p.add_argument("--sonarr-url", default="http://localhost:8989")
    p.add_argument("--radarr-url", default="http://localhost:7878")
    p.add_argument("--no-redownload", action="store_true",
                   help="Skip auto-search after blocklisting")
    args = p.parse_args()

    sonarr_key = os.environ.get("SONARR_API_KEY")
    radarr_key = os.environ.get("RADARR_API_KEY")
    if not (sonarr_key or radarr_key):
        print("Error: set SONARR_API_KEY and/or RADARR_API_KEY env vars",
              file=sys.stderr)
        sys.exit(1)

    print(f"Querying {args.qbit_url} ...")
    try:
        opener = qbit_opener(args.qbit_url)
        torrents = qbit_get(opener, args.qbit_url, "/api/v2/torrents/info?filter=stopped")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    hashes = {t["hash"].lower() for t in torrents if t["state"] == "stoppedDL"}
    print(f"Found {len(hashes)} stoppedDL torrents in qBittorrent")
    if not hashes:
        return

    redownload = not args.no_redownload
    if sonarr_key:
        process_arr("Sonarr", args.sonarr_url, sonarr_key, hashes,
                    args.apply, redownload)
    if radarr_key:
        process_arr("Radarr", args.radarr_url, radarr_key, hashes,
                    args.apply, redownload)

    if not args.apply:
        print("\nDry run. Pass --apply to execute.")


if __name__ == "__main__":
    main()
