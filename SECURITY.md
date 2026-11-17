# SECURITY — redhot-base

## Protected assets
- `~/.config/redhot/*` (user configuration, 0700)
- `~/.local/state/redhot/*` (shared state, 0700)
- `/usr/local/lib/redhot/*` (runtime libraries, 0644/0755)

## Adversaries in scope
- Local unprivileged processes injecting via `siren.fifo` or racing state
  files. Mitigated by `0600`/`0700` permissions, `PIPE_BUF` (512 bytes),
  and exclusive `flock(2)`.
- Malicious filenames containing shell metacharacters passed between
  Dragonet → Imp → external players. Mitigated by passing arguments via
  `execve` arrays, never `/bin/sh -c`.
- Privilege escalation during `redhot-wizard` execution. Mitigated by
  running the X11 UI unprivileged and isolating administrative copies
  via `doas`/`sudo`.

## Out of scope
- Pre-existing root compromise, physical access, third-party rendering
  engines (WebKit2GTK, MPV).
