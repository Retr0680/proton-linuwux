#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ $# -ne 1 ]]
then
    echo "Usage: $0 <proton-source-dir>" >&2
    exit 1
fi

SOURCE_DIR="$(realpath "$1")"

if [[ ! -d "$SOURCE_DIR/wine/dlls/ntdll/unix" ]]
then
    echo "Error: Wine ntdll Unix source directory not found:" >&2
    echo "$SOURCE_DIR/wine/dlls/ntdll/unix" >&2
    exit 1
fi

HOOKS_SOURCE="$ROOT_DIR/scripts/linuwux/linuwux_hooks.h"
HOOKS_DEST="$SOURCE_DIR/wine/dlls/ntdll/unix/linuwux_hooks.h"
SIGNAL_FILE="$SOURCE_DIR/wine/dlls/ntdll/unix/signal_x86_64.c"

if [[ ! -f "$HOOKS_SOURCE" ]]
then
    echo "Error: LinUwUx hooks source not found:" >&2
    echo "$HOOKS_SOURCE" >&2
    exit 1
fi

if [[ ! -f "$SIGNAL_FILE" ]]
then
    echo "Error: signal_x86_64.c not found:" >&2
    echo "$SIGNAL_FILE" >&2
    exit 1
fi

if grep -Fq '#include "linuwux_hooks.h"' "$SIGNAL_FILE"
then
    echo "Error: LinUwUx hooks are already included in signal_x86_64.c" >&2
    exit 1
fi

INCLUDE_ANCHOR_COUNT="$(
    grep -c '^#define NONAMELESSUNION$' "$SIGNAL_FILE" || true
)"

if [[ "$INCLUDE_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one NONAMELESSUNION anchor in signal_x86_64.c" >&2
    echo "Found: $INCLUDE_ANCHOR_COUNT" >&2
    exit 1
fi

SIGSYS_ANCHOR_COUNT="$(
    grep -c 'TRACE_(seh)("SIGSYS, rax' "$SIGNAL_FILE" || true
)"

if [[ "$SIGSYS_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one SIGSYS anchor in signal_x86_64.c" >&2
    echo "Found: $SIGSYS_ANCHOR_COUNT" >&2
    exit 1
fi

SIGNAL_TMP="$(mktemp)"

awk '
    /^#define NONAMELESSUNION$/ {
        print "#include \"linuwux_hooks.h\""
        print ""
    }

    /TRACE_\(seh\)\("SIGSYS, rax/ {
        print "    if (linuwux_handle_sigsys(sigcontext))"
        print "        return;"
        print ""
    }

    { print }
' "$SIGNAL_FILE" > "$SIGNAL_TMP"

mv "$SIGNAL_TMP" "$SIGNAL_FILE"

cp "$HOOKS_SOURCE" "$HOOKS_DEST"
