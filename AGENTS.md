# AGENTS.md: rules for working in this repository

Read [HANDOFF.md](HANDOFF.md) first for where things stand.

## What is here

- **loc**, in Rust (`src/`, `tests/`, `Cargo.*`): the original, by Philip
  Lindberg ([philiplindberg/loc](https://github.com/philiplindberg/loc),
  MIT), which this repository forks.
- **loco**, the same program in [Rig](https://github.com/shreeve/rig)
  (`rig/`), built as `bin/loco`. [rig/DESIGN.md](rig/DESIGN.md) is its
  design and its measurements.
- **The website** (`website/`): one static page, written in
  [Rip](https://github.com/shreeve/rip) and styled with Tailwind,
  published to GitHub Pages by `.github/workflows/pages.yml`.
  [website/README.md](website/README.md) says how to preview and update it.
- **The rules** both programs follow: [SPEC.md](SPEC.md), and the four
  expected documents in `fixtures/`.

## Rules

1. **The Rust code is not changed.** `src/`, `tests/`, `Cargo.toml` and
   `Cargo.lock` stay as upstream has them; loco sits beside them.
2. **The expected documents are the authority.** A disagreement is a bug
   in the program until an expected document is changed on purpose, and
   a change to one is a change to both implementations.
3. **loco's output is the Rust's, byte for byte**, except the
   differences DESIGN.md lists. Every loco change runs the light gate
   and lands only GREEN:

   ```
   rig/tools/light RIG=/path/to/bin/rig
   ```

   It builds loco, runs `rig test rig/loc` and `rig/test.sh`, and
   compares loco's stdout and exit code with the Rust loc's on 122 runs.
4. **Speed claims are measured**: interleaved runs, the fastest of
   several, with the machine's load noted. A change that does not pay is
   reverted. The table in DESIGN.md is the record, and the README and
   the website quote it.
5. **Toolchain:** Rig at main 6c3f35b78 or later (Rig #688) and Zig
   0.17.0. The `rig` on PATH may be older, so give the gate `RIG=`
   explicitly.
6. **Rig style** follows DESIGN.md's principles: sigils where effects
   happen, lends rather than copies, optionals rather than sentinels, and
   comments only for what the code cannot say.

## Commits

Small and themed, each passing the gate; the message says what changed
and why, with before and after numbers for speed work. No AI attribution
lines. Push to `origin` only when the owner says so.
