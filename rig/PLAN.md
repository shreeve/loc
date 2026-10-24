# loc in Rig: the plan

A second implementation of loc, in Rig, under `rig/`, built as
`bin/loco`. `SPEC.md` at the repository's root stays the one authority
for behavior, and the four expected documents in `fixtures/` judge both
implementations byte for byte. The Rust code is not changed: the Rig
version is added beside it. This file says how the Rig version is
built: its shape, the Rig each part becomes, and the order of the work.

Rig is `~/Data/Code/rig` on `main` (built at `a4d1cf635`, 2026-10-23,
still versioned 0.2.9), Zig 0.17.0. Nothing here needs a feature that is
not on `main`: no API objects, no raw pointers, no `extern zig`.

Three reviews checked this plan with probe programs against the Rig
compiler and the Rust binary: ownership and idiom, conformance, and
speed. Their findings are folded in; each shape below that the checker
could reject was compiled.

**Status:** built. `bin/loco` equals the four expected documents byte
for byte, passes all 43 cli checks and 7 unit tests, runs clean under
`RIG_SANITIZE=1` with the leak check, and gives the Rust loc's output
byte for byte, styled output included, on every tree it was run on.

## Principles

1. **Clean, fast, elegant, idiomatic Rig.** The code reads as Rig written
   for Rig, not as Rust transliterated: sigils where effects happen,
   lends rather than copies, optionals rather than sentinels, enums with
   payloads where Rust used tagged structs, several results where Rust
   returned tuples, `match` over bytes with named constants, and no
   `raw` beyond the one `isatty` call. Comments are timeless and as
   dense as the Rust's.
2. **The expected documents are the authority.** A disagreement is a bug
   in the Rig code until an expected document is changed on purpose,
   and a change to one is a change to both implementations.
3. **The same algorithms.** The scanner, the ignore matcher, the
   recognition order, the sorts, and the integer arithmetic of shares,
   sizes, and the bar are the Rust's, so the outputs agree by
   construction and a failing fixture points at one function.
4. **Standard library only:** `std.file`, `std.os`, `std.text`,
   `std.utf8`, `std.sort`, `std.task`.
