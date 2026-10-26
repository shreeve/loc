# loco: loc in Rig

`rig/` holds a second implementation of loc, built as `bin/loco`. It is
held to `SPEC.md` and the four expected documents in `fixtures/`, byte
for byte, styled output included. The Rust code is never changed; the
Rig version sits beside it. Toolchain: Rig 0.2.9 at main 6c3f35b78 or
later, and Zig 0.17.0. That Rig's blocking pool (Rig #624) bounds the
file calls in flight, and an optional field of a parameter moves like
any other field (Rig #688).

## Principles

1. **Clean, fast, idiomatic Rig.** Sigils where effects happen, lends
   rather than copies, optionals rather than sentinels, enums with
   payloads, `match` over byte literals (`'{'`, and `"\t"` for a control
   byte, which a raw `'…'` cannot spell), `?` only where a bare name would
   not lend, and no `raw`
   beyond the one `isatty` call. Comments say only what the code cannot.
2. **The expected documents are the authority.** A disagreement is a bug
   in the Rig code until an expected document is changed on purpose, and
   a change to one is a change to both implementations.
3. **The same algorithms.** The scanner, the ignore matcher, the
   recognition order, the sorts, and the integer arithmetic of shares,
   sizes, and the bar are the Rust's, so a failing fixture points at one
   function.
4. **Standard library only.** Speed claims here were measured.

## Layout

| File | Holds |
|---|---|
| `main.rig` | The program: dispatch, PATH checks, output, exit status, `isatty`. |
| `loc/bytes.rig` | The whitespace and regex byte tables, and `is_ident`. |
| `loc/lang.rig` | The language table, built once, and its lookups. |
| `loc/scan.rig` | Line classification and the scanner. |
| `loc/ignore.rig` | `.gitignore` matching, and the base the ignore files apply from. |
| `loc/flags.rig` | The command line: `parse`, `describe`, the help text, `Options`. |
| `loc/walk.rig` | The walk, recognition, reading, counting, and the sums. |
| `loc/report.rig` | The table, the JSON, `--languages`, lossy UTF-8. |
| `loc/loc_test.rig` | Unit tests. |
| `test.sh` | The conformance check and the cli checks, run on a binary. |
| `build.sh` | `rig build --release -o bin/loco rig/main.rig`. |

`use loc` brings in the directory module, whose files share one
namespace; only what `main.rig` uses is `pub`. Messages say `loc`.

## Build and test

```
rig/build.sh && rig/test.sh && rig test rig/loc
```

- `rig/test.sh` compares the four commands of `tests/conformance.rs` with
  their expected documents (`cmp`), then runs one shell function per test
  of `tests/cli.rs`, named as the Rust test is, then a few checks beyond
  them. `rig/test.sh NAME...` runs only those.
- `rig test rig/loc` runs the unit tests: the README's language count, the
  bar's glyphs, the size rule, and what fixtures cannot reach (APFS
  refuses names that are not UTF-8): dedup keys, path cleaning, lossy
  UTF-8, shebangs.
- `LOC=target/release/loc rig/test.sh` runs the same checks on the Rust
  loc. It fails exactly the last two, which the comment in `test.sh`
  names: a `.gitignore` line of only spaces, and a linked PATH's size.
- `rig/tools/light RIG=/path/to/bin/rig` is the light gate a Rig change
  runs: it builds loco with that Rig, runs both suites above, and compares
  loco's output and exit code with the Rust loc's on 122 tree and flag runs,
  then says GREEN or RED. Timing is not part of it.

## Decisions the code cannot explain

**Table and scanner.** `languages()` builds the table once and it is lent
everywhere as `?Table`; every part of it syncs, so all counting tasks
read it in place. Absence is an optional. An extension is lower-cased in
ASCII into a new `String`, a cost that does not show against the I/O. A `Scanner` is a view inside `scan`;
Rust's language references are indexes into `table.langs`.

