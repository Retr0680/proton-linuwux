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
FD_FILE="$SOURCE_DIR/wine/server/fd.c"
WINE_INF_FILE="$SOURCE_DIR/wine/loader/wine.inf.in"
PROTON_FILE="$SOURCE_DIR/proton"

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

if [[ ! -f "$FD_FILE" ]]
then
    echo "Error: Wine server fd.c not found:" >&2
    echo "$FD_FILE" >&2
    exit 1
fi

if [[ ! -f "$WINE_INF_FILE" ]]
then
    echo "Error: Wine loader wine.inf.in not found:" >&2
    echo "$WINE_INF_FILE" >&2
    exit 1
fi

if grep -Fq 'HKLM,System\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001,"HwProfileGuid",,"{12345678-1234-1234-1234-123456789012}"' "$WINE_INF_FILE"
then
    echo "Error: LinUwUx HwProfileGuid is already defined in wine.inf.in" >&2
    exit 1
fi

if [[ ! -f "$PROTON_FILE" ]]
then
    echo "Error: Proton launcher script not found:" >&2
    echo "$PROTON_FILE" >&2
    exit 1
fi

if grep -Fq '"winmm": "n,b",' "$PROTON_FILE" ||
   grep -Fq '"version.dll": "n,b",' "$PROTON_FILE" ||
   grep -Fq '"reflex.dll": "n,b",' "$PROTON_FILE" ||
   grep -Fq 'if "PROTON_DISABLE_LSTEAMCLIENT" not in os.environ:' "$PROTON_FILE"
then
    echo "Error: LinUwUx proton overrides are already present" >&2
    exit 1
fi

PROTON_DLL_OVERRIDE_ANCHOR_COUNT="$(
    grep -c '^                "winebth.sys": "d", #disable winebth.sys as it crashes winedevice.exe$' "$PROTON_FILE" || true
)"

if [[ "$PROTON_DLL_OVERRIDE_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one dlloverrides anchor in proton" >&2
    echo "Found: $PROTON_DLL_OVERRIDE_ANCHOR_COUNT" >&2
    exit 1
fi

PROTON_LSTEAMCLIENT_ANCHOR_COUNT="$(
    grep -c '^        # CW Bug 21737. Locoland executable happens to be steam.exe.$' "$PROTON_FILE" || true
)"

if [[ "$PROTON_LSTEAMCLIENT_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one Locoland anchor in proton" >&2
    echo "Found: $PROTON_LSTEAMCLIENT_ANCHOR_COUNT" >&2
    exit 1
fi

WINE_INF_OVERRIDES_ANCHOR_COUNT="$(
    grep -c '^;;Other app-specific overrides$' "$WINE_INF_FILE" || true
)"

if [[ "$WINE_INF_OVERRIDES_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one app-specific overrides anchor in wine.inf.in" >&2
    echo "Found: $WINE_INF_OVERRIDES_ANCHOR_COUNT" >&2
    exit 1
fi

FD_TIME_ANCHOR_COUNT="$(
    grep -c '^timeout_t monotonic_time;$' "$FD_FILE" || true
)"

if [[ "$FD_TIME_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one faketime state anchor in fd.c" >&2
    echo "Found: $FD_TIME_ANCHOR_COUNT" >&2
    exit 1
fi

FD_CURRENT_TIME_ANCHOR_COUNT="$(
    grep -c 'current_time = (timeout_t)now\.tv_sec \* TICKS_PER_SEC + now\.tv_usec \* 10 + ticks_1601_to_1970;' "$FD_FILE" || true
)"

if [[ "$FD_CURRENT_TIME_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one current_time anchor in fd.c" >&2
    echo "Found: $FD_CURRENT_TIME_ANCHOR_COUNT" >&2
    exit 1
fi

FD_LAST_LINE="$(
    awk 'NF { line = $0 } END { print line }' "$FD_FILE"
)"

if [[ "$FD_LAST_LINE" != "}" ]]
then
    echo "Error: unexpected end of fd.c" >&2
    echo "Last non-empty line: $FD_LAST_LINE" >&2
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
    grep -c '^#include "wine/debug.h"$' "$SIGNAL_FILE" || true
)"

if [[ "$INCLUDE_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one wine/debug.h include anchor in signal_x86_64.c" >&2
    echo "Found: $INCLUDE_ANCHOR_COUNT" >&2
    exit 1
fi

SIGSYS_ANCHOR_COUNT="$(
    awk '
        /^#ifdef HAVE_SECCOMP$/ {
            in_legacy_sigsys = 1
            next
        }

        in_legacy_sigsys && /^#endif$/ {
            in_legacy_sigsys = 0
        }

        /^#if defined\(__APPLE__\) \|\| defined\(__linux__\)$/ {
            in_modern_sigsys = 1
            next
        }

        in_modern_sigsys && /^#endif$/ {
            in_modern_sigsys = 0
        }

        (in_legacy_sigsys || in_modern_sigsys) &&
        /TRACE_\(seh\)\("SIGSYS, rax/ {
            count++
        }

        END { print count + 0 }
    ' "$SIGNAL_FILE"
)"

if [[ "$SIGSYS_ANCHOR_COUNT" -ne 1 ]]
then
    echo "Error: expected exactly one SIGSYS anchor in signal_x86_64.c" >&2
    echo "Found: $SIGSYS_ANCHOR_COUNT" >&2
    exit 1
fi

CPUID_ANCHOR_COUNT="$(
    awk '
        /^static void segv_handler\( int signal, siginfo_t \*siginfo, void \*sigcontext \)$/ {
            in_segv = 1
            next
        }

        in_segv && /^}$/ {
            in_segv = 0
        }

        in_segv && /rec\.ExceptionAddress = \(void \*\)RIP_sig\(ucontext\);/ {
            count++
        }

        END { print count + 0 }
    ' "$SIGNAL_FILE"
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
FD_TMP="$(mktemp)"
WINE_INF_TMP="$(mktemp)"
PROTON_TMP="$(mktemp)"
SIGNAL_BACKUP="$(mktemp)"
PROTOCOL_BACKUP="$(mktemp)"
FD_BACKUP="$(mktemp)"
WINE_INF_BACKUP="$(mktemp)"
PROTON_BACKUP="$(mktemp)"

