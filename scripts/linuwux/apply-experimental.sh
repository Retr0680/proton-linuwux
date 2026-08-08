#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINUWUX_DIR="$ROOT_DIR/scripts/linuwux"

LEGACY_REFLEX="${LINUWUX_LEGACY_REFLEX:-0}"

if [[ "$LEGACY_REFLEX" == "1" ]]
then
    HOOKS_FILE="$LINUWUX_DIR/linuwux_hooks_legacy.c"
    echo "Legacy Reflex: abilitato"
else
    HOOKS_FILE="$LINUWUX_DIR/linuwux_hooks.c"
    echo "Legacy Reflex: disabilitato"
fi

if [[ ! -f "$HOOKS_FILE" ]]
then
    echo "Errore: file hooks non trovato:"
    echo "$HOOKS_FILE"
    exit 1
fi

SOURCE_DIR="${1:-}"

if [[ -z "$SOURCE_DIR" ]]
then
    echo "Errore: directory sorgente non specificata."
    exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]
then
    echo "Errore: directory sorgente non trovata:"
    echo "$SOURCE_DIR"
    exit 1
fi

echo "== Applicazione LinUwUx experimental =="
echo "Sorgenti: $SOURCE_DIR"

WINE_UNIX_DIR="$SOURCE_DIR/wine/dlls/ntdll/unix"
HOOKS_TARGET="$WINE_UNIX_DIR/linuwux_hooks.c"

if [[ ! -d "$WINE_UNIX_DIR" ]]
then
    echo "Errore: directory Wine ntdll/unix non trovata:"
    echo "$WINE_UNIX_DIR"
    exit 1
fi

cp "$HOOKS_FILE" "$HOOKS_TARGET"

echo "Hooks copiati:"
echo "$HOOKS_TARGET"

insert_hooks_include() {
    local target="$WINE_UNIX_DIR/signal_x86_64.c"

    if [[ ! -f "$target" ]]
    then
        echo "Errore: signal_x86_64.c non trovato:"
        echo "$target"
        exit 1
    fi

    if grep -qF '#include "linuwux_hooks.c"' "$target"
    then
        echo "Include LinUwUx già presente."
        return
    fi

    local func_line

    func_line="$(
        grep -n '^static void sigsys_handler' "$target" |
        head -1 |
        cut -d: -f1
    )"

    if [[ -z "$func_line" ]]
    then
        echo "Errore: sigsys_handler non trovato in:"
        echo "$target"
        exit 1
    fi

    {
        head -n "$((func_line - 1))" "$target"
        echo '#include "linuwux_hooks.c"'
        echo
        tail -n "+$func_line" "$target"
    } > "$target.tmp"

    mv "$target.tmp" "$target"

    echo "Include LinUwUx inserito in signal_x86_64.c."
}

insert_hooks_include
