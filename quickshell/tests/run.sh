#!/usr/bin/env bash
# Run the QML unit tests (Qt Quick Test). Headless; no compositor required.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
qr="$(readlink -f "$(command -v qmltestrunner)")"
export QML2_IMPORT_PATH="$(dirname "$qr")/../lib/qt-6/qml"
export QT_QPA_PLATFORM=offscreen
exec qmltestrunner -input "$here"
