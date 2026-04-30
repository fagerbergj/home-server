# Audiobookshelf Setup

## First Run

```bash
mkdir -p /mnt/media/audiobooks
docker compose up -d
```

## NPM Proxy Host

Add a proxy host in NPM (http://\<server-local-ip\>:81):

| Field | Value |
|-------|-------|
| Domain | `books.jasonfagerberg.duckdns.org` |
| Scheme | `http` |
| Forward Hostname | `<server-local-ip>` |
| Forward Port | `13378` |
| SSL | Enable, use existing wildcard cert |

## Adding Audiobooks

Drop files into `/mnt/media/audiobooks` then add the library in the UI at `https://books.jasonfagerberg.duckdns.org`.