5. **Speed is measured.** Every cost claim here was probed; the target
   is in [Speed](#speed).

## Layout

```
rig/
  PLAN.md        this file
  main.rig       the program: flags, PATH checks, output, exit status
  loc/           one directory module, one namespace, as the Rust crate
    bytes.rig    the bytes the code names, and the whitespace and regex byte tables
    flags.rig    the command line: a Command, or a Usage error with data
    lang.rig     the language table and its lookups
    scan.rig     line classification and the scanner
    ignore.rig   .gitignore matching
    walk.rig     the walk, recognition, counting, and the sums
    report.rig   the table, the JSON, --languages
    *_test.rig   unit tests, run by `rig test rig/loc`
  build.sh       rig build --release -o bin/loco rig/main.rig
  test.sh        the conformance check and the cli checks, run on bin/loco
```

`main.rig` is the root and `use loc` brings in the directory module,
whose files share one namespace (Rig SPEC §14, Directory modules), so
they call each other freely and only what `main.rig` uses is `pub`. The
binary is `bin/loco`, and `/bin/` joins `.gitignore`. Its messages say
`loc`, as SPEC's help text does, word for word.

## Tests

The Rust tests are left as they are, so the Rig version has its own
driver. Rig cannot start a process, so `rig/test.sh` is a shell script
that runs `bin/loco`:

- **Conformance:** the four commands of `tests/conformance.rs`, each
  compared byte for byte with its expected document (`cmp`), and on a
  difference in `expected-files.json` the first differing file named,
  as the Rust test does.
- **The cli checks:** each test of `tests/cli.rs`, ported to the same
  scratch directories and assertions (exit codes, stdout, the usage
  lines on stderr, `cannot read` on stderr), one shell function per
  Rust test, named as the Rust test is. The `.git` entry, the ignore
  files above `PATH`, the escaped trailing space, unreadable files and
  directories, and several PATHs are built there as the Rust tests
  build them.
- **Unit tests:** the Rust unit tests (the README's language count, the
  bar's glyphs, the size rule) become `test` blocks in
  `rig/loc/*_test.rig`, with tests of their own for the dedup keys,
  path cleaning, and lossy UTF-8, which the fixtures cannot reach
  (APFS refuses names that are not UTF-8).

```
rig/build.sh && rig/test.sh && rig test rig/loc
```

The stderr the checks pin is the usage messages, which the Rig version
prints word for word, and the substring `cannot read`; an I/O error's
own wording is free, so the Rig version names the `FileError`
(`loc: cannot read a/b: denied`).

## The parts

### lang.rig

The table is data built once, `fun languages() -> Table`, and lent
everywhere as `?Table`. Every part of it syncs (Lists, Maps, `Static`s,
byte tables, function values), so every counting task reads the one
table in place; the checker verifies this at the task's call.

```
DOLLAR = ["${"]
HASH = ["#{"]
RIP = ["#{", "${"]
PHP = ["{$"]

enum Interp
  dollar
  hash
  rip
  php

fun openers(i: Interp) -> []Static

obj StrKind                          # plain data, so `List([dq(), sq()])` builds a list
  open: Static
  close: Static
  escape: Bool
  multiline: Bool
  interp: Interp? = none
  stop: [256]Bool = [256 of false]   # filled by `prepare`

enum Chars
  always
  rust

enum Heredoc
  shell
  ruby
  php

enum Region
  tag(name: Static, lang: Static)
  between(open: Static, close: Static, lang: Static)

obj Claim
  extensions: List[Static]
  test: fun(?String) -> Bool

obj Lang
  name: Static
  extensions: List[Static] = List()
  names: List[Static] = List()
  shebangs: List[Static] = List()
  claim: Claim? = none
  line: List[Static] = List()
  hash_attribute: Bool = false
  block_open: Static = ""
  block_close: Static = ""
  nests: Bool = false
  block_at_line_start: Bool = false
  strings: List[StrKind] = List()
  chars: Chars? = none
  regex: List[Static]? = none
  zig_line_string: Bool = false
  rust_raw: Bool = false
  heredoc: Heredoc? = none
  regions: List[Region] = List()
  region_langs: List[Int] = List()   # filled by `prepare`
  color: [3]U8 = [3 of 0]
  starts: [256]Bool = [256 of false] # filled by `prepare`

obj Table
  langs: List[Lang]
  char: StrKind                      # the char-literal kind, Rust's `CHAR`
  by_ext: Map[String, Int]
  by_claim: Map[String, Int]
  by_name: Map[String, Int]
  by_shebang: Map[String, Int]
```

Field defaults stand for Rust's `..NONE`, and absence is an optional:
no `Chars.none`, `Heredoc.none`, or empty `regex` list (Rig rejects a
variant named `none`, and the optional is the idiom anyway). `dq()`,
`sq()`, and `tick()` are functions, as Rust's `kind` and `interpolating`
are, since an object is no module constant. `c_family`, `js_family`,
and `markup` make a `Lang`; a variant of one is bind, set, push:

```
js = js_family("JavaScript", List([".js", ".mjs", ".cjs", ".jsx"]), [0xf1, 0xe0, 0x5a])
js.shebangs = List(["node", "nodejs", "bun", "deno"])
!langs.push(<js)
```

`prepare` reads the names into a `List[Static]` first, then for each
language sorts `strings` by opener length (`sort.sort_by`, stable),
resolves `region_langs` by name, and fills `stop` and `starts` exactly
as the Rust does. The maps are keyed by `String` so a lookup takes a
`?String` (`t.by_ext.get(?lower) ?? none`); an extension is lower-cased
into one reused `String`. The `.m` test is `fun mumps_routine(line:
?String) -> Bool`, a function value, called as `c.test(line)`.

### scan.rig

```
obj Counts
  lines: Int = 0
  blank: Int = 0
  comment: Int = 0
  code: Int = 0

  sub add(!@, o: Counts)

enum Open
  kind(i: Int)          # an index into the current language's `strings`
  char
  rust_raw(hashes: Int)

obj Nest                # an open interpolation: its string kind and brace depth
  kind: Int
  depth: Int

obj OpenHeredoc         # plain: its word is a view of the buffer
  word: ?String
  indented: Bool
  loose: Bool

enum Class
  str
  blank
  code
  comment

obj Scanner
  table: ?Table
  buf: ?String
  outer: Int            # the file's language, kept while a region switches `lang`
  lang: Int
  block_depth: Int = 0
  open: Open? = none
  nests: List[Nest, inline: 4] = List()
  heredoc: OpenHeredoc? = none
  region: Int? = none
  pending: Int? = none

  fun line(!@, pos: Int, end: Int) -> Class

pub fun scan(table: ?Table, lang: Int, buf: ?String) -> Counts
```

A `Scanner` is a view, holding `?Table` and `?String`, and lives only
inside `scan`. Rust's `&'a Lang` pointers become indexes: the current
language is `l = ?@table.langs[@lang]`, a view through a view field,
which views the table and not `@`, so `line` writes `@open`, `@nests`,
and `@heredoc` while it reads `l` (compiled). A line's end is
`text.find_any["\n"](buf, pos) ?? buf.len`.

`line` keeps Rust's order of tests. The arms that only compare bytes
are a `match` on named constants (`HASH => ...`); the arms that bind
(open a string, a Rust raw opener, a regex after its words) are an
`if`/`else if` chain with joined `as`, since a `match` guard does not
bind:

```
else if l.rust_raw and (b == LOWER_B or b == LOWER_R) and rust_raw_opener(buf, i, end) as hashes, after
else if @open_string(i, end) as ki
else if b == SLASH and l.regex as words and regex_opens(buf, pos, i, ?words)
```

The open string's kind is one `match`: `.kind(i) => ?l.strings[i]`,
`.char => ?@table.char`, and `.rust_raw(hashes)` scans for its closer
and `continue`s. The interpolation stack is reached by index
(`n = @nests.len - 1`, then `@nests[n].depth += 1` or
`!@nests.pop()`), since a write view of its top would block the `pop`
in the other branch. The byte helpers (`starts_with`,
`starts_with_ci`, `opens_region`, `closes_region`, `heredoc_opener`,
`rust_raw_opener`, `regex_opens`, `regex_end`, `blank`) are free
functions of `?String` and indexes that give optionals or several
results: `fun rust_raw_opener(buf: ?String, i: Int, end: Int) -> (Int,
Int)?`. `WHITESPACE` and `REGEX_PREV` are compile-time tables,
`WHITESPACE = byte_set[.whitespace]` with `fun byte_set[s: ByteSet] ->
[256]Bool`, Rust's `const fn byte_set`.

### ignore.rig

```
enum Step
  byte(b: U8)
  any
  one
  class(set: Int, inside: Bool)   # an index into the pattern's `sets`
  any_dirs
  rest

obj Pattern
  negate: Bool
  dir_only: Bool
  anchored: Bool
  steps: List[Step]
  sets: List[[256]Bool]

obj IgnoreFile
  offset: Int
  patterns: List[Pattern]
```

The set lives beside the steps, so a `Step` is a few bytes and `match`
copies nothing large. `matches(p: ?Pattern, at: Int, subject: ?String)
-> Bool` walks `p.steps` from `at`, recursively, as the Rust walks its
slice; `compile_class` gives `([256]Bool, Bool, Int)?`. Rust's
`.iter().rev().find_map` is a `while i > 0` loop. A `.gitignore` that
cannot be read is no ignore file, as Rust's `.ok()` makes it:
`file.read(p) catch none`, with no warning; the walk meets the file
itself and reports it `unreadable`.

`ancestors` finds the base. A relative root is joined to `os.cwd()`,
which is resolved as Rust's `absolute` is, and cleaned lexically: split
on `/`, drop empty and `.` components, let `..` pop but never above
`/`, so `rel` never has an empty component (`sub`, `sub/`, `sub//`,
`./sub/`, and `sub/.` apply the same anchored rules). `.git` is found
by `(file.stat(p) catch none) != none`, which holds for a broken link
as `symlink_metadata` does, and ignores an unreadable directory as
`.is_ok()` does. Paths are `String`s of bytes; `join(dir, name)` adds a
`/` only when `dir` does not end in one, so `loc src/` reaches
`src/a.rs`.

### walk.rig

A walker task sends each path to count through a channel, and counting
tasks take them as they come and sum what they count, as the Rust's
walker thread feeds its workers. The walk then overlaps the counting:
in a program that makes tasks, every file call, `read_dir` and each
`.gitignore` probe included, goes to the blocking pool, so a walk that
ran first would add 13 to 17% of Rust's whole time on trig.

```
task.workers(opts.jobs)                     # before the first task
paths = *Chan[String](1024)
turns = *Chan[Int](READ_CAP)                # filled with READ_CAP tokens
w = walk_roots(roots, ?opts, +paths)&       # sends each path, then !paths.close()
ts = Tasks[Sums!]()
for 0..2 * opts.jobs
  !ts.add(counter(?table, ?opts, +paths, +turns)&)
sums = Sums.merge(<(>ts)!)
>w!
```

- **`READ_CAP = 6` stays.** The blocking pool runs as many calls at
  once as tasks wait on it, up to 64 threads, so without a cap the
  number of tasks would set the I/O concurrency and bring back the
  kernel contention the Rust's semaphore avoids (2,725 ms against
  1,986 ms on trig). `count` takes a token, `(!turns).recv()!`, before a
  file's first call and sends it back, `!turns.send(t)!`, after its
  last, before it scans.
