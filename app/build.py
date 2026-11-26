"""Stage and export the viewer from local production resources with Godot 4.7.2."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile


HERE = Path(__file__).resolve().parent
DEFAULT_REV = "66a82f431a91acdde7492c3f2eddd9c9fb2390c5"
VERSION = "1.5.0"
SHADERS = ("kuze", "odev", "oko", "vlasy_karty", "vlasy_mikro_4k", "vousy_strniste_shell")
VEHICLES = ("bojovy", "ranenych", "remeslny", "velitelsky", "zasobovaci")
ATLASES = {
    "vlasy/vlasy_mikro_4k": ("atlas", "normal"),
    "vousy/vousy_mikro_4k": ("atlas", "normal"),
    "vousy/vousy_mikro_v2_4k": ("atlas", "normal"),
    "vousy/strniste_shell_2k": ("atlas", "normal"),
    "vousy/strniste_shell_4k": ("atlas", "normal"),
}
TEMPLATES = {
    "Windows": ("Windows Desktop", "windows_release_x86_64.exe", "WoB Model Viewer.exe"),
    "Linux": ("Linux", "linux_release.x86_64", "wob-model-viewer"),
}


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def production_asset(repo, commit, checkout, origin):
    data = git(repo, "show", f"{commit}:{origin}")
    if data.startswith(b"version https://git-lfs.github.com/spec/"):
        expected = data.split(b"oid sha256:", 1)[1].splitlines()[0].decode()
        data = (checkout / origin).read_bytes()
        if sha256(data) != expected:
            raise ValueError(f"Missing or mismatched Git LFS bytes for {origin}")
    return data


def add_vehicle_resources(repo, commit, checkout, production):
    """Copy the shared wagon shader and presets, leaving each export to provide its own atlas."""
    manifest_path = production / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    shared = "assets/vozy/spolecne/"
    target = production / "vehicles"
    target.mkdir()
    arrays = [f"vuz_dlazdice_{channel}.png" for channel in ("albedo", "normal", "orm")]

    def write(name, origin, data):
        (target / name).write_bytes(data)
        manifest["resources"][f"vehicles/{name}"] = {"source": origin, "sha256": sha256(data)}

    for name in ("vuz.gdshader", "vuz_sum.tres", "vuz_dlazdice.json", *arrays):
        origin = shared + name
        write(name, origin, production_asset(repo, commit, checkout, origin))
    for name in arrays:
        origin = shared + name + ".import"
        metadata = git(repo, "show", f"{commit}:{origin}").decode().replace(
            "res://" + shared, "res://production/vehicles/",
        )
        (target / (name + ".import")).write_text(metadata, encoding="utf-8")
    for style in VEHICLES:
        name = f"vuz_{style}_material.tres"
        origin = f"assets/vozy/{style}/{name}"
        text = git(repo, "show", f"{commit}:{origin}").decode().replace(
            "res://" + shared, "res://production/vehicles/",
        )
        drop = ('id="2_alb"]', 'id="3_nrm"]', 'id="4_orm"]')
        lines = [line for line in text.splitlines() if not line.endswith(drop)
                 and not line.startswith(("shader_parameter/albedo_tex", "shader_parameter/normal_tex",
                                           "shader_parameter/orm_tex"))]
        count = sum(line.startswith("[ext_resource ") for line in lines)
        lines[0] = re.sub(r"load_steps=\d+", f"load_steps={count + 1}", lines[0])
        write(name, origin + " (viewer preset without atlas references)", ("\n".join(lines) + "\n").encode())
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def run(command, log):
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run([str(item) for item in command], stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"Godot returned {result.returncode}. See {log}")
    contents = log.read_text(encoding="utf-8", errors="replace")
    if any(line.lstrip().startswith(("ERROR:", "SCRIPT ERROR:", "SHADER ERROR:")) for line in contents.splitlines()):
        raise RuntimeError(f"Godot reported an error. See {log}")


def prepare(args, stage):
    for name in ("project.godot", "viewer.tscn", "viewer.gd", "stage.gd", "materials.gd",
                 "glb_data.gd", "view_file.gd", "orientation_gizmo.gd", "lod_catalog.gd", "topology_overlay.gd",
                 "vehicle_manifest.gd", "game_materials.gd", "attribute_preview.gdshader", "celestial_sky.gdshader",
                 "wireframe_mesh.gd", "wireframe_preview.gdshader", "texture_search.gd", "model_gizmo.gd",
                 "loading_orbit.gdshader", "tutorial.gd", "scene_outline.gd", "material_inspector.gd", "ui_glyphs.gd"):
        shutil.copy2(HERE / name, stage / name)
    shutil.copytree(HERE / "tools", stage / "tools", ignore=shutil.ignore_patterns("*.go", "*.uid", "*.import"))
    shutil.copytree(HERE / "locale", stage / "locale")
    shutil.copytree(HERE / "art", stage / "art", ignore=shutil.ignore_patterns("ui-concept.*"))
    if args.resources:
        if not (args.resources / "vehicles" / "vuz.gdshader").is_file():
            raise ValueError("Use the production resource archive for WoB Model Viewer 1.0.1 or later.")
        shutil.copytree(args.resources, stage / "production")
        return
    commit = git(args.repo, "rev-parse", args.rev).decode().strip()
    hashes = {}

    def copy_production(destination, origin, data):
        target = stage / "production" / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        hashes[destination] = {"source": origin, "sha256": sha256(data)}

    for shader in SHADERS:
        origin = f"shaders/postavy/{shader}.gdshader"
        copy_production(f"shaders/{shader}.gdshader", origin, git(args.repo, "show", f"{commit}:{origin}"))
    for name in ("kuze_pory_n.png", "vlasy_atlas.png"):
        origin = f"assets/postavy/zizka/textury/{name}"
        data = production_asset(args.repo, commit, args.assets_checkout, origin)
        copy_production(f"textures/{name}", origin, data)
    for atlas, suffixes in ATLASES.items():
        for suffix in suffixes:
            relative = f"{atlas}_{suffix}.png"
            copy_production(
                f"textures/{Path(relative).name}", f"Textury/postavy/{relative}",
                (args.atlases / relative).read_bytes(),
            )
    copy_production(
        "lighting/lilienstein_2k.hdr", "Poly Haven Lilienstein (CC0)", args.hdri.read_bytes(),
    )
    manifest = {"godot": "4.7.2.stable.official.ed1daf0bf", "shader_source_commit": commit, "resources": hashes}
    (stage / "production" / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    add_vehicle_resources(args.repo, commit, args.assets_checkout, stage / "production")


def preset(name, platform, template, *, product_name="WoB Model Viewer", version=VERSION):
    options = f"""
