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
PROTOCOL_FILE="$SOURCE_DIR/wine/server/protocol.def"

if [[ ! -f "$HOOKS_SOURCE" ]]
then
    echo "Error: LinUwUx hooks source not found:" >&2
    echo "$HOOKS_SOURCE" >&2
    exit 1
fi

if [[ -e "$HOOKS_DEST" ]]
then
    echo "Error: LinUwUx hooks destination already exists:" >&2
    echo "$HOOKS_DEST" >&2
    exit 1
fi

if [[ ! -f "$SIGNAL_FILE" ]]
then
    echo "Error: signal_x86_64.c not found:" >&2
    echo "$SIGNAL_FILE" >&2
    exit 1
fi

if [[ ! -f "$PROTOCOL_FILE" ]]
then
    echo "Error: Wine server protocol definition not found:" >&2
    echo "$PROTOCOL_FILE" >&2
    exit 1
fi

if grep -Fq '@REQ(set_faketime)' "$PROTOCOL_FILE"
then
    echo "Error: set_faketime is already defined in protocol.def" >&2
    exit 1
fi

PROTOCOL_LAST_LINE="$(
    awk 'NF { line = $0 } END { print line }' "$PROTOCOL_FILE"
)"

if [[ "$PROTOCOL_LAST_LINE" != "@END" ]]
then
    echo "Error: unexpected end of protocol.def" >&2
    echo "Last non-empty line: $PROTOCOL_LAST_LINE" >&2
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

CPUID_ANCHOR_COUNT="$(
    grep -c 'rec.ExceptionAddress = (void \*)RIP_sig(ucontext);' "$SIGNAL_FILE" || true
)"

if [[ "$CPUID_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one CPUID/segv anchor in signal_x86_64.c" >&2
    echo "Found: $CPUID_ANCHOR_COUNT" >&2
    exit 1
fi

CPUID_INIT_ANCHOR_COUNT="$(
    grep -c 'if (sigaction( SIGSEGV, &sig_act, NULL ) == -1) goto error;' "$SIGNAL_FILE" || true
)"

if [[ "$CPUID_INIT_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one CPUID init anchor in signal_x86_64.c" >&2
    echo "Found: $CPUID_INIT_ANCHOR_COUNT" >&2
    exit 1
fi

SIGNAL_TMP="$(mktemp)"
PROTOCOL_TMP="$(mktemp)"
SIGNAL_BACKUP="$(mktemp)"
PROTOCOL_BACKUP="$(mktemp)"

cp -p "$SIGNAL_FILE" "$SIGNAL_BACKUP"
cp -p "$PROTOCOL_FILE" "$PROTOCOL_BACKUP"

cleanup()
{
    rm -f "$SIGNAL_TMP" "$PROTOCOL_TMP" \
          "$SIGNAL_BACKUP" "$PROTOCOL_BACKUP"
}

rollback()
{
    cp -p "$SIGNAL_BACKUP" "$SIGNAL_FILE"
    cp -p "$PROTOCOL_BACKUP" "$PROTOCOL_FILE"
    rm -f "$HOOKS_DEST"
}

trap rollback ERR
trap cleanup EXIT

cp "$PROTOCOL_FILE" "$PROTOCOL_TMP"

cat >> "$PROTOCOL_TMP" <<'EOF'

@REQ(set_faketime)
    unsigned __int64 faketime;
@REPLY
@END
EOF

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

    /rec\.ExceptionAddress = \(void \*\)RIP_sig\(ucontext\);/ {
        print "    if (linuwux_handle_cpuid(siginfo, ucontext))"
        print "        return;"
        print ""
    }

    /if \(sigaction\( SIGSEGV, &sig_act, NULL \) == -1\) goto error;/ {
        print
        print "    detect_cpu_vendor();"
        print "    syscall(SYS_arch_prctl, ARCH_SET_CPUID, 0);"
        next
    }

    { print }
' "$SIGNAL_FILE" > "$SIGNAL_TMP"

if ! grep -Fq '@REQ(set_faketime)' "$PROTOCOL_TMP"
then
    echo "Error: failed to prepare set_faketime in protocol.def" >&2
    exit 1
fi

if ! grep -Fq '#include "linuwux_hooks.h"' "$SIGNAL_TMP"
then
    echo "Error: failed to prepare LinUwUx hooks in signal_x86_64.c" >&2
    exit 1
fi

cp "$PROTOCOL_TMP" "$PROTOCOL_FILE"
cp "$SIGNAL_TMP" "$SIGNAL_FILE"
cp "$HOOKS_SOURCE" "$HOOKS_DEST"
