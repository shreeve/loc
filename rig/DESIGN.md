# loco: loc in Rig

`rig/` holds a second implementation of loc, built as `bin/loco`. It is
held to `SPEC.md` and the four expected documents in `fixtures/`, byte
for byte, styled output included. The Rust code is never changed; the
Rig version sits beside it. Toolchain: Rig 0.2.9, Zig 0.17.0.

## Principles

1. **Clean, fast, idiomatic Rig.** Sigils where effects happen, lends
   rather than copies, optionals rather than sentinels, enums with
   payloads, `match` over bytes with named constants, and no `raw`
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
| `loc/bytes.rig` | The bytes the code names, and the whitespace and regex byte tables. |
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

**Walker and counters.** One walker task sends a `Job` (path, and whether
the PATH is a device) through a channel to counting tasks. Every file
call in a program that makes tasks goes to the blocking pool, so a walk
that ran first would add 13 to 17% of Rust's time on trig; overlapping
the two removes it. Sums merge at the end, so order cannot matter.

- **`READ_CAP = 6` read turns.** A channel of 6 tokens limits the files in
  their file calls; a counter takes one before a file's first call and
  returns it after its last, before the scan. The blocking pool runs as
  many calls as tasks wait on it, up to 64 threads, so without the cap
  the task count sets the I/O concurrency and brings back the kernel
  contention Rust's semaphore avoids (2,725 ms against 1,986 ms on trig).
- **2N counters with `--jobs N`, 64 without.** `--jobs N` is `N` workers
  (capped at 64) and `2N` counting tasks: with one task per worker each
  worker sleeps through every pool call, and two overlap one file's I/O
  with another's scan (`--jobs=1`: 2,910 ms against Rust's 3,376).
  Without `--jobs` the runtime keeps a worker per core and 64 counting
  tasks run; std gives no core count to ask.
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
`file.open` and reads of the bytes still wanted up to 8192; `File.read`
allocates `max` bytes per call, so `max` stays small. A `.m` file with
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

The scanner was measured against the repository's `scan.rs` on a 101 MB
corpus with identical counts: Rust 243 ms, Rig 196 ms. `--release=fast`
gains nothing, so the program builds with `--release` (safe); the rest of
the gap is I/O and concurrency.

The target is Rust's wall time within 25% on `~/Data/Code/trig` with no
ignore rules (125,268 files) and on `loc .` of Trig. Interleaved runs,
fastest of five, two rounds, on a machine at load 9 to 10:

| Run | Rust | Rig | Ratio |
|---|---|---|---|
| `--no-ignore --json ~/Data/Code/trig` | 2,067 / 2,043 ms | 2,236 / 2,266 ms | 1.09x |
| the same, `--jobs=1` | 3,529 / 3,492 ms | 3,071 / 3,131 ms | 0.88x |
| `--no-ignore --json -l python ~/Data/Code/trig` | 267 / 275 ms | 332 / 353 ms | 1.26x |
| `--json ~/Data/Code/trig` | 23.5 / 25.4 ms | 28.3 / 30.1 ms | 1.19x |
| `~/Data/Code/trig/src` | 10.3 / 10.9 ms | 13.8 / 15.5 ms | 1.38x |

The walk itself is the rest of the gap on filtered runs: `read_dir`
costs more than Rust's listing (see the asks below).

A small tree pays a few milliseconds more than Rust; about 2 ms is
starting the scheduler's workers.

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

- `File.read(!buf, max)` allocates `max` bytes per call, dups the
  descriptor under a global lock, and copies: 1 MiB chunks took 9 s
  against 3.8 s for `file.read`.
- `read_dir` sorts, copies each name twice, uses a 2 KiB buffer, and
  makes one pool hop per directory.
- No open-only readability check exists, so `check_root` lists a
  directory.
- An error mid-listing fails the whole `read_dir`; Rust skips the entry.
- A closed stdout gives the error reason "Unexpected".
- The blocking pool has no cap a program can set; a
  `task.blocking_threads(n)` would replace the token channel.
- Starting the workers costs about 2 ms; `par.map` with `limit: 1`
  starts every worker.
- `task.workers(n)` caps at 64 without saying so.
- `std.text` has no Unicode `to_lower`.
