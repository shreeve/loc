# HANDOFF: where loc and loco stand

The resume point for anyone, human or agent. Read it first, then
[AGENTS.md](AGENTS.md) (the rules) and [rig/DESIGN.md](rig/DESIGN.md)
(loco's design and measurements).

## Current state

- **Branches:** `main` is the only branch, pushed to `origin`
  (`shreeve/loc`), with no worktrees. `upstream` is
  `philiplindberg/loc`, the Rust original.
- **loco is complete.** It passes all of `SPEC.md`'s fixtures, the 51
  checks of `rig/test.sh`, the 7 unit tests, and the light gate's 122
  byte comparisons with the Rust loc (GREEN). Its output differs from
  the Rust's only where DESIGN.md says, each pinned by a check.
- **Speed** (DESIGN.md's table, Rust → loco):
  - large trees: 0.50x to 0.65x the Rust's time. On trig's 125,000
    files, 1,881 ms → 1,216 ms, and 3,377 → 1,692 with `--jobs=1`.
  - the walk alone: 0.57x. One language (`-l python`): 0.52x.
  - the scanner: 0.80x to 0.83x.
  - 20,000 files as PATHs: 0.80x, since the PATHs are checked on
    16 tasks.
  - small trees: about 2 ms slower (5–13 ms runs), from starting
    Rig's workers and a pool hop per file call.
- **Toolchain:** Rig at main 6c3f35b78 or later, Zig 0.17.0.
- **Website:** `website/` holds the product page;
  `.github/workflows/pages.yml` publishes it when `website/` changes on
  `main`. GitHub Pages must be set to deploy from GitHub Actions
  (Settings → Pages → Source) once, by the owner.

## What is left

loco has no open work. Its remaining gap, small trees, is in Rig's
runtime:

- **Worker start:** Rig starts every worker at the first task, about
  0.6 ms per run.
- **The pool hop per file call:** a wake, a switch, and a wake back.
  Running calls inline on an idle worker was built and measured (Rig
  PR #689, closed). loco did not gain, since its calls nearly always find
  other work queued, and the owner declined it
  (`docs/history/records/2026-10/consolidation-2/inline-idle.md` in Rig).
- **Allocator:** large blocks are reused only at their exact size. loco
  peaks at 231 MB against Rust's 46 MB on 9,000 files; this shows in
  memory, not in time on this Mac.

These are Rig's to change. After any Rig change to the scheduler, the
pool, the allocator, or `std.file`, run loco's light gate with that Rig
and the speed table's rows.

## Resuming

```
rig/build.sh && rig/test.sh && rig test rig/loc   # loco
cargo test                                        # the Rust loc
rig/tools/light RIG=/path/to/bin/rig              # the gate
```

Benchmarks: interleave the Rust's `target/release/loc` and `bin/loco`,
take the fastest of 7, and note `uptime`'s load, which moves every
number. The first loco run after a large trig run reads a colder file
cache; run both orders.
