# Nextcloud

Self-hosted file storage and sync — Google Drive replacement. Integrated with Ollama for AI-powered document search and summarization.

Accessible at: https://files.jasonfagerberg.duckdns.org

## Stack

- **Nextcloud** — web UI, file sync, desktop/mobile clients
- **PostgreSQL** — database
- **Redis** — caching

## AI Integration

Uses the Nextcloud Assistant app connected to Ollama (`gpt-oss-20b-64k`) for:
- Document summarization
- Natural language file search
- Draft generation
