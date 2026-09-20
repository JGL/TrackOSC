#!/bin/bash
#
# Builds, signs, notarizes, staples, and publishes BOTH macOS TrackOSC apps
# (Receiver and Sender) as assets of a single GitHub Release.
#
# One-time setup (see README "Releasing the macOS apps"):
#   1. A "Developer ID Application" certificate in your keychain
#      (Xcode → Settings → Accounts → Manage Certificates → +).
#   2. Notary credentials stored in the keychain:
#      xcrun notarytool store-credentials poseiosc-notary \
#        --apple-id you@example.com --team-id YOURTEAMID
#   3. gh CLI authenticated (gh auth login).
#
# Usage:
#   POSEIOSC_TEAM_ID=YOURTEAMID Scripts/release.sh [--dry-run]
#
# --dry-run does everything except create the GitHub release.

set -euo pipefail

cd "$(dirname "$0")/.."

# System paths first: Xcode's export step runs /usr/bin/rsync (openrsync),
# which spawns its server half by looking up `rsync` on PATH. With
# Homebrew's rsync found first, that server rejects openrsync's flags and
# xcodebuild fails with only "exportArchive Copy failed". gh and friends
# are still found further along PATH.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

: "${POSEIOSC_TEAM_ID:?Set POSEIOSC_TEAM_ID to your Apple Developer team ID}"

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
[[ -n "$VERSION" ]] || { echo "Could not read MARKETING_VERSION from project.yml"; exit 1; }

BUILD_DIR="build/release"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

# scheme:artifact-basename pairs
APPS=(
    "TrackOSCReceiver:TrackOSCReceiver"
    "TrackOSCSenderMac:TrackOSCSender"
)

echo "=== Releasing TrackOSC $VERSION (team $POSEIOSC_TEAM_ID) ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
sed "s/TEAM_ID_PLACEHOLDER/$POSEIOSC_TEAM_ID/" Scripts/ExportOptions.plist > "$EXPORT_OPTIONS"

ASSETS=()
for pair in "${APPS[@]}"; do
    SCHEME="${pair%%:*}"
    BASENAME="${pair##*:}"
    ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
    EXPORT_DIR="$BUILD_DIR/$SCHEME-export"
    APP="$EXPORT_DIR/$BASENAME.app"
    ZIP="$BUILD_DIR/$BASENAME-$VERSION-macOS.zip"

    echo "--- [$SCHEME] Archiving"
    xcodebuild -project TrackOSC.xcodeproj \
        -scheme "$SCHEME" \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE" \
        DEVELOPMENT_TEAM="$POSEIOSC_TEAM_ID" \
        archive | tail -1

    echo "--- [$SCHEME] Exporting with Developer ID signing"
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        -exportPath "$EXPORT_DIR" | tail -1

    echo "--- [$SCHEME] Notarizing (waits for Apple)"
    ditto -c -k --keepParent "$APP" "$BUILD_DIR/$SCHEME-notarize.zip"
    xcrun notarytool submit "$BUILD_DIR/$SCHEME-notarize.zip" \
        --keychain-profile poseiosc-notary \
        --wait

    echo "--- [$SCHEME] Stapling and verifying"
    xcrun stapler staple "$APP"
    spctl -a -vv "$APP"

    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Created $ZIP"
    ASSETS+=("$ZIP")
done

if [[ $DRY_RUN -eq 1 ]]; then
    echo "--- Dry run: skipping GitHub release. Artifacts:"
    printf '    %s\n' "${ASSETS[@]}"
    exit 0
fi

echo "--- Publishing GitHub release v$VERSION"
gh release create "v$VERSION" "${ASSETS[@]}" \
    --title "TrackOSC $VERSION" \
    --notes "macOS TrackOSC apps, $VERSION — signed and notarised; download, unzip, and open.

- **TrackOSCReceiver**: listens for OSC tracking data and visualises it, in 2D and 3D.
- **TrackOSCSender**: Mac camera (built-in, external, or iPhone via Continuity Camera) → Vision tracking → OSC.

The iOS sender is free on the App Store: https://apps.apple.com/app/trackosc/id6795593815. To build from source, see the README."

echo "=== Done: https://github.com/JGL/TrackOSC/releases/tag/v$VERSION ==="
