#!/bin/zsh
set -euo pipefail

MODE="${1:-run}"
EXECUTABLE_NAME="ScrollDolmeng"
BUNDLE_ID="kim.chansuk.ScrollDolmeng"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="/Applications/울트라돌멩의원핑거스크롤.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/build_app.sh" >/dev/null

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --debug --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        sleep 1
        pgrep -x "$EXECUTABLE_NAME" >/dev/null
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
