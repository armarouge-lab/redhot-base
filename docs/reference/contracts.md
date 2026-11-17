# redhot-base — Behavioural Contracts

## Flat KV parser
- `key.subkey = value`
- `#` starts a comment
- first `=` splits
- `~/` expands to `$HOME` at resolution time

## Precedence
1. CLI flag
2. `$REDHOT_CONFIG`
3. `~/.config/redhot/<app>.conf`
4. `/etc/redhot/redhot.conf`
5. compiled-in defaults

## Atomic write
`flock` → `mkstemp` → write → `fsync` → `rename` → `fsync(parent)`

## Siren FIFO
`<level>|<app>|<title>|<message>\n` — max 512 bytes, `O_NONBLOCK`,
fail silent on `ENXIO`.

## Exit codes
| Code | Name |
|---|---|
| 0 | EX_OK |
| 1 | EX_RUNTIME |
| 2 | EX_USAGE |
| 3 | EX_CONFIG |
| 4 | EX_IOERR |
| 5 | EX_PRECOND |
| 6 | EX_SECURITY |
| 7 | EX_CANCELED |
| 8 | EX_NO_HANDLER |
| 64 | EX_INTERNAL |
