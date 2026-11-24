# Build WoB Model Viewer from source

Download the [production resources pack](https://github.com/RIGELIO/wob-model-viewer/releases/download/v1.0.1/WoB-Model-Viewer-production-resources-v1.0.1.zip) and extract it so the `production` directory sits alongside `app/project.godot`. The resulting path to the resource manifest is `app/production/manifest.json`. The pack contains the production shaders, textures, vehicle presets and Lilienstein HDRI. Its manifest records the source revision and SHA-256 hashes.

## Open the project

Use the standard Godot 4.7.2 x86-64 editor and import `app/project.godot`. Press **F6** with `viewer.tscn` open, or **F5** to run the project. A graphics driver supporting Forward+ is required. [Godot 4.7.2 downloads](https://godotengine.org/download/archive/4.7.2-stable/)

## Export both portable builds

Use Python 3 and Godot 4.7.2 with the standard export templates. Extract the export template archive and place these files in one directory. [Godot 4.7.2 standard export templates](https://godotengine.org/download/archive/4.7.2-stable/)

- `windows_release_x86_64.exe`
- `linux_release.x86_64`
- `LICENSE.txt` and `COPYRIGHT.txt` from the Godot 4.7.2 source release. [Godot 4.7.2 source](https://github.com/godotengine/godot/tree/4.7.2-stable)

Run the following from the repository root. Substitute the path to the local Godot executable and the directory containing the templates. On Windows use the Godot console executable. The output directory must be new.

```text
python app/build.py --resources app/production --godot "path/to/godot" --templates "path/to/templates" --out build/viewer --logs build/logs
```

You can also pass `--resources` the path to a separately extracted `production` directory. The script imports the assets, exports the Windows and Linux executables and creates a portable ZIP for each platform. The executables embed their runtime resources. Use `--stage-only` if you only need the prepared Godot project.

## Build the installers

On Windows, run `makensis.exe` from NSIS. Use absolute paths for the payload, icon and output because the compiler changes its working directory to the script location. [NSIS compiler reference](https://nsis.sourceforge.io/Docs/Chapter3.html)

```powershell
$root = (Get-Location).Path
makensis.exe "/DPAYLOAD=$root\build\viewer\Windows" "/DAPP_ICON=$root\app\art\icon.ico" "/DOUTPUT=$root\build\viewer\WoB-Model-Viewer-Windows-Setup-x86_64.exe" "$root\app\windows\setup.nsi"
```

On Debian or Ubuntu, use `dpkg-deb` from the `dpkg` package. The script stages files on a temporary POSIX filesystem and writes the finished package to the build directory.

```sh
sh app/linux/package-deb.sh build/viewer
```

The package is written to the export directory. Keep the viewer and resource license notices with redistributed builds.