cp -p "$SIGNAL_FILE" "$SIGNAL_BACKUP"
cp -p "$PROTOCOL_FILE" "$PROTOCOL_BACKUP"
cp -p "$FD_FILE" "$FD_BACKUP"
cp -p "$WINE_INF_FILE" "$WINE_INF_BACKUP"
cp -p "$PROTON_FILE" "$PROTON_BACKUP"

cleanup()
{
    rm -f "$SIGNAL_TMP" "$PROTOCOL_TMP" "$FD_TMP" "$WINE_INF_TMP" "$PROTON_TMP" \
          "$SIGNAL_BACKUP" "$PROTOCOL_BACKUP" "$FD_BACKUP" "$WINE_INF_BACKUP" "$PROTON_BACKUP"
}

rollback()
{
    cp -p "$SIGNAL_BACKUP" "$SIGNAL_FILE"
    cp -p "$PROTOCOL_BACKUP" "$PROTOCOL_FILE"
    cp -p "$FD_BACKUP" "$FD_FILE"
    cp -p "$WINE_INF_BACKUP" "$WINE_INF_FILE"
    cp -p "$PROTON_BACKUP" "$PROTON_FILE"
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
    /^#include "wine\/debug\.h"$/ {
    print
    print "#include \"linuwux_hooks.h\""
    print ""
    next
}

/^#ifdef HAVE_SECCOMP$/ {
    in_legacy_sigsys = 1
    print
    next
}

in_legacy_sigsys && /^#endif$/ {
    in_legacy_sigsys = 0
    print
    next
}

/^#if defined\(__APPLE__\) \|\| defined\(__linux__\)$/ {
    in_modern_sigsys = 1
    print
    next
}

in_modern_sigsys && /^#endif$/ {
    in_modern_sigsys = 0
    print
    next
}

(in_legacy_sigsys || in_modern_sigsys) &&
/TRACE_\(seh\)\("SIGSYS, rax/ {
    print "    if (linuwux_handle_sigsys(sigcontext))"
    print "        return;"
    print ""
}

/^static void segv_handler\( int signal, siginfo_t \*siginfo, void \*sigcontext \)$/ {
    in_segv = 1
    print
    next
}

in_segv && /^}$/ {
    in_segv = 0
    print
    next
}

