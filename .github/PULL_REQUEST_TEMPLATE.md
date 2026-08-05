<!-- Conventional-commit title: feat(scope): … / fix(scope): … / docs(scope): … -->

## What & why

<!-- One or two lines: what changed and the motivation. The story goes here, not in the source. -->

Closes #

## Spec (non-trivial changes)

<!-- Skip for a trivial fix. Otherwise summarize, or link the issue's spec:
- **Scope / out of scope** -
- **Forbidden actions** -
- **Output contract** -
- **Test cases** - the 2–3 concrete cases now covered by tests -->

## Checklist

- [ ] `docker compose config` parses for every compose file touched
- [ ] Image tags are pinned to a release, not `:latest`, unless auto-update is intended
- [ ] Secrets come from `.env` / mounted files - none committed
- [ ] Deployed and verified on the server, not just edited here
- [ ] Comments say what the config *can't* - the non-obvious constraint, not the obvious setting
