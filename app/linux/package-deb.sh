#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 BUILD_DIRECTORY" >&2
    exit 2
fi
source_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
build=$(cd -- "$1" && pwd -P)
pkg=wob-model-viewer
version=1.5.6
prefix="/opt/$pkg"

# Under WSL, TMPDIR uses the Linux filesystem while the export can stay on a
# Windows drive. The package requires real POSIX permissions and symlinks.
stage=$(mktemp -d "${TMPDIR:-/tmp}/$pkg.XXXXXXXX")
pending=
trap 'rm -rf -- "$stage"; if [ -n "$pending" ]; then rm -f -- "$pending"; fi' EXIT
if [ "$(stat -c %a "$stage")" != 700 ]; then
    echo "Package staging requires a POSIX filesystem. Set TMPDIR to a Linux directory." >&2
    exit 1
fi
umask 022
chmod 755 "$stage"
mkdir -p "$stage/DEBIAN" "$stage$prefix" "$stage/usr/bin" \
    "$stage/usr/share/applications" "$stage/usr/share/mime/packages" "$stage/usr/share/doc/$pkg" \
    "$stage/usr/share/icons/hicolor/256x256/apps"
install -m755 "$build/Linux/$pkg" "$stage$prefix/$pkg"
install -m755 "$build/Linux/wob-gif" "$stage$prefix/wob-gif"
ln -s "$prefix/$pkg" "$stage/usr/bin/$pkg"
install -m644 "$build/Linux/icon.png" "$stage/usr/share/icons/hicolor/256x256/apps/$pkg.png"
install -m644 "$build/Linux/README.en.md" "$build/Linux/README.cs.md" \
    "$build/Linux/PRODUCTION-RESOURCES.json" "$build/Linux/Godot-COPYRIGHT.txt" \
    "$build/Linux/Godot-LICENSE.txt" "$build/Linux/CormorantGaramond-OFL.txt" \
    "$build/Linux/Go-LICENSE.txt" "$build/Linux/RESOURCE-LICENSES.md" "$stage/usr/share/doc/$pkg/"
install -m644 "$build/Linux/LICENSE" "$stage/usr/share/doc/$pkg/copyright"

install -m644 "$source_dir/com.rigelio.WoBModelViewer.desktop" "$stage/usr/share/applications/"
install -m644 "$source_dir/com.rigelio.WoBModelViewer.xml" "$stage/usr/share/mime/packages/"
size=$(du -sk "$stage" | cut -f1)
cat > "$stage/DEBIAN/control" <<EOF
Package: $pkg
Version: $version
Section: graphics
Priority: optional
Architecture: amd64
Installed-Size: $size
Maintainer: RIGELIO Team <admin@rigelio.com>
Depends: libc6, libstdc++6, libvulkan1, libx11-6, libxext6, libxrandr2, libxcursor1, libxi6, shared-mime-info, desktop-file-utils
Homepage: https://github.com/RIGELIO/wob-model-viewer
Description: Offline Wars of Bohemia model viewer
 Godot desktop viewer with production material mappings, image-based
 lighting, animation playback, wireframe and 4K PNG export.
EOF
archive="$build/${pkg}_${version}_amd64.deb"
pending=$(mktemp "$archive.XXXXXXXX")
dpkg-deb --build --root-owner-group -Zxz -z3 "$stage" "$pending"
mv -f -- "$pending" "$archive"
