# WoB Model Viewer

WoB Model Viewer is an offline desktop viewer for GLB, glTF, FBX, OBJ and STL models. It helps you inspect geometry, materials and animations, with support for original Wars of Bohemia character shaders and shared atlases.

[Step-by-step tutorial on GitHub](https://github.com/RIGELIO/wob-model-viewer/blob/main/docs/tutorial.en.md)

## Download and run

Get the [latest release](https://github.com/RIGELIO/wob-model-viewer/releases/latest) for x86-64. On Windows, run the setup EXE to install for your user. On Debian and Ubuntu, open the `.deb` in your package manager or run `sudo apt install ./wob-model-viewer_VERSION_amd64.deb`. Both platforms also have a portable ZIP. Extract it and run **WoB Model Viewer.exe** or **wob-model-viewer**. Use `chmod +x wob-model-viewer` if your Linux extractor removed the executable flag. The runtime is bundled. Use an up-to-date graphics driver.

Windows Setup and the Linux DEB register **.glb**, **.gltf**, **.fbx**, **.obj**, **.stl** and **.wobview** automatically. For double-click opening, choose **WoB Model Viewer** in the system’s default app settings or **Open With**. Windows Setup sets the initial handler for unregistered `.wobview` files and offers a link to **Default apps** on its final page. For the portable editions, run **Register-FileTypes.cmd** on Windows or `sh register-file-types.sh` on Linux. The Linux helper uses `shared-mime-info` and `desktop-file-utils`. Repeat portable registration when you move the executable.

The Windows installer and executable are unsigned. If SmartScreen prompts on first use, verify the download against `SHA256SUMS.txt` on the release page. A signed release can display a verified publisher. SmartScreen also considers the reputation of the downloaded file. [Microsoft documentation](https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation)

Setup displays the installation terms and MIT license. Updates and uninstall prompt you to close the viewer. Uninstall removes the program, shortcuts, registration and known settings and cache files. Your saved models, views and screenshots stay in their existing folders.

To update on Windows, download and run the newer setup. It detects the registered installation, shows its version and updates the existing folder with your settings intact. Running the same version again reinstalls it in place. On Linux, install the newer DEB through the package manager to upgrade the installed package.

## Learn the viewer

Open **Help → Step-by-step Guide** for six interactive lessons. The **View**, **Animation** and **Model** menus open the relevant controls. The inspector on the right contains playback settings, materials, lighting, display and active editing tools. Use the Scene tree on the left to show or hide meshes and select materials, skeletons and clips. The bottom timeline has previous frame, play, next frame, speed and loop controls.

## Animation tools

Open the **ⓘ** tab beside Lighting for the Scene tree selection. The root shows file details and totals. Individual layers show their own geometry and attributes. Press **Ctrl+T** to open the Viewer Terminal. Try `help`, `info model` or `cut 0.4 1.2` followed by `play`.

The **ⓘ** tab has **Export JSON** and **Export CSV** buttons for the current selection. In the terminal, use `export info "object.json" model` for the whole model or `export info "layer.csv" selection` for the Scene tree selection.

To export a whole folder from PowerShell without a window, run `& ".\WoB Model Viewer.console.exe" --headless -- "--export-info=D:\Models" "--output-dir=D:\Exports\WoB" --format=json`. On Linux, use `./wob-model-viewer` with the same options and Linux paths.

Add `--recursive` to include subfolders. Use `"--summary-csv=D:\Exports\inventory.csv"` for a combined CSV of paths and triangle counts. Supply `--output-dir` when you also want individual reports.

**File → Export for 3D printing…** saves visible geometry from the rest pose or current animation frame to STL, 3MF or OBJ. Files use millimeters and Z up. The viewer also opens OBJ and binary or ASCII STL.

Viewer 1.5 is free and runs offline without an account or activation. Use **Model → Motion Editor** on an animated skeleton to select joints, step frames, preview changes and attach drawing marks. **Analyze Motion** checks the chosen clip for foot contact, rotation spikes and loop continuity. Select a finding to move to its position on the timeline. **Export report and edits** saves the results to JSON.

Use **Model → Draft a new skeleton** on an unrigged model. Start with a human or quadruped template, or choose **Add joint** and click in the viewport. Select and drag your joints to adjust them. Save a `.wobrig` draft to continue later and use a separate GLB for export.

Use **Model → Animation Range** to set the interval, frame rate and output size before choosing **Export animation GIF**. Keep the included GIF encoder beside the portable executable.

## Vehicle manifests

Open a `vuz_*_manifest.json` or one of the adjacent GLBs. The viewer applies the original wagon shader and resolves the manifest's albedo, normal and ORM maps. Tiled models retain their `UV2` and `COLOR_0` semantics. Use **Model & LOD** in the right-hand inspector to select the vehicle state and level of detail. The `*_atlas.json` file describes the UV atlas.

## Local WoB materials

Keep the local `_materialy-z-hry` folder, including `index.json` and `assets/`, at the root of your finished model collection. Open a building, prop, bridge or road GLB as usual. The viewer uses the model's original import and prefab material assignments and reads the referenced materials and maps. The same folder layout works on Windows and Linux. Check **Materials & diagnostics** for incomplete material data.

## Inspect a model

1. Drop a `.glb`, `.gltf` or `.fbx` anywhere in the window or press **Ctrl+O**. The viewer shows the filename and a spinner during import. Keep any separate `.bin` and textures referenced by a `.gltf` at their relative paths within the model folder. Switch languages from **Window**. Press **F1** for help and **F11** for full screen.
2. Drag with the **left mouse button** to orbit. Drag with the right or middle button to pan and scroll to zoom. **F** frames the model. Click a face on the view cube to align the camera, or drag the cube to orbit. Enable **Auto-rotate** to orbit continuously. The **Screen-space pan** toggle switches between view-aligned and ground-plane movement.
3. Under **Lighting**, choose a built-in Poly Haven panorama or load a 2:1 HDR or EXR file. **HDRI** shows the panorama as photographed. **Day · Sun** and **Night · Moon** add a visible light source aligned with the direct light. Adjust its azimuth and elevation to move it, or use **Aim at source** to bring it into view. Ambient HDRI, direct light and HDRI reflections have separate controls.
4. **View** provides background colors and the HDRI panorama. Turn off **Show background** for transparent PNG exports. Toggle the grid, shadow-catching floor, skeleton overlay and orthographic projection independently. Inspect shaded, wireframe, unlit, normal-buffer, overdraw or **Points** views. **Point size** controls the size of vertex dots in **Points** mode. **Geometry** shows mesh statistics, and the timeline plays and scrubs embedded clips.
5. Use **File → Save** or **Save As** to save a `.wobview` file with the model reference, camera, lighting, display settings and animation position. Reopen it through **File → Open**. Use **Ctrl+E** or **Save 4K PNG** to render the current 3D view at 3840 × 2160.

Skin materials display without subsurface scattering when you make the background transparent.

The viewer starts in a maximized window. Animations repeat after you press **Play**. Clear **Loop** to play the clip once.

Switching clips during playback starts the new clip immediately. If playback is paused, the newly selected clip stays paused.

Choose **0× to 2× in 0.01× steps** speed next to the timeline. **In place** suppresses horizontal travel in clips with recognized root motion while preserving height and limb movement. Use it to inspect walk and run cycles.

Turn on **Cut** in the timeline. Click the beginning and end on the ruler below the slider or drag across the range. You can also use **Animation → Mark Time at Playhead** twice. Selecting a cut enables looping, and **Play** repeats the marked range. Turn off **Cut** to return to the full clip. Saved .wobview sessions remember the selection.

In **Lighting**, select **Day and night cycle**. Scrub the time of day or enable **Play cycle**. **Cycle duration** controls how many seconds a complete 24-hour day takes. The time and settings are saved in `.wobview`.

The viewer also shows progress feedback when switching panoramas or skies, preparing points, quads or attribute previews, and exporting a 4K image.

## Inspect parts and attributes

- **Ctrl+R** reloads the current model file after a new export. It keeps the camera, lights, HDRI, vehicle state and selected LOD. It restores isolation when the part still exists.
- Expand **Parts and materials** and select a mesh or one of its material surfaces. Press **Isolate** or double-click the row. **Show all** restores the full model. Geometry and LOD statistics cover the full model at the selected level.
- In **View**, choose **Vertex colors** and a source layer such as `COLOR_0` or `COLOR_1`. View RGB together or individual R, G, B and A channels in grayscale. **UV0 · checker** and **UV2 · checker** show the first and second UV sets (`TEXCOORD_0` and `TEXCOORD_1` in glTF). Stripes mark surfaces missing the requested attribute.

## Compare LODs

If a model is named like `character_lod0.glb`, the viewer finds matching files in the same folder, including variants such as `character_lod1_helma.glb`. The LOD list shows the triangle and vertex counts from the source GLB scene and the size of each file. Switch levels from the list to compare them while keeping the current camera.

**Wireframe** shows triangle edges. In **View**, the same control position shows **Line width** in wireframe mode or **Point size** in Points mode. The session stores both values independently. **Inferred quads** estimates quad boundaries by pairing adjacent triangles and hiding the inferred diagonals.

Use the color swatch next to **Floor** to change its color. **Floor offset** moves the floor and grid in meters relative to the model's baseline, which helps inspect animated ground contact. The session saves both settings.

In **View**, turn on **Model axes** or press **M**. Drag an arrow to move the model along world X, Y, or Z. Drag a ring to rotate it around that axis. **Reset transform** restores the original position and orientation. The `.wobview` session saves the transform.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| **1** or **F** · **2** · **3** · **4** | Frame · Front · Side · Top |
| **W** · **Q** · **P** | Wireframe · Inferred quads · Points |
| **G** · **K** · **A** · **B** · **O** | Grid · Skeleton · Auto-rotate · Show background · Ortho |
| **M** | Toggle model axes |
| **Page Up** · **Page Down** | Previous LOD · Next LOD |
| **Space** | Play or pause |
| **Ctrl+O** · **Ctrl+S** · **Ctrl+Shift+S** | Open · Save view · Save view as |
| **Ctrl+R** | Reload the current model and keep the view |
| **Ctrl+E** · **Ctrl+Q** · **F1** | Export 4K PNG · Quit · Help |
| **F11** · **Esc** | Enter or leave full screen · Return to window |

## Production materials and diagnostics

The viewer matches model and material names to the Wars of Bohemia shaders for skin, eyes, cloth, hair cards, hair and beard microfibers, and StubbleShell. Source files retain their original vertex color streams. Each production shader uses the stream required by that material, including the different density streams used by legacy and 4K StubbleShell.

Check **Materials & diagnostics** for unmatched shaders, missing attributes or missing textures. The viewer keeps the original GLB material where it can. Some material-free exports, including KeenFace heads and the opaque LOD3 hair cap in the v5 reference set, display with a neutral preview and a warning when there is no matching production material.

Click a yellow warning or the **Log** button in the status bar to open the current session history. You can also use **Help → Log** or **Ctrl+L**. **Copy log** copies the text to the clipboard.

The viewer searches by exact name in the model folder and up to two parent directories, including standard texture subfolders such as `textury_4k`, `textury`, `textures`, and `maps`. When a texture is missing, select **Materials & diagnostics → Load textures…**. The folder picker starts one level above the model. The viewer keeps the camera and saves the chosen folder with the session.

For V5 short haircuts, the viewer reads the hair and beard atlases from `textury_4k` and the original face materials from the source GLB in the same catalog. If you move the model elsewhere, select the original `textury_4k` folder manually.

For custom mappings, create a `your-model.wob.json` beside the model. Keys in `surfaces` combine the glTF node name and zero-based primitive index. Local texture paths are relative to the model directory.

```json
{
  "surfaces": {
    "HeroMesh:0": {
      "shader": "kuze",
      "color": "COLOR_0",
      "textures": {
        "albedo_tex": "skin.png",
        "normal_tex": "skin-normal.png"
      }
    }
  }
}
```

Supported shader IDs are `kuze`, `oko`, `odev`, `vlasy_karty`, `vlasy_mikro_4k` and `vousy_strniste_shell`. The release includes the provenance and SHA-256 of its production resources.

## Command line

```sh
./wob-model-viewer -- "/local/character.glb" "--language=en"
./wob-model-viewer -- "/local/character.glb" "--screenshot=/local/character-4K.png"
```

Windows accepts the same arguments after `"WoB Model Viewer.exe"`. Automated screenshot capture uses the desktop renderer and exits after saving the PNG.

The three built-in panoramas are available offline. Godot notices are bundled with each release. [Lilienstein](https://polyhaven.com/a/lilienstein), [Kloppenheim 06 (Pure Sky)](https://polyhaven.com/a/kloppenheim_06_puresky), [Moonlit Golf](https://polyhaven.com/a/moonlit_golf) by Poly Haven, CC0.

## License

© 2026 RIGELIO Studio. The MIT license permits use, modification and redistribution with the copyright and license notice. See [LICENSE](LICENSE) and [resource licenses](RESOURCE-LICENSES.md). The application displays its version, copyright and license under **Help → About**.
