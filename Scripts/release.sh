#!/bin/bash
#
# Builds, signs, notarises, staples, and publishes every macOS TrackOSC app
# as assets of a single GitHub Release.
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
#   POSEIOSC_TEAM_ID=YOURTEAMID Scripts/release.sh [--dry-run] [--only A,B] [--skip-notarize]
#
# --dry-run        everything except creating the GitHub release
# --only A,B       only these schemes (e.g. --only TrackOSCRecorder)
# --skip-notarize  sign and zip without notarising (local testing only)
# --resume         reuse the exports already in build/release (skip the
#                  archive and export steps), e.g. after notarisation failed
#
# Every app is archived and exported first, then all of them are submitted
# to Apple in one go and waited on together, so a release of many apps
# takes one notarisation round-trip rather than one per app.

set -euo pipefail

cd "$(dirname "$0")/.."

# System paths first: Xcode's export step runs /usr/bin/rsync (openrsync),
# which spawns its server half by looking up `rsync` on PATH. With
# Homebrew's rsync found first, that server rejects openrsync's flags and
# xcodebuild fails with only "exportArchive Copy failed". gh and friends
# are still found further along PATH.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

DRY_RUN=0
SKIP_NOTARIZE=0
RESUME=0
ONLY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        --resume) RESUME=1 ;;
        --only) ONLY="$2"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

: "${POSEIOSC_TEAM_ID:?Set POSEIOSC_TEAM_ID to your Apple Developer team ID}"

# House style: en dashes (U+2013), never em dashes (U+2014), anywhere in the
# repository. Refuse to release while any tracked text file has one.
if OFFENDERS=$(git grep -Il $'\xe2\x80\x94' -- .); then
    echo "Em dashes found in tracked files; replace them with en dashes before releasing:" >&2
    echo "$OFFENDERS" | sed 's/^/    /' >&2
    echo "Fix:  git grep -Ilz \$'\\xe2\\x80\\x94' | xargs -0 perl -CSD -pi -e 's/\\x{2014}/\\x{2013}/g'" >&2
    exit 1
fi

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
[[ -n "$VERSION" ]] || { echo "Could not read MARKETING_VERSION from project.yml"; exit 1; }

BUILD_DIR="build/release"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

# scheme:artifact-basename:release-note. Keep in the order the notes should read.
APPS=(
    "TrackOSCReceiver:TrackOSCReceiver:listens for OSC tracking data and visualises it, in 2D and 3D."
    "TrackOSCSenderMac:TrackOSCSender:Mac camera (built-in, external, or iPhone via Continuity Camera) → Vision tracking → OSC."
    "TrackOSCRecorder:TrackOSCRecorder:records the tracking stream to a .trackosc file and plays recordings back to any receiver."
    "TrackOSCSpeaker:TrackOSCSpeaker:reads the tracking stream aloud – appearances, recognised text and codes, periodic summaries – with every voice and speech option."
    "TrackOSCRouter:TrackOSCRouter:turns tracking events and values into MIDI, Shortcuts, key presses and HTTP requests, by rules."
    "TrackOSCColours:TrackOSCColours:gradients, colour fields and patterns driven by the tracking stream – fourteen modes, palettes, presets, full screen."
    "TrackOSCParticles:TrackOSCParticles:physics particles, trails and ghosts driven by the tracking stream – twelve modes."
    "TrackOSCText:TrackOSCText:kinetic typography from recognised text, codes and your own words – ten modes."
    "TrackOSCSynth:TrackOSCSynth:a 303-and-808-flavoured synth and drum machine played by the tracking stream – knobs, a step sequencer, mappings and MIDI out."
    "TrackOSCCostumes:TrackOSCCostumes:dresses tracked bodies, faces and hands in SVG costumes with named layers – three bundled, bring your own from Illustrator, Inkscape, Figma or Affinity."
    "TrackOSC3DCostumes:TrackOSC3DCostumes:dresses the 3D body pose in rigged USDZ models on Apple's motion-capture skeleton, folders of parts, or a mannequin."
)

