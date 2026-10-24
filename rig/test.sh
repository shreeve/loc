#!/usr/bin/env bash
# The Rig loc's checks, run on bin/loco: the conformance check of
# tests/conformance.rs, then the cli checks of tests/cli.rs, each a shell
# function named as its Rust test and asserting what it asserts.
# `rig/test.sh NAME...` runs only those. Build first with rig/build.sh.

set -u
[[ -z ${LOC:-} || $LOC == /* || $LOC != */* ]] || LOC=$PWD/$LOC
cd "$(dirname "$0")/.."
ROOT=$PWD
LOC=${LOC:-$ROOT/bin/loco}  # LOC=target/release/loc runs the same checks on the Rust loc
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/loco-test.XXXXXX")
trap 'chmod -R u+rwx "$SCRATCH" 2>/dev/null; rm -rf "$SCRATCH"' EXIT

# ---- Helpers ---------------------------------------------------------------

# The result of the last `run`: its exit status, stdout, and stderr.
status=0
out=
err=

# Runs loco with the arguments given, in the current directory.
run() {
  status=0
  "$LOC" "$@" >"$SCRATCH/.out" 2>"$SCRATCH/.err" || status=$?
  out=$(cat "$SCRATCH/.out"; printf x)
  out=${out%x}
  err=$(cat "$SCRATCH/.err"; printf x)
  err=${err%x}
}

# Stdout of loco with the arguments given.
stdout() {
  run "$@"
  printf '%s' "$out"
}

# A fresh directory for one check, made the current one; the Rust tests' Scratch.
scratch() {
  cd "$(mktemp -d "$SCRATCH/case.XXXXXX")"
}

# Writes a file below the current directory, making its directories.
put() {
  mkdir -p -- "$(dirname -- "$1")"
  printf '%s' "$2" >"./$1"
}

unreadable() {
  chmod 000 "$1"
}

fail() {
  printf '    %s\n' "$@"
  exit 1
}

is() {
  [ "$1" = "$2" ] || fail "expected: $2" "  actual: $1" "${3:-}"
}

has() {
  [[ "$1" == *"$2"* ]] || fail "lacks: $2" "in: $1"
}

lacks() {
  [[ "$1" != *"$2"* ]] || fail "should lack: $2" "in: $1"
}

starts() {
  [[ "$1" == "$2"* ]] || fail "should start with: $2" "but is: $1"
}

ends() {
  [[ "$1" == *"$2" ]] || fail "should end with: $2" "but is: $1"
}