**Ignore files.** A relative root is joined to `os.cwd()` and cleaned
lexically (empty and `.` components dropped, `..` pops but never above
`/`), so `sub`, `sub/`, `sub//`, `./sub/`, and `sub/.` apply the same
anchored rules. `.git` is found by `file.stat`, true for a broken link
and blind to an unreadable directory, as in Rust. A `.gitignore` that
cannot be read is no ignore file (Rust's `.ok()`), with no warning; the
walk meets the file itself and reports it. A line of only spaces is no
pattern.

**Walkers and counters.** Walker tasks send each `Job` (path, and
whether the PATH is a device) through a channel to counting tasks. Every
file call in a program that makes tasks goes to the blocking pool, so a
walk that ran first would add 13 to 17% of Rust's time on trig;
overlapping the two removes it. Sums merge at the end and every report
row sorts by its own key, so no order can change the output.

- **Up to `WALKERS = 16` walker tasks.** Each directory listing is a pool
  call, which a single walker waits out one at a time; Rust's one walker
  does too. A subdirectory gets a task of its own while fewer than 16
  walkers are listing (a `*Cell[Int]` counted with `add` and `sub`),
  and is walked in place otherwise. A walker waiting for its own tasks
  leaves its turn to another. The ignore files are an `Ignores` chain: a
  directory's own, then a view of its parent's, so a subdirectory's task
  reads them in place, and each frame waits for its tasks before it ends.
  On trig, walk-only: 290 ms with one walker, 142 with 4, 120 with 16,
  against Rust's 190. Among several roots, those whose resolved paths
  nest share one walker and the dedup set, which is one task's (all of
  them, when any root does not resolve); every
  other root gets the walker tasks, since two roots that do not nest
  share no file (8 trig subdirectories: 1,731 ms with one walker, 1,348
  with the tasks, against Rust's 1,954).
- **No read cap of loco's own.** The pool keeps the file calls in flight
  near the performance cores, which is where the kernel stops gaining
  from more. A token channel on top of it only made reads wait:
  `~/Data/Code/rig` took 185 ms with 6 tokens and 143 ms without.
- **Up to 64 counting tasks, started on demand.** The walker asks for a
  counter with each of the first 64 files it sends (a shared `*Cell[Int]`
  keeps the count), so an empty tree starts none and a small one few:
  the empty directory took 7.4 ms when all 64 started at once, 5.8
  after. Each counter waits out its own file calls, so `--jobs N` sets
  `N` workers (capped at 64) and not the counters: with `2N` of them,
  `--jobs=1` had two files in flight (3,019 ms against 2,015 with 64;
  Rust 3,250).
- **The walk starts from `check_root`'s listing.** `check_root` stats
  each PATH and lists a directory or opens a file, to exit 2 before any
  output, and hands what it
  found to the walk, which neither stats nor lists it again; `realpath`
  runs only with several PATHs (`~/Data/Code/rig`: 168 ms to 135).
  `check_roots` checks the PATHs on 16 tasks (`par.map`), so their pool
  calls overlap, and `main` warns in PATH order: 20,000 PATHs took
  1,141 ms one at a time and 524 ms so (4 tasks: 877, 64: 709).
- **The walk** skips `.git`, links (tested first, since `read_dir`
  follows links for `kind`), and other kinds (device, FIFO, broken
  link). A directory that cannot be listed is a `cannot read` warning
  and nothing below it.
- **Dedup keys below the resolved root, for several roots.** A path's key
  is `realpath(root)` for the root itself, else `realpath(root)`, `/`,
  and the path's bytes after the root's with leading `/` removed, kept in
  a `Set[String]`. Links are never followed, so a file has one key below
  its resolved root, as Rust's component-wise `PathBuf` equality gives:
  `src/main.rs src` counts the file once. One root keeps no set.
- **A PATH that is not a directory** is sent as a file. One that is not
  a regular file (device, FIFO, link to one) is read through `file.open`
  only up to the size `file.stat` gives, as Rust reads `take(size)`:
  `zero.rs -> /dev/zero` counts as an empty file.
- **Dropping by name in the walker.** `dropped_by_name` applies the drops
  of `load` that read nothing (`-x`, and `-l` for a name no chosen
  language owns), so the walker never sends such a file.
- **`.gitignore` is read only when listed** in the directory's listing,
  which saves a file call in every other directory (31.1 ms to 28.1 ms on
  `loc .` of Trig).

**Reading.** A whole file is one `file.read`; the NUL check covers its
first 8192 bytes, so a later NUL leaves the file counted, as in Rust. A
head, for a file whose name decides nothing, is `file.stat` for the size
and then, up to 64 KiB, a whole `file.read` and a look at the first 8192
bytes: two pool calls and no descriptor of its own (414 ms for trig's
29,312 head files, against 1,082 ms for open, read, stat). The whole
file is kept, so a file that counts is not read twice. A larger file is
`file.open` and reads of the bytes still wanted, 8192 at a time. A `.m` file with
exactly one of Objective-C and MUMPS excluded reads the head, decides,
and reads the rest only when it counts. A failed `read`, `open`, or
`stat` is `unreadable`, with a warning.

**Report.** Widths count runes (`utf8.rune_count`), as Rust counts
`char`s; not `text.char_count` or `text.width`. A path is shown in the
Rust's order: drop a leading `./`, make it valid UTF-8, then sort,
`shorten`, and count widths. Valid UTF-8 comes from a `utf8.Decoder` fed
byte by byte, a byte fed again while `d.retry`, and one U+FFFD at the
end when `d.pending()`; on 20,000 random byte strings it is byte for
byte `String::from_utf8_lossy`. A skipped label is made the same way and
lower-cased in ASCII, so names that become one label merge. `size` uses
`U128`. Each output is one `String` written by one `print`.

**Command line.** `parse` reads `os.args()` as bytes: `-h`/`--help`
before `--`, then `--languages` before `--` (both scans see flag values,
so `--exclude -h` prints the help); then one pass, the first error
winning. A flag takes the next argument as its value even when it starts
with `-`. `--jobs` rejects a sign, and a value past `Int.max` is a usage
error. `main` prints a usage error and the usage line and returns 1; a
PATH that fails `check_root` is named in words and `main` returns 2 once
every PATH is checked. Styling asks `isatty(1)`, then `NO_COLOR` and
`TERM`.

## Speed

`--release=fast` gains nothing, so the program builds with `--release`
(safe).

Interleaved runs, fastest of seven, on a 10-core machine (4 performance
cores) at load 2.6, loco from 0d9bc00 built with Rig main 6c3f35b78. A
second round at load 6 to 9 kept every ratio within 0.1. `~/Data/Code/trig`
holds 125,268 files.

| Run | Rust | Rig | Ratio |
|---|---|---|---|
| `--no-ignore --json ~/Data/Code/trig` | 1,881 ms | 1,216 ms | 0.65x |
| the same, `--jobs=1` | 3,377 ms | 1,692 ms | 0.50x |
| `--no-ignore --json -l python ~/Data/Code/trig` | 219 ms | 113 ms | 0.52x |
| `--no-ignore --json -o zzznomatch ~/Data/Code/trig` (the walk) | 183 ms | 104 ms | 0.57x |
| `--no-ignore --json` of 8 trig subdirectories as PATHs | 1,899 ms | 1,223 ms | 0.64x |
| `--jobs=1`, 130 MB of C, Go, HTML, JS, Python, Ruby, Rust, TS and Zig | 240 ms | 199 ms | 0.83x |
| one 378 MB file of long string literals | 293 ms | 234 ms | 0.80x |
| `--json ~/Data/Code/rig` | 139 ms | 129 ms | 0.92x |
| `--json ~/Data/Code/trig` | 22.2 ms | 22.6 ms | 1.02x |
| `~/Data/Code/trig/src` (304 files, 13.8 MB) | 10.2 ms | 12.6 ms | 1.24x |
| `--json .` of this repository | 7.3 ms | 9.8 ms | 1.34x |
| `--json -f fixtures` | 6.7 ms | 8.7 ms | 1.30x |
| `--json` of an empty directory | 4.6 ms | 5.3 ms | 1.15x |
| 20,000 files given as PATHs (load 7 to 14) | 651 ms | 524 ms | 0.80x |

A small tree pays about 2 ms more than Rust: starting every worker, and
a pool hop for each file call.

## Where the two implementations differ

No fixture reaches these; the first two are pinned by the last two checks
of `test.sh`. The Rig version follows SPEC, or the closest Rig gives.

- **A `.gitignore` line of only spaces.** Rust panics; loco ignores the
  line, as SPEC says.
- **A linked PATH's size.** Rust reports the link's own size (`loc
  link.png` shows 8 B); loco follows the link, as SPEC says.
- **`--exclude=V` and `--only=V`.** Rust passes `V` through lossy UTF-8,
  so a non-UTF-8 byte matches differently in the two spellings; loco
  takes the bytes, as SPEC's byte-wise matching says.
- **`--languages -- --no-color`.** Rust obeys the `--no-color`; loco's
  `--` ends flags.
- **A closed stdout.** The exit code is 1 from the Rig runtime, 0 from
  Rust.
- **Lower-casing of skipped labels.** Rust uses Unicode's rules, loco
  ASCII only, as the extension lookup in both does: `menu.РУ` is
  `.ру` in Rust and `.РУ` in loco. Accepted.
- **Stderr wording.** An I/O error names Rig's `FileError`, not the
  system's message; SPEC fixes no wording.

## Asks for Rig's standard library

Measured here; none blocks loco.

- Every file call is a hop to the blocking pool and a wake back: in C,
  a hop per file cost 42% on one thread. A worker with nothing else to
  run could make a regular-file call itself (approved for Rig, not yet
  built); loco's walker tasks only overlap the hops.
- The blocking pool's lock spins without backing off and reads the clock
  while held: under load it is the top frame of a `--jobs=1` profile
  (62% of the worker's time), and a private patch cut a large walk's
  user time from 14.9 s to 1.4 s at the same wall time.
- The allocator keeps a freed large block only for an allocation of
  exactly its size, so each file read whole of a new size faults in
  fresh pages: 24,600 page reclaims against Rust's 3,000 on 9,000 files
  (Rust reuses one buffer per reader).
- An error mid-listing fails the whole `read_dir`; Rust skips the entry.
- A closed stdout gives the error reason "Unexpected".
- Starting every worker at the first task costs about 0.6 ms. With a hop
  per file call, it is most of the 2 ms loco pays over Rust on
  `trig/src`'s 304 files.
- `task.workers(n)` caps at 64 without saying so.
- `std.text` has no Unicode `to_lower`.
