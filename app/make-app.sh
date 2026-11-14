#!/bin/sh
# swift build -> EnetDiag.app (Info.plist, ad-hoc signed, hardened runtime). Usage: ./make-app.sh [debug|release]
set -e
cd "$(dirname "$0")"
CONF=${1:-release}
swift build -c "$CONF"
APP=build/EnetDiag.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONF/EnetDiag" "$APP/Contents/MacOS/EnetDiag"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for l in en pl; do mkdir -p "$APP/Contents/Resources/$l.lproj"; printf '"CFBundleDisplayName" = "BMW ENET Diag";\n' > "$APP/Contents/Resources/$l.lproj/InfoPlist.strings"; done
codesign --force --sign - --options runtime "$APP"
echo "$PWD/$APP"