application/modify_resources=true
application/icon="res://art/icon.png"
application/company_name="RIGELIO Studio"
application/product_name={json.dumps(product_name)}
application/file_description={json.dumps(product_name)}
application/file_version="{version}.0"
application/product_version="{version}.0"
application/legal_copyright="Copyright 2026 RIGELIO Studio"
""" if name == "Windows" else ""
    return f"""
[preset.0]
name="{name}"
platform="{platform}"
runnable=true
dedicated_server=false
export_filter="all_resources"
include_filter="production/manifest.json,production/vehicles/vuz_dlazdice.json,art/icon.ico,art/startup.png"
exclude_filter=""

[preset.0.options]
custom_template/debug=""
custom_template/release={json.dumps(template.as_posix())}
debug/export_console_wrapper=0
binary_format/embed_pck=true
binary_format/architecture="x86_64"
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
{options}
"""


def import_project(godot, stage, logs):
    version = subprocess.check_output([str(godot), "--version"]).decode().strip()
    if version != "4.7.2.stable.official.ed1daf0bf":
        raise ValueError(f"Expected standard Godot 4.7.2, got {version}")
    logs.mkdir(parents=True, exist_ok=True)
    run([godot, "--headless", "--path", stage, "--editor", "--import"], logs / "import.log")
    import_settings_changed = False
    for sidecar in (stage / "production" / "textures").glob("*.png.import"):
        metadata = sidecar.read_text(encoding="utf-8")
        # Atlas RGB and alpha are data channels. Keep source texels and generate mipmaps.
        updated = metadata.replace("mipmaps/generate=false", "mipmaps/generate=true")
        updated = updated.replace("process/fix_alpha_border=true", "process/fix_alpha_border=false")
        updated = updated.replace("detect_3d/compress_to=1", "detect_3d/compress_to=0")
        if updated != metadata:
            sidecar.write_text(updated, encoding="utf-8")
            import_settings_changed = True
    if import_settings_changed:
        run([godot, "--headless", "--path", stage, "--editor", "--import"], logs / "import-mipmaps.log")


def export(args, stage):
    import_project(args.godot, stage, args.logs)
    go_root = Path(subprocess.check_output([args.go, "env", "GOROOT"], text=True).strip())
    for name, (platform, template_name, executable) in TEMPLATES.items():
        target = args.out / name
        target.mkdir()
        template = args.templates / template_name
        if not template.is_file():
            raise FileNotFoundError(template)
        (stage / "export_presets.cfg").write_text(preset(name, platform, template), encoding="utf-8")
        binary = target / executable
        run([args.godot, "--headless", "--path", stage, "--export-release", name, binary],
            args.logs / f"export-{name.lower()}.log")
        binary.chmod(0o755)
        gif_encoder = target / ("wob-gif.exe" if name == "Windows" else "wob-gif")
        env = dict(os.environ, GOOS=name.lower(), GOARCH="amd64", CGO_ENABLED="0")
        subprocess.run([args.go, "build", "-trimpath", "-ldflags=-s -w", "-o", str(gif_encoder),
                        str(HERE / "tools" / "gif.go")], env=env, check=True)
        gif_encoder.chmod(0o755)
        shutil.copy2(go_root / "LICENSE", target / "Go-LICENSE.txt")
        for guide in (HERE / "docs").glob("README.*.md"):
            shutil.copy2(guide, target)
        shutil.copy2(HERE / "art" / "icon.png", target)
        shutil.copy2(HERE / "art" / "CormorantGaramond-OFL.txt", target)
        for notice in ("LICENSE", "RESOURCE-LICENSES.md"):
            shutil.copy2(HERE / notice, target)
        shutil.copy2(stage / "production" / "manifest.json", target / "PRODUCTION-RESOURCES.json")
        for file in ("LICENSE.txt", "COPYRIGHT.txt"):
            shutil.copy2(args.templates / file, target / f"Godot-{file}")
        if name == "Windows":
            for file in (HERE / "windows").glob("Register-FileTypes.*"):
                shutil.copy2(file, target)
        else:
            for file in ("register-file-types.sh", "com.rigelio.WoBModelViewer.xml", "com.rigelio.WoBModelViewer.desktop"):
                shutil.copy2(HERE / "linux" / file, target)
        archive = args.out / f"WoB-Model-Viewer-{name.lower()}-portable-x86_64.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=5) as package:
            for file in sorted(target.iterdir()):
                item = zipfile.ZipInfo.from_file(file, f"WoB Model Viewer/{file.name}")
                if name == "Linux" and (file in (binary, gif_encoder) or file.name == "register-file-types.sh"):
                    item.create_system = 3
                    item.external_attr = 0o100755 << 16
                package.writestr(item, file.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=lambda value: Path(value).resolve())
    for path in ("repo", "assets-checkout", "atlases", "hdri", "resources"):
        parser.add_argument("--" + path, type=lambda value: Path(value).resolve())
    parser.add_argument("--rev", default=DEFAULT_REV)
    for path in ("godot", "templates", "logs"):
        parser.add_argument("--" + path, type=lambda value: Path(value).resolve())
    parser.add_argument("--stage-only", action="store_true")
    parser.add_argument("--go", default="go", help="Go compiler for the offline GIF encoder")
    args = parser.parse_args()
    if not args.resources and any(getattr(args, key) is None for key in ("repo", "assets_checkout", "atlases", "hdri")):
        parser.error("Pass --resources or all of --repo, --assets-checkout, --atlases and --hdri")
    if not args.stage_only and any(getattr(args, key) is None for key in ("godot", "templates", "logs")):
        parser.error("Export requires --godot, --templates and --logs")
    stage = args.out / "source"
    stage.mkdir(parents=True)
    # Respect a workspace's explicit temporary output location for exporter subprocesses.
    if os.name == "nt":
        os.environ["TEMP"] = str(args.out)
        os.environ["TMP"] = str(args.out)
    prepare(args, stage)
    if not args.stage_only:
        export(args, stage)


if __name__ == "__main__":
    main()
