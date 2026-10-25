#!/usr/bin/env python3
"""Explicit acquisition/bootstrap; normal packaging never downloads."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
STAGE = ROOT / ".build/packaging"
MANIFEST = json.loads((ROOT / "Scripts/Packaging/dependencies.json").read_text())


def verify_cache():
    for entry in MANIFEST.values():
        path = STAGE / "downloads" / entry["file"]
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise SystemExit(f"Missing or mismatched dependency: {entry['file']}. Run prepare.py --acquire explicitly.")


def extract(archive, destination):
    if destination.exists() and any(destination.iterdir()):
        return  # Project-local incremental build. Remove only this staging tree for a fresh rebuild.
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as source:
        members = source.getmembers()
        prefix = members[0].name.split("/")[0] + "/"
        for member in members:
            if not member.name.startswith(prefix):
                continue
            member.name = member.name[len(prefix):]
            if member.name:
                source.extract(member, destination, filter="data")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--acquire", action="store_true", help="allow pinned HTTPS downloads")
    args = parser.parse_args()
    if sys.version_info[:2] != (3, 14):
        raise SystemExit("Build bootstrap requires Python 3.14 for the pinned arm64 build-tool wheels. Packaged app needs no installed Python.")
    for entry in MANIFEST.values():
        target = STAGE / "downloads" / entry["file"]
        if not target.exists() and args.acquire:
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_name(target.name + ".partial")
            subprocess.run(["/usr/bin/curl", "--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--tlsv1.2", "--max-time", "600", entry["url"], "-o", str(temporary)], check=True)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != entry["sha256"]:
                temporary.unlink()
                raise SystemExit("Downloaded checksum mismatch: " + entry["file"])
            temporary.replace(target)
    verify_cache()
    tools = STAGE / "tools"
    if not (tools / "bin/python").exists():
        subprocess.run([sys.executable, "-m", "venv", str(tools)], check=True)
    requirements = STAGE / "build-tool-hashes.txt"
    requirements.write_text("".join(f"{STAGE / 'downloads' / e['file']} --hash=sha256:{e['sha256']}\n" for name, e in MANIFEST.items() if name.startswith("wheel:")))
    subprocess.run([str(tools / "bin/python"), "-m", "pip", "install", "--no-cache-dir", "--no-index", "--no-deps", "--disable-pip-version-check", "--require-hashes", "-r", str(requirements)], check=True)
    for name, entry in MANIFEST.items():
        if name.startswith("wheel:") or name == "yt-dlp" or name == "mpv-coreaudio-fix":
            continue
        destination = STAGE / "src" / name
        if name in ("Vulkan-Headers", "fast_float"):
            destination = STAGE / "src/libplacebo/3rdparty" / name
        extract(STAGE / "downloads" / entry["file"], destination)
    patch = MANIFEST["mpv-coreaudio-fix"]
    target = STAGE / "src" / patch["target"]
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest == patch["before_sha256"]:
        subprocess.run(["/usr/bin/patch", "-p1", "-i", str(STAGE / "downloads" / patch["file"])], cwd=STAGE / "src/mpv", check=True)
    if hashlib.sha256(target.read_bytes()).hexdigest() != patch["after_sha256"]:
        raise SystemExit("Unexpected mpv source patch state; move aside staging and rebuild fresh")
    print("Pinned cache verified and isolated build environment ready.")


if __name__ == "__main__":
    main()