if [[ -n "$ONLY" ]]; then
    SELECTED=()
    for pair in "${APPS[@]}"; do
        SCHEME="${pair%%:*}"
        if [[ ",$ONLY," == *",$SCHEME,"* ]]; then SELECTED+=("$pair"); fi
    done
    [[ ${#SELECTED[@]} -gt 0 ]] || { echo "--only matched no scheme in: ${APPS[*]%%:*}" >&2; exit 2; }
    APPS=("${SELECTED[@]}")
fi

echo "=== Releasing TrackOSC $VERSION (team $POSEIOSC_TEAM_ID) ==="
if [[ $RESUME -eq 0 ]]; then
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    sed "s/TEAM_ID_PLACEHOLDER/$POSEIOSC_TEAM_ID/" Scripts/ExportOptions.plist > "$EXPORT_OPTIONS"
    # The commit the release is built from: the tag points here even if
    # the branch moves on before a --resume publishes.
    git rev-parse HEAD > "$BUILD_DIR/COMMIT"
fi
RELEASE_COMMIT=$(cat "$BUILD_DIR/COMMIT" 2>/dev/null || git rev-parse HEAD)

scheme_of() { echo "${1%%:*}"; }
basename_of() { local rest="${1#*:}"; echo "${rest%%:*}"; }
note_of() { echo "${1#*:*:}"; }

# 1. Archive and export every app (unless resuming with exports in place).
for pair in "${APPS[@]}"; do
    if [[ $RESUME -eq 1 ]]; then
        [[ -d "$BUILD_DIR/$(scheme_of "$pair")-export/$(basename_of "$pair").app" ]] || { echo "--resume: no export for $(scheme_of "$pair")" >&2; exit 1; }
        continue
    fi
    SCHEME=$(scheme_of "$pair")
    BASENAME=$(basename_of "$pair")
    ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
    EXPORT_DIR="$BUILD_DIR/$SCHEME-export"

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
done

# 2. Submit every app to Apple, then wait for all of them.
if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    SUBMISSIONS=()
    for pair in "${APPS[@]}"; do
        SCHEME=$(scheme_of "$pair")
        APP="$BUILD_DIR/$SCHEME-export/$(basename_of "$pair").app"
        echo "--- [$SCHEME] Submitting for notarisation"
        ditto -c -k --keepParent "$APP" "$BUILD_DIR/$SCHEME-notarize.zip"
        ID=$(xcrun notarytool submit "$BUILD_DIR/$SCHEME-notarize.zip" \
            --keychain-profile poseiosc-notary --output-format json \
            | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -1)
        [[ -n "$ID" ]] || { echo "No submission id for $SCHEME" >&2; exit 1; }
        SUBMISSIONS+=("$SCHEME:$ID")
    done
    for entry in "${SUBMISSIONS[@]}"; do
        SCHEME="${entry%%:*}"
        ID="${entry##*:}"
        echo "--- [$SCHEME] Waiting for Apple ($ID)"
        xcrun notarytool wait "$ID" --keychain-profile poseiosc-notary
        STATUS=$(xcrun notarytool info "$ID" --keychain-profile poseiosc-notary | sed -n 's/.*status: *//p')
        [[ "$STATUS" == "Accepted" ]] || {
            echo "Notarisation of $SCHEME was $STATUS; see: xcrun notarytool log $ID --keychain-profile poseiosc-notary" >&2
            exit 1
        }
    done
else
    echo "--- Skipping notarisation (--skip-notarize)"
fi

# 3. Staple, verify and zip.
ASSETS=()
for pair in "${APPS[@]}"; do
    SCHEME=$(scheme_of "$pair")
    BASENAME=$(basename_of "$pair")
    APP="$BUILD_DIR/$SCHEME-export/$BASENAME.app"
    ZIP="$BUILD_DIR/$BASENAME-$VERSION-macOS.zip"
    if [[ $SKIP_NOTARIZE -eq 0 ]]; then
        echo "--- [$SCHEME] Stapling and verifying"
        xcrun stapler staple "$APP"
        spctl -a -vv "$APP"
    fi
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Created $ZIP"
    ASSETS+=("$ZIP")
done

if [[ $DRY_RUN -eq 1 ]]; then
    echo "--- Dry run: skipping GitHub release. Artifacts:"
    printf '    %s\n' "${ASSETS[@]}"
    exit 0
fi

NOTES="macOS TrackOSC apps, $VERSION – signed and notarised; download, unzip, and open.
"
for pair in "${APPS[@]}"; do
    NOTES+="
- **$(basename_of "$pair")**: $(note_of "$pair")"
done
NOTES+="

The iOS sender is free on the App Store: https://apps.apple.com/app/trackosc/id6795593815. To build from source, see the README."

echo "--- Publishing GitHub release v$VERSION"
gh release create "v$VERSION" "${ASSETS[@]}" \
    --target "$RELEASE_COMMIT" \
    --title "TrackOSC $VERSION" \
    --notes "$NOTES"

echo "=== Done: https://github.com/JGL/TrackOSC/releases/tag/v$VERSION ==="
