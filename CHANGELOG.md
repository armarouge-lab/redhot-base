# Changelog — redhot-base

## [0.1.0] — Phase 1 skeleton (On-Rails)

- Four-ring D layout (`entry`, `domain`, `services`, `infra`).
- `scripts/ensure-base.sh` — XDG directory bootstrap.
- `libredhot.a` build target (Makefile).
- Flat KV parser contract in `domain.d`.
- Atomic write + `flock` contract in `infra.d`.
- Contract tests placeholder in `tests/contract.d`.
