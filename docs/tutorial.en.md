# WoB Model Viewer step by step

[Český tutoriál](tutorial.cs.md) · [Download the viewer](https://github.com/RIGELIO/wob-model-viewer/releases/latest) · [Feature overview](../README.md)

1. [Run the viewer](#run-the-viewer)
2. [Navigate the viewport](#navigate-the-viewport)
3. [Inspect object information](#inspect-object-information)
4. [Check geometry and materials](#check-geometry-and-materials)
5. [Set up lighting and save a view](#set-up-lighting-and-save-a-view)
6. [Play and review animation](#play-and-review-animation)
7. [Use the in-app terminal](#use-the-in-app-terminal)
8. [Automate from a system terminal](#automate-from-a-system-terminal)
9. [Export for 3D printing](#export-for-3d-printing)

## Run the viewer

1. On Windows, extract the ZIP marked `windows-portable` and run **WoB Model Viewer.exe**. To install the viewer, run **Windows Setup**.
2. On Linux, extract the ZIP marked `linux-portable` and run `./wob-model-viewer`. If your extractor drops executable permissions, run `chmod +x wob-model-viewer wob-gif` first. On Debian or Ubuntu you can also install the DEB package.
3. Drop a model into the window or press **Ctrl+O**. The viewer accepts GLB, glTF, FBX, OBJ, STL, 3MF, `.wobview` sessions and Wars of Bohemia vehicle manifests. Keep external `.bin` files and textures referenced by glTF at their exported relative paths.
4. Switch the interface language from **Window**. **Help → Step-by-step Guide** opens the interactive tutorial. **F1** shows input controls and **Ctrl+L** opens the log.

If a surface appears white, check **Materials & diagnostics**. The viewer searches for textures beside the model and up to two levels above it. Use **Load textures…** to choose a folder manually. To use local game materials, keep the `_materialy-z-hry` collection together with its index and `assets` directory.

## Navigate the viewport

- Drag with the left mouse button to orbit. Drag with the right or middle button to pan. Scroll to zoom.
- Press **F** to frame the model. Click a face on the view cube to align the camera. The viewport toolbar lets you switch between perspective and orthographic projection. **F11** toggles full screen.
- Expand the object and the mesh group in the Scene tree. The checkbox on each layer controls visibility. The tree also lists material slots, the skeleton and animation clips when present.
- Use **Window** to show, hide or auto-hide panels. Reveal an auto-hidden panel from its window edge.

## Inspect object information

Click **ⓘ** beside Lighting. The selected row in the Scene tree controls the report.

| Select | What you see |
| --- | --- |
| Model root | File name, path, format, exact size and modification time in UTC. Import bounds, mesh, surface, vertex and triangle counts, vertex attributes, LOD, skeleton and clip counts and diagnostics. For glTF, this can include the exporter, extensions and custom metadata. |
| Individual mesh | Node path, visibility setting, local dimensions, transform, skin bindings, morph targets and geometry by surface. |
| Material slot | Primitive type, vertices, indices, triangles and attributes for that surface, active material, shader when present, PBR values and available texture sizes. |
| Skeleton or clip | Bone names and counts, or clip duration, track paths and key counts. |

Use **Copy details** to put the report on the clipboard. **Refresh details** reads the current selection again, for example after playing an animation that moves the node. Vertex totals count imported vertices per surface. UV seams and material boundaries can split vertices. Whole-model dimensions use import-time bounds.

### Export JSON and CSV

1. Open **ⓘ** and select the model root to export the whole object, or select a mesh for a single layer.
2. Click **Export JSON** or **Export CSV** and choose an output file. Selected materials, skeletons and animation clips can be exported in the same way.
3. JSON contains a schema version, a `scope`, a `source_path` and a `details` object. Counts are numbers and dimensions are arrays of X, Y and Z in meters. Both interface languages use the same keys. Diagnostic messages follow the interface language.
4. CSV is UTF-8 and uses two columns named `field,value`. For example, `/details/geometry/triangle_count` is the triangle count. Use a comma as the separator when importing into a spreadsheet. Text that resembles a formula is prefixed with an apostrophe to keep it as text. Use JSON to retrieve the original value.

## Check geometry and materials

1. Press **W** for triangle wireframe, **Q** for inferred quads or **P** for points. Quad inference pairs neighboring triangles to estimate the original topology.
2. Select **Vertex colors** and a source layer such as `COLOR_0`. Choose R, G, B or A to inspect an individual mask. Use the two UV checker views to inspect either of the first two UV sets.
3. In **Material**, select a slot. Editable materials support changes to base color, roughness, metallic and the normal map in the preview. A session can save those changes. The source file retains its original materials and vertex colors.
4. To compare LODs, keep similarly named exports such as `character_lod0.glb` and `character_lod1.glb` in the same folder. **Model & LOD** shows counts and sizes. **Page Up** and **Page Down** switch LOD while retaining the camera.

Changing a textured material's base color first enables **Solid color**, so the new color is visible over dark albedo. Turn it off to use the original albedo and vertex colors with the tint. The separate **Lighting** tab contains lights, HDRI and sky controls.

## Set up lighting and save a view

1. Under **Lighting**, choose a built-in preset or load a 2:1 HDR or EXR panorama. Use separate switches for HDRI, direct light and reflections.
2. Choose **Day · Sun** or **Night · Moon** to show the corresponding source. In **Day and night cycle**, set the time manually or play the full cycle. Toggle the floor, grid and background independently.
3. **File → Save As** writes a `.wobview` file with a model reference, camera, lighting, LOD and animation settings, including the current cut. After re-exporting a model, press **Ctrl+R** to reload it and keep the view.
4. Press **Ctrl+E** to save a 3840 × 2160 PNG. Disable **Show background** for a transparent background.

## Play and review animation

1. Select a clip, press Space to play and use the step buttons to inspect poses. Set speed from 0× to 2×. For close inspection, try 0.1× or 0.01×. **In place** suppresses horizontal travel when root motion is recognized.
2. Enable **Cut** and mark the start and end on the ruler below the slider. Dragging across the range also works. **Loop** repeats the selected range. Turn it off to stop at the cut's end.
3. **Model → Motion Editor** lets you select joints, preview changes and attach marks to bones. **Analyze Motion** checks foot contact, rotation spikes and loop continuity. Select a finding to seek to its time.
4. To save a GIF, set the interval, FPS and dimensions through **Model → Animation Range**, then choose **Export animation GIF**. The export uses its own interval. Keep the included `wob-gif` or `wob-gif.exe` beside the portable viewer.

## Use the in-app terminal

Open **Window → Viewer Terminal** or press **Ctrl+T**. The same English commands work in either language. Enter runs a command and Up and Down navigate history. Quote paths and clip names that contain spaces. Use a decimal point in numeric arguments.

```text
help
open "D:\Models\character lod0.glb"
info model
clips
clip "Walk Cycle"
speed 0.25
cut 0.4 1.2
play
```

Replace the sample path and clip name with your own. A typical Linux path is `/home/user/models/character.glb`. Use `info` for the Scene selection and `info model` for the whole object. Use `cut off` to return to the full clip, `pause` to pause or `seek 0.6` to seek to a point. Try `grid on`, `view wireframe` and `screenshot "D:\Models\review.png"`. Run `help` for the full list.

The terminal controls the current Viewer window and interprets input as Viewer commands.

Use the following terminal commands to export. `model` exports the whole object regardless of the Scene tree selection. `selection` exports the current selection and is the default. Use a new output filename.

```text
export info "D:\Models\object.json" model
export info "D:\Models\layer.csv" selection
```

## Automate from a system terminal

### Export information in bulk without a window

In Windows, open PowerShell in the viewer folder and use the bundled `WoB Model Viewer.console.exe`. Installed copies have it beside the main EXE. You can pass either a folder or a single model.

```powershell
$viewer = (Resolve-Path ".\WoB Model Viewer.console.exe").Path
& $viewer --headless -- "--export-info=D:\Models" "--output-dir=D:\Exports\WoB" --format=json
$LASTEXITCODE
```

Use `--format=csv` for CSV. For a single file, pass an argument like `"--export-info=D:\Models\cabin.glb"`. The viewer processes GLB, glTF, FBX, OBJ, STL and 3MF files in the supplied folder. It creates the output directory when needed and writes one report per model, for example `cabin.glb.json`. It keeps the model extension in the name so a GLB and an FBX with the same stem have distinct outputs. The scan covers the selected folder's immediate children.

Existing reports are kept unless you add `--overwrite`. The batch continues after a model fails. The last line begins with `WOB_VIEWER_INFO_RESULT` and contains a JSON summary with one result per file. Exit code `0` means all reports were written, `1` means an incomplete export, and `2` means invalid input or an unavailable output directory.

Use `--recursive` and `--summary-csv` for one combined inventory of a folder and its subfolders.

```powershell
& $viewer --headless -- "--export-info=D:\Models" --recursive "--summary-csv=D:\Exports\inventory.csv"
```

The inventory has one row per model and the columns `path`, `triangles` and `status`. When loading fails, the triangle count is blank and the status is `load_failed`. Add `--output-dir` for individual reports alongside the inventory. Their output folders mirror the input tree. Recursive scans skip directory links.

```sh
./wob-model-viewer --headless -- "--export-info=/home/user/models" "--output-dir=/home/user/export" --format=csv
```

### Open models and capture images

Use `--` to separate viewer arguments. Screenshot capture requires a graphical display. The instance exits with a status code after saving the file.

```powershell
& ".\WoB Model Viewer.exe" -- "D:\Models\character.glb" "--language=en"
& ".\WoB Model Viewer.exe" -- "D:\Models\character.glb" "--screenshot=D:\Models\review.png"
```

```sh
./wob-model-viewer -- "/home/user/models/character.glb" --language=en
./wob-model-viewer -- "/home/user/models/character.glb" "--screenshot=/home/user/review.png"
```

Save a batch analysis job as `analyze.json` beside the model. Relative paths resolve from that JSON's folder. Set `start` and `finish` in seconds within the chosen clip.

```json
{
  "version": 1,
  "type": "analyze",
  "model": "character.glb",
  "clip": "Walk Cycle",
  "start": 0.4,
  "finish": 1.2,
  "fps": 30,
  "result": "result.json"
}
```

```sh
./wob-model-viewer --headless -- --viewer-job=analyze.json
```

On Windows use `& ".\WoB Model Viewer.exe" --headless -- --viewer-job=analyze.json`. Read `result.json` from your script on either platform. For GIF export, use `"type": "gif"` with `"output": "cut.gif", "width": 640, "height": 360`. Run GIF jobs with a graphical display and omit `--headless`. Analysis supports 5–60 FPS and up to 900 samples. GIF export supports 5–30 FPS, up to 240 frames and dimensions up to 1280 × 720.

## Export for 3D printing

1. Open the model. To print a pose, choose an animation clip and scrub to the desired time. Opening the export stops playback at that frame.
2. Choose **File → Export for 3D printing…** and select **Current animation frame** or **Rest pose**. The export uses visible parts and respects isolation.
3. Set the scale and choose **STL**, **3MF** or **OBJ**. With scale at 100%, one meter in the viewer becomes 1000 millimeters in the file. Z points up and the lowest point is placed at Z = 0.
4. Open the file in your slicer to check dimensions, orientation and open edges. The file contains the mesh for one pose. Materials, animation tracks and shader-generated surfaces are outside the exported geometry.

The viewer can also open binary and ASCII STL, Wavefront OBJ and 3MF. For 3MF it reads the mesh geometry and build transforms. Keep textures referenced by a basic MTL file at their original relative paths. STL uses millimeters. Ordinary OBJ uses the source axes and one unit per meter. The viewer recognizes its own print OBJ header and converts those files back from millimeters.