in_segv && /rec\.ExceptionAddress = \(void \*\)RIP_sig\(ucontext\);/ {
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

awk '
    /^timeout_t monotonic_time;$/ {
        print
        print "static timeout_t faketime = 0;"
        next
    }

    /current_time = \(timeout_t\)now\.tv_sec \* TICKS_PER_SEC \+ now\.tv_usec \* 10 \+ ticks_1601_to_1970;/ {
        sub(/;$/, " - faketime;")
        print
        next
    }

    { print }
' "$FD_FILE" > "$FD_TMP"

cat >> "$FD_TMP" <<'EOF'

DECL_HANDLER(set_faketime)
{
    faketime = ((current_time >> 32) - req->faketime) << 32;
}
EOF

cp "$WINE_INF_FILE" "$WINE_INF_TMP"

cat >> "$WINE_INF_TMP" <<'EOF'
HKLM,System\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001,"HwProfileGuid",,"{12345678-1234-1234-1234-123456789012}"
EOF

awk '
    /^                "winebth.sys": "d", #disable winebth.sys as it crashes winedevice.exe$/ {
        print
        print "                \"winmm\": \"n,b\","
        print "                \"version.dll\": \"n,b\","
        print "                \"reflex.dll\": \"n,b\","
        next
    }

    /^        # CW Bug 21737. Locoland executable happens to be steam.exe.$/ {
        print "        if \"PROTON_DISABLE_LSTEAMCLIENT\" not in os.environ:"
        print "            os.environ[\"PROTON_DISABLE_LSTEAMCLIENT\"] = \"1\""
        print "            self.env[\"PROTON_DISABLE_LSTEAMCLIENT\"] = \"1\""
        print ""
        print
        next
    }

    { print }
' "$PROTON_FILE" > "$PROTON_TMP"

if ! grep -Fq '"winmm": "n,b",' "$PROTON_TMP"
then
    echo "Error: failed to prepare winmm override in proton" >&2
    exit 1
fi

if ! grep -Fq '"version.dll": "n,b",' "$PROTON_TMP"
then
    echo "Error: failed to prepare version.dll override in proton" >&2
    exit 1
fi

if ! grep -Fq '"reflex.dll": "n,b",' "$PROTON_TMP"
then
    echo "Error: failed to prepare reflex.dll override in proton" >&2
    exit 1
fi

if ! grep -Fq 'if "PROTON_DISABLE_LSTEAMCLIENT" not in os.environ:' "$PROTON_TMP"
then
    echo "Error: failed to prepare PROTON_DISABLE_LSTEAMCLIENT guard in proton" >&2
    exit 1
fi

if ! grep -Fq 'os.environ["PROTON_DISABLE_LSTEAMCLIENT"] = "1"' "$PROTON_TMP"
then
    echo "Error: failed to prepare PROTON_DISABLE_LSTEAMCLIENT os.environ value in proton" >&2
    exit 1
fi

if ! grep -Fq 'self.env["PROTON_DISABLE_LSTEAMCLIENT"] = "1"' "$PROTON_TMP"
then
    echo "Error: failed to prepare PROTON_DISABLE_LSTEAMCLIENT self.env value in proton" >&2
    exit 1
fi

if ! grep -Fq 'HKLM,System\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001,"HwProfileGuid",,"{12345678-1234-1234-1234-123456789012}"' "$WINE_INF_TMP"
then
    echo "Error: failed to prepare HwProfileGuid in wine.inf.in" >&2
    exit 1
fi

if ! grep -Fq 'static timeout_t faketime = 0;' "$FD_TMP"
then
    echo "Error: failed to prepare faketime state in fd.c" >&2
    exit 1
fi

if ! grep -Fq 'current_time = (timeout_t)now.tv_sec * TICKS_PER_SEC + now.tv_usec * 10 + ticks_1601_to_1970 - faketime;' "$FD_TMP"
then
    echo "Error: failed to prepare faketime-adjusted current_time in fd.c" >&2
    exit 1
fi

if ! grep -Fq 'DECL_HANDLER(set_faketime)' "$FD_TMP"
then
    echo "Error: failed to prepare set_faketime handler in fd.c" >&2
    exit 1
fi

if ! grep -Fq 'faketime = ((current_time >> 32) - req->faketime) << 32;' "$FD_TMP"
then
    echo "Error: failed to prepare set_faketime calculation in fd.c" >&2
    exit 1
fi

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
cp "$FD_TMP" "$FD_FILE"
cp "$WINE_INF_TMP" "$WINE_INF_FILE"
cp "$PROTON_TMP" "$PROTON_FILE"
cp "$SIGNAL_TMP" "$SIGNAL_FILE"
cp "$HOOKS_SOURCE" "$HOOKS_DEST"
