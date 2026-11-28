#!/bin/sh
set -eu

source_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
viewer="$source_dir/wob-model-viewer"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
desktop_id=com.rigelio.WoBModelViewer
portable_id="$desktop_id.Portable"

if [ ! -x "$viewer" ]; then
    echo "Make wob-model-viewer executable before registering file types." >&2
    exit 1
fi
for program in update-mime-database update-desktop-database; do
    if ! command -v "$program" >/dev/null; then
        echo "Missing $program. Install shared-mime-info and desktop-file-utils." >&2
        exit 1
    fi
done

mkdir -p "$data/mime/packages" "$data/applications" "$data/icons/hicolor/256x256/apps" "$data/wob-model-viewer"
# A per-user symlink keeps the portable folder name out of desktop Exec field codes.
launcher="$data/wob-model-viewer/portable"
if [ -e "$launcher" ] && [ ! -L "$launcher" ]; then
    echo "Cannot register the portable launcher at $launcher." >&2
    exit 1
fi
ln -sfnT -- "$viewer" "$launcher"
install -m644 "$source_dir/$desktop_id.xml" "$data/mime/packages/$portable_id.xml"
install -m644 "$source_dir/icon.png" "$data/icons/hicolor/256x256/apps/$portable_id.png"
{
    while IFS= read -r line; do
        case "$line" in
            Exec=*) printf '%s\n' 'Exec=sh -c "exec \\"\\${XDG_DATA_HOME:-\\$HOME/.local/share}/wob-model-viewer/portable\\" -- \\"\\$1\\"" sh %f' ;;
            Icon=*) printf 'Icon=%s\n' "$portable_id" ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < "$source_dir/$desktop_id.desktop"
} > "$data/applications/$portable_id.desktop"
update-mime-database "$data/mime"
update-desktop-database "$data/applications"
echo "WoB Model Viewer is available in Open With for GLB, glTF, FBX, OBJ, STL, 3MF and WOBVIEW."
