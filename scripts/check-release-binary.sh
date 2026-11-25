#!/bin/sh
# shellcheck shell=sh
# Confirms a Release PaperGlide.app has no debug or test launch hooks and
# carries the shipping version and encryption flag. Pass the .app bundle.
set -eu

app=${1:?usage: check-release-binary.sh PaperGlide.app}
binary="$app/PaperGlide"
plist="$app/Info.plist"

if [ ! -f "$binary" ] || [ ! -f "$plist" ]; then
    echo "Release app is missing a binary or Info.plist: $app" >&2
    exit 1
fi

found=$(strings -a "$binary" | grep -F -e '-paperGlideForceCrash' -e '-paperGlideEndScore' -e '-paperGlideWorstCaseDeath' -e '-paperGlideSeed' -e '-paperGlideGuidedStride' -e 'paperGlideForceCrash' -e 'paperGlideEndScore' -e 'paperGlideWorstCaseDeath' -e 'paperGlideSeed' -e 'paperGlideGuidedStride' || true)
if [ -n "$found" ]; then
    echo "Release binary contains a debug or test launch hook:" >&2
    echo "$found" >&2
    exit 1
fi

python3 - "$plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    info = plistlib.load(handle)
encryption = info.get("ITSAppUsesNonExemptEncryption")
short = info.get("CFBundleShortVersionString")
build = str(info.get("CFBundleVersion"))
if encryption is not False:
    sys.exit(f"ITSAppUsesNonExemptEncryption is {encryption!r}, expected false")
if short != "1.0":
    sys.exit(f"CFBundleShortVersionString is {short!r}, expected 1.0")
if build != "1":
    sys.exit(f"CFBundleVersion is {build!r}, expected 1")
print(f"Release binary has no test hooks. version {short} ({build}), encryption exempt flag false")
PY
