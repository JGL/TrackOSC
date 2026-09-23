#!/bin/bash
#
# Renders the app icons with Design/render_icons.swift and fills each macOS
# app's AppIcon.appiconset (16…1024 px) plus the README copies in Images/.
#
# Usage: Scripts/make_appiconsets.sh [icon names…]     (all when none given)
#
# Icon name → app folder. The Receiver and Mac Sender keep their existing
# names; every new app follows "<name>:<folder>:<Images basename>".

set -euo pipefail
cd "$(dirname "$0")/.."

MAP=(
    "receiver:Receiver:icon-mac-receiver"
    "sender-mac:SenderMac:icon-mac-sender"
    "recorder:Recorder:icon-mac-recorder"
    "speaker:Speaker:icon-mac-speaker"
    "router:Router:icon-mac-router"
    "colours:Colours:icon-mac-colours"
    "particles:Particles:icon-mac-particles"
    "text:Text:icon-mac-text"
    "synth:Synth:icon-mac-synth"
    "costumes:Costumes:icon-mac-costumes"
    "costumes3d:Costumes3D:icon-mac-costumes3d"
)

WANTED=("$@")
RENDER_DIR=$(mktemp -d)
trap 'rm -rf "$RENDER_DIR"' EXIT

swift Design/render_icons.swift "$RENDER_DIR" "${WANTED[@]}" > /dev/null

for entry in "${MAP[@]}"; do
    IFS=: read -r NAME FOLDER IMAGE <<< "$entry"
    if [[ ${#WANTED[@]} -gt 0 ]] && ! printf '%s\n' "${WANTED[@]}" | grep -qx "$NAME"; then
        continue
    fi
    [[ -d "$FOLDER" ]] || { echo "skip $NAME: no $FOLDER/ yet"; continue; }
    case "$NAME" in
        receiver) SRC="$RENDER_DIR/AppIcon-macOS-1024.png" ;;
        sender-mac) SRC="$RENDER_DIR/AppIcon-macOS-sender-1024.png" ;;
        *) SRC="$RENDER_DIR/AppIcon-macOS-$NAME-1024.png" ;;
    esac
    SET="$FOLDER/Assets.xcassets/AppIcon.appiconset"
    mkdir -p "$SET"
    for PX in 16 32 64 128 256 512 1024; do
        sips -z "$PX" "$PX" "$SRC" --out "$SET/icon_$PX.png" > /dev/null
    done
    if [[ ! -f "$SET/Contents.json" ]]; then
        cp Receiver/Assets.xcassets/AppIcon.appiconset/Contents.json "$SET/Contents.json"
    fi
    if [[ ! -f "$FOLDER/Assets.xcassets/Contents.json" ]]; then
        cp Receiver/Assets.xcassets/Contents.json "$FOLDER/Assets.xcassets/Contents.json"
    fi
    sips -z 512 512 "$SRC" --out "Images/$IMAGE.png" > /dev/null
    echo "filled $SET and Images/$IMAGE.png"
done
