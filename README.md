# redhot-base

Foundation layer of the Redhot Suite (Cycle 1.0, Phase 1).

**Language:** D (LDC) for `libredhot.a`; Java 17 for `redhot-core.jar`.
**Philosophy:** On-Rails v1.0 — four unidirectional rings.
**Targets:** FreeBSD x86_64 and Debian-based Linux (MiniOS Flux).

## Build

    make clean && make
    make test

## Layout (On-Rails)

    src/entry.d      Ring 1 — CLI parsing, signals
    src/domain.d     Ring 2 — pure logic, Flat KV parser, exit codes
    src/services.d   Ring 3 — XDG paths, theme loader, state files
    src/infra.d      Ring 4 — flock, atomic write, Siren FIFO

## Contracts

See `docs/reference/contracts.md` for the full behavioural contract.
