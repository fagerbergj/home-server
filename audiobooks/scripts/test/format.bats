#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../format.sh"

setup() {
    TMPDIR="$(mktemp -d)"
    SOURCE="$TMPDIR/Andy Weir - Project Hail Mary"
    DEST="$TMPDIR/Andy Weir/Project Hail Mary"
    mkdir -p "$SOURCE" "$DEST"

    for i in 01 02 03; do
        touch "$SOURCE/Andy Weir - Project Hail Mary - $i.mp3"
    done
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "shows usage when no args given" {
    run bash "$SCRIPT"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Usage"* ]]
}

@test "errors if source does not exist" {
    run bash "$SCRIPT" "/nonexistent" "$DEST"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not a directory"* ]]
}

@test "errors if dest does not exist" {
    run bash "$SCRIPT" "$SOURCE" "/nonexistent"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"does not exist"* ]]
}

@test "errors if source is empty" {
    empty="$TMPDIR/empty"
    mkdir -p "$empty"
    run bash "$SCRIPT" "$empty" "$DEST"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No files found"* ]]
}

@test "detects and prints common prefix" {
    run bash "$SCRIPT" "$SOURCE" "$DEST"
    [[ "$output" == *"Andy Weir - Project Hail Mary - "* ]]
}

@test "dry run shows renames without moving files" {
    run bash "$SCRIPT" "$SOURCE" "$DEST"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"01.mp3"* ]]
    [[ "$output" == *"dry run"* ]]
    # files should still be in source
    [[ -f "$SOURCE/Andy Weir - Project Hail Mary - 01.mp3" ]]
    # dest should be empty
    [[ -z "$(ls -A "$DEST")" ]]
}

@test "apply moves and strips prefix from files" {
    run bash "$SCRIPT" "$SOURCE" "$DEST" --apply
    [[ "$status" -eq 0 ]]
    [[ -f "$DEST/01.mp3" ]]
    [[ -f "$DEST/02.mp3" ]]
    [[ -f "$DEST/03.mp3" ]]
    [[ ! -f "$SOURCE/Andy Weir - Project Hail Mary - 01.mp3" ]]
}

@test "apply reports correct file count" {
    run bash "$SCRIPT" "$SOURCE" "$DEST" --apply
    [[ "$output" == *"3 file(s) moved"* ]]
}

@test "dry run reports correct file count" {
    run bash "$SCRIPT" "$SOURCE" "$DEST"
    [[ "$output" == *"3 file(s) would be moved"* ]]
}