# How many files of a language a JSON report counts, 0 when it is absent.
files_of() {
  if [[ "$1" =~ "\"name\":\"$2\",\"files\":"([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo 0
  fi
}

# The JSON object for one language, or an empty string when it is absent.
entry() {
  local key="{\"name\":\"$2\","
  [[ "$1" == *"$key"* ]] || return 0
  local rest=${1#*"$key"}
  printf '%s' "$key${rest%%\}*}}"
}

# The first ``` block after a heading in a Markdown file.
block_after() {
  awk -v heading="$2" '
    !found && index($0, heading) == 1 { found = 1; next }
    found && !open && $0 == "```" { open = 1; next }
    open && /^```/ { exit }
    open { print }
  ' "$1"
}

# ---- Conformance -------------------------------------------------------------

# loco's output on fixtures/cases must equal an expected document byte for byte.
same_as() {
  local expected=$1
  shift
  cd "$ROOT"
  run "$@"
  is "$status" 0 "stderr: $err"
  if ! cmp -s "$SCRATCH/.out" "fixtures/$expected"; then
    diff <(tr ',' '\n' <"fixtures/$expected") <(tr ',' '\n' <"$SCRATCH/.out") | head -20 | sed 's/^/    /'
    fail "loco $* differs from fixtures/$expected; a stray file such as .DS_Store inside fixtures/cases changes the skipped counts"
  fi
}

table_matches_expected() { same_as expected.txt "$ROOT/fixtures/cases"; }
json_matches_expected() { same_as expected.json --json "$ROOT/fixtures/cases"; }
json_no_ignore_matches_expected() { same_as expected-no-ignore.json --json --no-ignore "$ROOT/fixtures/cases"; }
by_file_json_matches_expected_files() { same_as expected-files.json --json --by-file --no-ignore fixtures/cases; }

# ---- The cli checks ------------------------------------------------------------

help_exits_0_and_usage_errors_exit_1() {
  scratch
  run --help; is "$status" 0
  run --json -h; is "$status" 0
  run --bogus; is "$status" 1
  run --jobs 0; is "$status" 1
  run --jobs; is "$status" 1
}

missing_path_exits_2() {
  scratch
  run nope; is "$status" 2
}

unreadable_file_path_exits_2() {
  scratch
  put locked.rs $'x\n'
  unreadable locked.rs
  run locked.rs; is "$status" 2 "stderr: $err"
}

unreadable_directory_path_exits_2() {
  scratch
  mkdir locked
  unreadable locked
  run locked; is "$status" 2 "stderr: $err"
}

unreadable_file_inside_a_walk_is_skipped_and_exits_0() {
  scratch
  put ok.rs $'x\n'
  put locked.rs $'y\n'
  unreadable locked.rs
  put locked.xyz $'z\n'
  unreadable locked.xyz
  run --json .; is "$status" 0
  has "$out" '"name":"Rust","files":1,'
  has "$out" '"label":"unreadable","files":2,'
}

a_symlink_given_as_path_is_followed() {
  scratch
  put real/a.rs $'x\n'
  ln -s real link
  run --json link; is "$status" 0
  has "$out" '"name":"Rust","files":1,'
  put b.rs $'y\n'
  ln -s b.rs linkfile.rs
  has "$(stdout --json linkfile.rs)" '"name":"Rust","files":1,'
}

a_symlink_inside_a_walk_is_neither_followed_nor_counted() {
  scratch
  put real/a.rs $'x\n'
  ln -s real link
  ln -s real/a.rs link.rs
  run --json .
  has "$out" '"name":"Rust","files":1,'
  has "$out" '"skipped":{"text":{"files":0,'
}

help_matches_the_spec() {
  scratch
  run --help
  cmp -s "$SCRATCH/.out" <(block_after "$ROOT/SPEC.md" "## Command line") || fail "--help is not SPEC.md's block" "$out"
}

readme_usage_is_the_help_output() {
  scratch
  run -h
  cmp -s "$SCRATCH/.out" <(block_after "$ROOT/README.md" "## Usage") || fail "-h is not README.md's block" "$out"
}

several_paths_sum_and_a_file_reached_twice_counts_once() {
  scratch
  put src/main.rs $'x\n'
  put src/lib/b.rs $'y\n'
  put other/c.rs $'z\n'
  is "$(files_of "$(stdout --json src other)" Rust)" 3
  is "$(files_of "$(stdout --json src src/lib)" Rust)" 2
  is "$(files_of "$(stdout --json src src)" Rust)" 2
  is "$(files_of "$(stdout --json src/main.rs src/main.rs)" Rust)" 1
  is "$(files_of "$(stdout --json src/main.rs src)" Rust)" 2
}

a_missing_path_among_several_exits_2_with_no_output() {
  scratch
  put a.rs $'x\n'
  run --json a.rs nope
  is "$status" 2
  is "$out" ""
}

double_dash_ends_the_flags() {
  scratch
  put -weird/a.rs $'x\n'
  run --json -weird; is "$status" 1
  is "$(files_of "$(stdout --json -- -weird)" Rust)" 1
}

exclude_matches_like_a_gitignore_line() {
  scratch
  put a.rs $'x\n'
  put vendor/v.rs $'x\n'
  put sub/vendor/w.rs $'x\n'
  put d/x.rs $'x\n'
  put other/d $'x\n'
  is "$(files_of "$(stdout --json .)" Rust)" 4
  is "$(files_of "$(stdout --json --exclude vendor .)" Rust)" 2
  is "$(files_of "$(stdout --json --exclude=/vendor .)" Rust)" 3
  local dir_only
  dir_only=$(stdout --json --exclude d/ .)
  is "$(files_of "$dir_only" Rust)" 3
  has "$dir_only" '"label":"d","files":1,'
  is "$(files_of "$(stdout --json --exclude vendor --exclude d .)" Rust)" 1
}

exclude_decides_before_gitignore_and_applies_with_no_ignore() {
  scratch
  put .gitignore $'*.md\n'
  put keep.md $'x\n'
  put notes.md $'x\n'
  put a.rs $'x\n'
  put vendor/v.rs $'x\n'
  is "$(files_of "$(stdout --json .)" Markdown)" 0
  is "$(files_of "$(stdout --json --exclude '!keep.md' .)" Markdown)" 1
  local no_ignore
  no_ignore=$(stdout --json --no-ignore --exclude vendor .)
  is "$(files_of "$no_ignore" Markdown)" 2
  is "$(files_of "$no_ignore" Rust)" 1
}

exclude_is_relative_to_each_path_and_never_path_itself() {
  scratch
  for root in a b; do
    put "$root/vendor/x.rs" $'x\n'
    put "$root/y.rs" $'x\n'
  done
  is "$(files_of "$(stdout --json --exclude /vendor a b)" Rust)" 2
  is "$(files_of "$(stdout --json --exclude vendor a/vendor)" Rust)" 1
}

exclude_without_a_pattern_is_a_usage_error() {
  scratch
  run --exclude; is "$status" 1
  run --exclude= .; is "$status" 1
  run --exclude=vendor .; is "$status" 0
}

only_counts_what_a_gitignore_line_would_skip() {
  scratch
  put a.rs $'x\n'
  put vendor/v.rs $'x\n'
  put vendor/gen/g.rs $'x\n'
  put vendor/notes.txt $'x\n'
  put sub/vendor/w.rs $'x\n'
  put top.txt $'x\n'
  local vendor none
  vendor=$(stdout --json --only vendor .)
  is "$(files_of "$vendor" Rust)" 3
  has "$vendor" '"text":{"files":1,'
  has "$vendor" '"label":".txt","files":1,'
  is "$(files_of "$(stdout --json --only=/vendor .)" Rust)" 2
  is "$(files_of "$(stdout --json --only '*.rs' --only '!a.rs' .)" Rust)" 3
  is "$(files_of "$(stdout --json --only /vendor/ --only '!vendor/gen/' .)" Rust)" 2
  is "$(files_of "$(stdout --json --only /vendor/ --exclude vendor/gen/ .)" Rust)" 1
  none=$(stdout --json --only nothing .)
  has "$none" '"languages":[],'
  has "$none" '"text":{"files":0,'
}

only_leaves_gitignore_in_force_and_applies_with_no_ignore() {
  scratch
  put .gitignore $'*.md\n'
  put notes.md $'x\n'
  put a.rs $'x\n'
  has "$(stdout --json --only '*.md' .)" '"languages":[],'
  local no_ignore
  no_ignore=$(stdout --json --no-ignore --only '*.md' .)
  is "$(files_of "$no_ignore" Markdown)" 1
  is "$(files_of "$no_ignore" Rust)" 0
}

only_is_relative_to_each_path_and_a_file_path_always_counts() {
  scratch
  for root in a b; do
    put "$root/vendor/x.rs" $'x\n'
    put "$root/y.rs" $'x\n'
  done
  is "$(files_of "$(stdout --json --only /vendor a b)" Rust)" 2
  is "$(files_of "$(stdout --json --only '*.py' a/y.rs)" Rust)" 1
}

only_decides_which_files_by_file_lists() {
  scratch
  put src/a.rs $'x\n'
  put src/b.rs $'x\n'
  put other/c.rs $'x\n'
  local json
  json=$(stdout --json --by-file --only src/ .)
  is "$(files_of "$json" Rust)" 2
  has "$json" '"path":"src/a.rs",'
  has "$json" '"path":"src/b.rs",'
  lacks "$json" 'other/c.rs'
}

only_without_a_pattern_is_a_usage_error() {
  scratch
  run --only; is "$status" 1
  run --only= .; is "$status" 1
  run --only=vendor .; is "$status" 0
}

exclude_lang_drops_the_language_from_every_total_and_label() {
  scratch
  put a.rs $'x\n'
  put b.rs $'x\n'
  put c.py $'x\n'
  put notes.txt $'x\n'
  printf 'x\0y' >blob.rs
  put .gitignore $'c.py\n'
  local plain without two
  plain=$(stdout --json --no-ignore .)
  is "$(files_of "$plain" Rust)" 2
  has "$plain" '"total":{"files":3,'
  has "$plain" '"binary":{"files":1,'
  without=$(stdout --json --no-ignore --exclude-lang rust .)
  is "$(entry "$without" Rust)" ""
  is "$(files_of "$without" Python)" 1
  has "$without" '"total":{"files":1,'
  has "$without" '"label":".txt","files":1,'
  has "$without" '"binary":{"files":0,'
  two=$(stdout --json --exclude-lang=RUST --exclude-lang Python .)
  has "$two" '"languages":[],'
}

a_dot_m_file_is_mumps_by_its_first_line_and_excluded_as_that_language() {
  scratch
  put routine.m $'R ;header\n ; comment\n'
  put bom.m $'\xef\xbb\xbfR ;header after a byte-order mark\n'
  put class.m $'#import <x.h>\n'
  local i long=""
  for ((i = 0; i < 400; i++)); do long+=$'x; // longer than the head\n'; done
  put long.m "$long"
  local plain no_mumps no_objc
  plain=$(stdout --json .)
  is "$(files_of "$plain" MUMPS)" 2
  is "$(files_of "$plain" Objective-C)" 2
  has "$(entry "$plain" Objective-C)" '"lines":401,'
  no_mumps=$(stdout --json -x mumps .)
  is "$(entry "$no_mumps" MUMPS)" ""
  is "$(entry "$no_mumps" Objective-C)" "$(entry "$plain" Objective-C)"
  no_objc=$(stdout --json -x objective-c .)
  is "$(files_of "$no_objc" MUMPS)" 2
  is "$(entry "$no_objc" Objective-C)" ""
  unreadable routine.m
  has "$(stdout --json -x objective-c .)" '"label":"unreadable","files":1,'
  run --json -x objective-c -x mumps .
  has "$out" '"text":{"files":0,'
  is "$err" ""
}

exclude_lang_leaves_embedded_regions_with_their_file() {
  scratch
  put a.vue $'<template><p>hi</p></template>\n<style>\na {}\n/* c */\n</style>\n'
  put x.css $'a {}\n'
  local plain without
  plain=$(stdout --json .)
  without=$(stdout --json --exclude-lang CSS .)
  is "$(files_of "$plain" CSS)" 1
  is "$(entry "$without" CSS)" ""
  is "$(entry "$without" Vue)" "$(entry "$plain" Vue)"
  has "$(entry "$plain" Vue)" '"comment":1,'
}

exclude_lang_with_an_unknown_or_missing_name_is_a_usage_error() {
  scratch
  put a.rs $'x\n'
  run --exclude-lang; is "$status" 1
  run --exclude-lang= .; is "$status" 1
  run --exclude-lang Fortran .
  is "$status" 1
  is "$out" ""
  starts "$err" $'loc: unknown language Fortran\n'
  run --exclude-lang 'PHP code' .; is "$status" 1
  run --exclude-lang 'c#' .; is "$status" 0
}

only_lang_counts_named_languages_and_reports_only_their_misses() {
  scratch
  put a.rs $'x\n'
  put b.py $'x\n'
  put notes.txt $'x\n'
  printf 'x\0y' >data.bin
  printf 'x\0y' >blob
  local rust two
  rust=$(stdout --json --only-lang rust .)
  is "$(files_of "$rust" Rust)" 1
  is "$(entry "$rust" Python)" ""
  has "$rust" '"total":{"files":1,'
  has "$rust" '"text":{"files":0,'
  has "$rust" '"binary":{"files":0,'
  run --only-lang rust .
  ends "$out" $'─\n'
  lacks "$out" skipped
  two=$(stdout --json --only-lang=RUST --only-lang Python .)
  is "$(files_of "$two" Python)" 1
  has "$two" '"total":{"files":2,'
  printf 'x\0y' >blob.rs
  run --only-lang rust .
  has "$out" $'\n0 of 1 files skipped,'
  ends "$out" $'\n1 binary file, 3 B: .rs 1\n'
}

only_lang_reads_an_extensionless_file_only_when_a_named_language_has_shebangs() {
  scratch
  put script $'#!/usr/bin/env python3\nx = 1\n'
  put tool $'#!/bin/sh\necho\n'
  put locked $'#!/usr/bin/env python3\n'
  unreadable locked
  local json
  json=$(stdout --json --only-lang python .)
  is "$(files_of "$json" Python)" 1
  is "$(entry "$json" Shell)" ""
  has "$json" '"label":"unreadable","files":1,'
  run --json --only-lang rust .
  has "$out" '"text":{"files":0,'
  is "$err" ""
}

only_lang_reads_a_dot_m_file_when_one_of_its_languages_is_named() {
  scratch
  put routine.m $'R ;header\n'
  put class.m $'#import <x.h>\n'
  put locked.m $'R ;header\n'
  unreadable locked.m
  local mumps both
  mumps=$(stdout --json --only-lang mumps .)
  is "$(files_of "$mumps" MUMPS)" 1
  is "$(entry "$mumps" Objective-C)" ""
  has "$mumps" '"label":"unreadable","files":1,'
  both=$(stdout --json --only-lang mumps --only-lang objective-c .)
  is "$(files_of "$both" MUMPS)" 1
  is "$(files_of "$both" Objective-C)" 1
  run --json --only-lang rust .
  has "$out" '"text":{"files":0,'
  is "$err" ""
}

only_lang_leaves_embedded_regions_with_their_file() {
  scratch
  put a.vue $'<template><p>hi</p></template>\n<style>\na {}\n</style>\n'
  put x.css $'a {}\n'
  local only
  only=$(stdout --json --only-lang CSS .)
  is "$(entry "$only" Vue)" ""
  is "$(entry "$only" CSS)" "$(entry "$(stdout --json .)" CSS)"
  has "$only" '"total":{"files":1,'
}

only_lang_drops_a_file_path_of_another_language() {
  scratch
  put a.rs $'x\n'
  local python
  python=$(stdout --json --only-lang python a.rs)
  has "$python" '"languages":[],'
  has "$python" '"text":{"files":0,'
  is "$(files_of "$(stdout --json --only-lang rust a.rs)" Rust)" 1
}

only_lang_with_a_bad_name_or_with_exclude_lang_is_a_usage_error() {
  scratch
  put a.rs $'x\n'
  run --only-lang; is "$status" 1
  run --only-lang= .; is "$status" 1
  run --only-lang Fortran .
  is "$status" 1
  starts "$err" $'loc: unknown language Fortran\n'
  run --only-lang rust --exclude-lang c .
  is "$status" 1
  is "$out" ""
  starts "$err" $'loc: --only-lang and --exclude-lang cannot be combined\n'
  run --only-lang 'c#' .; is "$status" 0
}

short_flags_are_exact_aliases_that_take_the_next_argument_and_do_not_bundle() {
  scratch
  put a.rs $'x\n'
  put vendor/v.rs $'x\n'
  put c.py $'x\n'
  is "$(stdout --json -e vendor -x python .)" "$(stdout --json --exclude vendor --exclude-lang python .)"
  is "$(stdout --json -o vendor -l rust .)" "$(stdout --json --only vendor --only-lang rust .)"
  is "$(files_of "$(stdout --json -e vendor .)" Rust)" 1
  is "$(files_of "$(stdout --json -o vendor .)" Rust)" 1
  [ -n "$(stdout --languages)" ] || fail "--languages printed nothing"
  local bad
  for bad in "-e=vendor ." "-o=vendor ." "-x=python ." "-l=python ." "-el ." "-e" "-o" "-x" "-l"; do
    # shellcheck disable=SC2086
    run $bad
    is "$status" 1 "$bad"
    is "$out" "" "$bad"
  done
}

by_file_lists_files_under_their_language_by_code_then_path() {
  scratch
  put b.rs $'x\ny\nz\n'
  put a.rs $'x\n'
  put c.rs $'x\n'
  put d.py $'x\n\n'
  # The language table's layout: first column left-aligned, the rest right-aligned to seven, four spaces between.
  line() {
    printf '%-8s' "$1"
    shift
    local cell
    for cell in "$@"; do printf '    %7s' "$cell"; done
    printf '\n'
  }
  local rule="" want
  for ((i = 0; i < 8 + 6 * 11; i++)); do rule+="─"; done
  want=$(
    echo "$rule"
    line Language Files Lines Blank Comment Code %
    echo "$rule"
    line Rust 3 5 0 0 5 83.3
    echo "$rule"
    line b.rs "" 3 0 0 3 50.0
    line a.rs "" 1 0 0 1 16.7
    line c.rs "" 1 0 0 1 16.7
    echo "$rule"
    line Python 1 2 1 0 1 16.7
    echo "$rule"
    line d.py "" 2 1 0 1 16.7
    echo "$rule"
    line Total 4 7 1 0 6 100.0
    echo "$rule"
  )
  starts "$(stdout -f .)" "$want"$'\n\n'
  has "$(stdout --json --by-file .)" '"code":5,"bytes":10,"by_file":[{"path":"b.rs","lines":3,"blank":0,"comment":0,"code":3,"bytes":6},{"path":"a.rs",'
  lacks "$(stdout --json .)" by_file
}

by_file_drops_leading_directories_from_a_long_path_but_never_the_name() {
  scratch
  put api/migrations/20260912010125_result_matching.sql $'x\n'
  put deep/this_file_name_is_far_longer_than_forty_chars.rs $'x\n'
  put a_bare_name_that_is_far_longer_than_forty_chars.rs $'x\n'
  put exactly/forty/characters/long/path/a.rs $'x\n'
  local table
  table=$(stdout -f .)
  shown() {
    local l
    l=$(printf '%s\n' "$table" | grep -F -- "$1" | head -1)
    printf '%s' "${l%%  *}"
  }
  is "$(shown result_matching)" "…/20260912010125_result_matching.sql"
  is "$(shown this_file_name)" "…/this_file_name_is_far_longer_than_forty_chars.rs"
  is "$(shown a_bare_name)" "a_bare_name_that_is_far_longer_than_forty_chars.rs"
  is "$(shown exactly)" "exactly/forty/characters/long/path/a.rs"
  has "$(stdout --json -f .)" '"path":"api/migrations/20260912010125_result_matching.sql"'
}

languages_lists_the_table() {
  scratch
  run --json --languages nope
  is "$status" 0
  local text=$out
  cells() { printf '%s' "$1" | sed -E 's/  +/\n/g' | sed -E 's/^ +| +$//g' | grep -v '^$' | paste -sd '|' -; }
  is "$(cells "$(printf '%s' "$text" | sed -n 2p)")" "Language|Files"
  local firsts
  firsts=$(printf '%s' "$text" | tail -n +4 | grep -v '^ ')
  local rows
  rows=$(printf '%s\n' "$firsts" | wc -l | tr -d ' ')
  has "$(cat "$ROOT/README.md")" "in $rows languages."
  printf '%s\n' "$firsts" | awk '{print $1}' | LC_ALL=C sort -c || fail "names are not sorted"
  is "$(cells "$(printf '%s\n' "$firsts" | grep '^Ruby ')")" "Ruby|.rb .rake .gemspec Gemfile Rakefile"
  ! printf '%s' "$text" | grep -q ' $' || fail "trailing spaces"
  lacks "$text" "PHP code"
  has "$(cat "$ROOT/README.md")" $'## Languages\n\n```\n'"$text"'```'$'\n'
}

a_dot_git_entry_is_never_entered_or_counted() {
  scratch
  put a.rs $'x\n'
  put .git/x.rs $'y\n'
  put sub/.git $'z\n'
  put sub/b.rs $'w\n'
  local json
  for flags in "--json ." "--json --no-ignore ."; do
    # shellcheck disable=SC2086
    json=$(stdout $flags)
    is "$(files_of "$json" Rust)" 2 "$json"
    has "$json" '"skipped":{"text":{"files":0,'
  done
}

ignore_files_above_path_apply_up_to_the_nearest_dot_git() {
  scratch
  mkdir .git
  put .gitignore $'*.md\n'
  put mid/.gitignore $'*.zig\n'
  put mid/sub/a.md $'x\n'
  put mid/sub/a.zig $'x\n'
  put mid/sub/a.rs $'x\n'
  local json
  json=$(stdout --json mid/sub)
  is "$(files_of "$json" Rust)" 1
  is "$(files_of "$json" Markdown)" 0
  is "$(files_of "$json" Zig)" 0
  json=$(stdout --json --no-ignore mid/sub)
  is "$(files_of "$json" Markdown)" 1
  is "$(files_of "$json" Zig)" 1
}

an_escaped_trailing_space_matches_a_name_ending_in_a_space() {
  scratch
  put .gitignore $'sp.rs\\ \n'
  put "sp.rs " $'x\n'
  put sp.rs $'y\n'
  local json
  json=$(stdout --json .)
  is "$(files_of "$json" Rust)" 1
  has "$json" '"skipped":{"text":{"files":1,'
}

more_than_ten_labels_fold_and_one_binary_file_is_singular() {
  scratch
  local i
  for ((i = 1; i <= 12; i++)); do put "f$i.ext$i" $'x\n'; done
  printf '\0\0' >blob.bin
  run .
  has "$out" "2 more labels"
  has "$out" $'\n1 binary file, 2 B: .bin 1\n'
}

an_unreadable_directory_inside_a_walk_is_skipped_with_a_warning() {
  scratch
  put a.rs $'x\n'
  put locked/b.rs $'y\n'
  unreadable locked
  run --json .
  is "$status" 0
  is "$(files_of "$out" Rust)" 1
  has "$err" "cannot read"
}

no_color_and_jobs_do_not_change_output_and_path_defaults_to_dot() {
  scratch
  put a.rs $'x\n'
  run .
  cp "$SCRATCH/.out" "$SCRATCH/.want"
  run --no-color .
  cmp -s "$SCRATCH/.want" "$SCRATCH/.out" || fail "--no-color changed the output" "$out"
  is "$(files_of "$(stdout --json)" Rust)" 1
  run --json "$ROOT/fixtures/cases"
  cp "$SCRATCH/.out" "$SCRATCH/.want"
  run --json --jobs 1 "$ROOT/fixtures/cases"
  cmp -s "$SCRATCH/.want" "$SCRATCH/.out" || fail "--jobs 1 changed the output" "$out"
}

a_path_with_dot_dot_components_is_counted() {
  scratch
  mkdir .git
  put sub/a.rs $'x\n'
  run --json sub/../sub
  is "$status" 0
  is "$(files_of "$out" Rust)" 1
}

json_escapes_a_label_and_the_table_separates_thousands() {
  scratch
  put 'na"me\x' $'x\n'
  has "$(stdout --json .)" '"label":"na\"me\\x",'
  local big="" i
  for ((i = 0; i < 1234; i++)); do big+=$'x\n'; done
  put big.rs "$big"
  has "$(stdout .)" "1,234"
}

# ---- Checks beyond tests/cli.rs ----------------------------------------------
# The Rust loc fails the last two: it panics on a line of only spaces, and
# sizes a linked PATH as the link, where SPEC follows it.

json_escapes_control_bytes_as_u_escapes() {
  scratch
  put $'c\x01\x1f\x7f.rs' $'x\n'
  put $'l.\x02' $'x\n'
  local json
  json=$(stdout --json --by-file .)
  has "$json" '"path":"c\u0001\u001f'$'\x7f''.rs"'
  has "$json" '"label":".\u0002"'
}

styled_output_has_the_bar_dots_and_dim_rules() {
  scratch
  put a.rs $'x\n'
  script -q /dev/null true >/dev/null 2>&1 </dev/null || return 0  # BSD script only
  local styled
  styled=$(env -u NO_COLOR TERM=xterm script -q /dev/null "$LOC" . </dev/null | tr -d '\r')
  has "$styled" $'\e[38;2;222;165;132m\e[48;2;222;165;132m'"█"
  has "$styled" $'\e[38;2;222;165;132m'"●"$'\e[0m Rust'
  has "$styled" $'\e[2m'"─"
  has "$styled" $'\e[1m  Language'
}

an_ignore_line_of_only_spaces_has_no_effect() {
  scratch
  mkdir .git
  put .gitignore $'   \n*.log\n'
  put a.rs $'x\n'
  put b.log $'x\n'
  run --json .
  is "$status" 0
  has "$out" '"total":{"files":1,'
  run --json -e ' ' .
  is "$status" 0
}

a_linked_path_reports_its_target_size() {
  scratch
  printf 'x\0yyyyyyyyy' >big.png
  ln -s big.png l.png
  has "$(stdout --json l.png)" '"binary":{"files":1,"bytes":11,'
}

# ---- Running -------------------------------------------------------------------

CHECKS=(
  table_matches_expected
  json_matches_expected
  json_no_ignore_matches_expected
  by_file_json_matches_expected_files
  help_exits_0_and_usage_errors_exit_1
  missing_path_exits_2
  unreadable_file_path_exits_2
  unreadable_directory_path_exits_2
  unreadable_file_inside_a_walk_is_skipped_and_exits_0
  a_symlink_given_as_path_is_followed
  a_symlink_inside_a_walk_is_neither_followed_nor_counted
  help_matches_the_spec
  readme_usage_is_the_help_output
  several_paths_sum_and_a_file_reached_twice_counts_once
  a_missing_path_among_several_exits_2_with_no_output
  double_dash_ends_the_flags
  exclude_matches_like_a_gitignore_line
  exclude_decides_before_gitignore_and_applies_with_no_ignore
  exclude_is_relative_to_each_path_and_never_path_itself
  exclude_without_a_pattern_is_a_usage_error
  only_counts_what_a_gitignore_line_would_skip
  only_leaves_gitignore_in_force_and_applies_with_no_ignore
  only_is_relative_to_each_path_and_a_file_path_always_counts
  only_decides_which_files_by_file_lists
  only_without_a_pattern_is_a_usage_error
  exclude_lang_drops_the_language_from_every_total_and_label
  a_dot_m_file_is_mumps_by_its_first_line_and_excluded_as_that_language
  exclude_lang_leaves_embedded_regions_with_their_file
  exclude_lang_with_an_unknown_or_missing_name_is_a_usage_error
  only_lang_counts_named_languages_and_reports_only_their_misses
  only_lang_reads_an_extensionless_file_only_when_a_named_language_has_shebangs
  only_lang_reads_a_dot_m_file_when_one_of_its_languages_is_named
  only_lang_leaves_embedded_regions_with_their_file
  only_lang_drops_a_file_path_of_another_language
  only_lang_with_a_bad_name_or_with_exclude_lang_is_a_usage_error
  short_flags_are_exact_aliases_that_take_the_next_argument_and_do_not_bundle
  by_file_lists_files_under_their_language_by_code_then_path
  by_file_drops_leading_directories_from_a_long_path_but_never_the_name
  languages_lists_the_table
  a_dot_git_entry_is_never_entered_or_counted
  ignore_files_above_path_apply_up_to_the_nearest_dot_git
  an_escaped_trailing_space_matches_a_name_ending_in_a_space
  more_than_ten_labels_fold_and_one_binary_file_is_singular
  an_unreadable_directory_inside_a_walk_is_skipped_with_a_warning
  no_color_and_jobs_do_not_change_output_and_path_defaults_to_dot
  a_path_with_dot_dot_components_is_counted
  json_escapes_a_label_and_the_table_separates_thousands
  json_escapes_control_bytes_as_u_escapes
  styled_output_has_the_bar_dots_and_dim_rules
  an_ignore_line_of_only_spaces_has_no_effect
  a_linked_path_reports_its_target_size
)

[ -x "$LOC" ] || { echo "no $LOC; build it with rig/build.sh" >&2; exit 2; }

passed=0
failed=0
for name in "${@:-${CHECKS[@]}}"; do
  (set -eu; "$name") >"$SCRATCH/.log" 2>&1
  if [ $? -eq 0 ]; then
    passed=$((passed + 1))
    echo "ok    $name"
  else
    failed=$((failed + 1))
    echo "FAIL  $name"
    cat "$SCRATCH/.log"
  fi
done
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