- **`--jobs N` is `N` workers and `2N` counting tasks.** With one task
  per worker, each worker sleeps through every pool call; two overlap
  one file's I/O with another's scan (`--jobs=1`: 2,910 ms against
  Rust's 3,376).
- **The walk** skips an entry when its name is `.git`, when `e.link`
  is set, or when `e.kind == .other` (a device, a FIFO, a broken link),
  and recurses when `e.kind == .directory`; Rig's `read_dir` follows
  links for `kind`, so `link` is tested first. A directory that cannot
  be listed, or that is gone (`none`), is a `cannot read` warning and
  nothing below it.
- **Several roots.** Each root is walked in turn, and a path is sent
  once: its key is `realpath(root)` for the root itself, else
  `realpath(root)`, `/`, and the path's bytes after the root's with any
  leading `/` removed, kept in a `Set[String]`. This is what Rust's
  component-wise `PathBuf` equality gives, so `src/main.rs src` counts
  the file once.
- **A root** whose kind is not `.directory`, a file or a device, is
  sent as a file, as Rust's `!metadata.is_dir()` sends it. A root that
  is not a regular file (a device, a FIFO, or a link to one) is read
  only up to the size `file.stat` gives, through `file.open` and
  `File.read`, as the Rust reads `take(size)`: `zero.rs -> /dev/zero`
  counts as an empty file, where `file.read` would read forever.

`counter` loops `while (!paths).recv()! as path`, counts each file
into its own `Sums`, and returns them; `merge` adds the `Sums` of
every counter. Recognition follows the Rust `Sums::count` step for
step, the `LangFilter` cases included. Reading:

- **A whole file** is `file.read(path)`, one call, a `String` of
  exactly its bytes. The NUL check looks at its first 8192 bytes only,
  `text.find_any["\x00"](?buf[..min(buf.len, 8192)], 0)`, so a NUL
  further in leaves the file counted, as in Rust.
- **A head**, for a file whose name decides nothing, is
  `file.stat(path)` for the size and then, when the size is at most
  64 KiB, `file.read(path)` and a look at its first 8192 bytes: two
  pool calls and no descriptor of its own (414 ms for trig's 29,312
  head files, against 1,082 ms for open, read, stat). A larger file is
  `file.open` and `(!f).read(!buf, want)` with `want = 8192 - buf.len`,
  until 8192 bytes or the end. `File.read` allocates `max` bytes per
  call, so its `max` stays at 8192.
- **The `.m` case** that must look before it reads, with exactly one of
  Objective-C and MUMPS excluded, reads the head, decides, and reads
  the whole file only when it counts.
- **`none` or a failure** from `read`, `open`, or `stat` inside the
  walk is `unreadable`, with a `warn`, as Rust's I/O errors are.

`Sums` holds per-language `Counts`, files, and bytes, two
`Map[String, Skipped]`, and `by_file: List[FileRow]? = none`. A label
is added with `if (!m).edit(label) as s` and `put` only for a new one,
so a label allocates once. A `FileRow` takes the path the counter
received, by move.

### report.rig

A port of `report.rs`, building text with `!out.add(...)` and
`!out.push(b)` in place of `write!`. Widths count runes
(`utf8.rune_count`), as Rust counts `char`s; not `text.char_count` or
`text.width`, which count chars and columns. A path is shown by the
Rust's steps in the Rust's order: drop a leading `./` from its bytes,
make it valid UTF-8, then sort, `shorten`, and count widths on the
result. Valid UTF-8 comes from a `utf8.Decoder` fed byte by byte, the
byte fed again while `d.retry` is set, and one U+FFFD pushed at the end
when `d.pending()`: on 20,000 random byte strings this is byte for byte
`String::from_utf8_lossy`. A label is made the same way and lower-cased
in ASCII ([Where the two implementations differ](#where-the-two-implementations-differ)), so two names that become one label merge, as in
Rust. `size` computes in `U128`. `languages()` and `Grid` are as in
Rust.

### main.rig

Flags are read from `os.args()` as bytes, judged in the Rust's order:

- `-h` or `--help` anywhere before `--` prints the help, then
  `--languages` anywhere before `--` prints the list, skipping the PATH
  checks; both scans see flag values, so `--exclude -h` prints the
  help;
- then one pass, in argument order, the first error winning; a flag
  takes the next argument as its value even when it starts with `-`,
  and `--name=V` takes the bytes after the `=`;
- the `--only-lang`/`--exclude-lang` conflict is judged after the pass;
- `--jobs` takes `text.parse_int` and rejects a sign; a value past
  `Int.max` is a usage error.

The outcomes are errors with data, so each message is written in one
place. `parse` gives what to do, or fails with a usage error:

```
enum Command
  run(opts: Options)
  help
  languages(styled: Bool)

error Usage
  unknown_flag(flag: String)
  needs_pattern(flag: Static)
  needs_language(flag: Static)
  unknown_language(name: String)
  bad_jobs
  both_lang_flags

pub fun parse(args: []Static, table: ?Table) -> Command!Usage
pub fun describe(e: ?Usage) -> String
pub sub check_root(root: ?String)!
```

`main` catches a `Usage`, prints what `describe` makes of it, which
`match`es every member and needs no `_`, then the usage line, and
returns 1. A `PATH` fails `check_root` with the `file.FileError` itself,
`not_found` standing for a `none`, and `main` names it in words
(`loc: nope: no such file or directory`) and returns 2 once every
`PATH` is checked; a set of its own would only rename the `FileError`.
The help text is a module constant of lines. A `PATH` is checked with
`file.stat`, then `read_dir` for a directory or `open` for anything else
(`open` gives `none` for a broken link that `stat` reported). Styling asks `isatty(1)`, an `extern fun` called in one
`raw` block, then `NO_COLOR` and `TERM`. Every output, the report, the
help, and the list, is one `String` written by one `print` of all but
its last newline. A closed pipe ends the program with status 0, which
the Rig runtime does already; any other write failure ends it with
status 1 and the runtime's `error: stdout: ...`.

## Speed

The scanner as planned, the per-line method call, the view chain, and
the bounds checks included, was measured against the repository's own
`scan.rs` on a 101 MB corpus with identical counts: Rust 243 ms, Rig
196 ms with `find_any` for line ends. `--release=fast` gained nothing,
so the program builds with `--release` (safe), and the remaining gap is
I/O and concurrency, which the design above closes.

The target is Rust's wall time within 25% on `~/Data/Code/trig` with no
ignore rules (125,268 files) and on `loc .` of Trig, interleaved,
fastest of seven, on a machine at load 11 to 15:

| Run | Rust | Rig | Ratio |
|---|---|---|---|
| `--no-ignore --json ~/Data/Code/trig` | 1,949 ms | 1,990 ms | 1.02x |
| the same, `--jobs=1` | 3,411 ms | 3,075 ms | 0.90x |
| `--json ~/Data/Code/trig` | 24.2 ms | 28.6 ms | 1.18x |

The plan as first drafted took 1.76x on the first. A small tree pays a
few milliseconds of fixed cost more than Rust, about 2 ms of it
starting the scheduler's workers; that is the runtime's, recorded for
the Rig session below. The walk reads a directory's `.gitignore` only
when the directory's listing holds one, which saves a file call in
every other directory (31.1 ms to 28.1 ms on `loc .` of Trig). Without
`--jobs` the runtime keeps a worker per core and 64 counting tasks run,
twice the most workers it starts; std gives no core count to ask.

## Order of work

Each step ends green on what it can check.

0. `rig/build.sh` and `rig/test.sh`, the conformance part first, the
   cli checks ported one Rust test at a time as the steps below make
   each pass; `/bin/` in `.gitignore`.
1. `lang.rig`, `--languages`, and `main.rig`'s flags, help, and usage
   errors. Check: the cli checks of help, usage, short flags, and
   `--languages`.
2. `scan.rig`. Check: each fixture's counts against
   `fixtures/expected-files.json`.
3. `walk.rig` without ignore rules, and the JSON of `report.rig`. Check:
   `expected-no-ignore.json` and `expected-files.json`.
4. `ignore.rig`. Check: `expected.json`.
5. The table and the skipped section. Check: `expected.txt`.
6. `--exclude`, `--only`, `--exclude-lang`, `--only-lang`, several
   PATHs, unreadable entries. Check: the whole cli suite.
7. Styling and the bar, checked under a pseudo-terminal as SPEC says.
8. Speed, against the target.
9. A pass for idiom, then a short Rig section in the README that
   leaves its first `## Usage` block, the `## Languages` block, and
   `in N languages.` as they are, since tests read them.

## Where the two implementations differ

No fixture and no test reaches these. In each the Rig version follows
SPEC, or the closest Rig gives, and the Rust is left as it is.

- **Non-ASCII letters in a skipped label.** A label is the skipped
  file's extension lower-cased, so `NOTES.TXT` and `notes.txt` share
  `.txt`. Rust lower-cases with Unicode's rules and Rig with ASCII's,
  the only case mapping Rig's std has, as the extension lookup in both
  does: `menu.CAFÉ` is `.café` in Rust and `.cafÉ` in Rig.
- **A linked PATH's size.** Rust reports the link's own size for a
  skipped linked PATH (`loc link.png` shows 8 B); Rig reports its
  target's, as SPEC's "a link names its target" says.
- **`--exclude=V` and `--only=V`.** Rust passes `V` through lossy UTF-8,
  so a byte that is not UTF-8 matches differently in the two spellings;
  Rig takes the bytes, as SPEC's byte-wise matching says.
- **`--no-color` after `--`.** Rust's `--languages` obeys it; Rig stops
  at `--`, as SPEC says.
- **Help and `--languages` on a closed pipe.** Rust panics with exit
  101; Rig exits 0, as it does for the report.
- **Error wording.** An I/O error names Rig's `FileError` (`denied`),
  not the system's message; SPEC fixes no wording.

## For the Rig session, after the port

Measured here, owed to the Rig session once the port lands, none
blocking it:

- `File.read(!buf, max)` allocates `max` bytes per call
  (`std/net.zig` `readLent`), dups the descriptor under a global lock,
  and copies: 1 MiB chunks took 9 s against 3.8 s for `file.read`.
- The blocking pool has no cap a program can set; a
  `task.blocking_threads(n)` beside `task.workers(n)` would replace the
  token channel.
- Starting the workers costs about 2 ms, and `par.map` with `limit: 1`
  starts every worker.
- `task.workers(n)` caps at 64 without saying so.
