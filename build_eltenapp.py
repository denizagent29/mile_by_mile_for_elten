#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = [
#     "zstandard",
# ]
# ///
# Builds the MileByMile .eltenapp from elten_app/ and installs it into
# Elten's apps/src folder (Windows %APPDATA%). Pure-Python port of the
# .eltenapp container format used by elten3/tools/build-eltenapp.rb, so the
# repo builds on a machine with no Ruby toolchain.
#
# Usage:
#   python build_eltenapp.py                  # build + install into Elten (Windows)
#   python build_eltenapp.py --no-install     # build only
#   python build_eltenapp.py --output x.eltenapp --no-install
#
# Needs one zstd backend (tried in order): the `zstandard` module
# (pip install zstandard), the `zstd` CLI, or the system libzstd.

import ctypes
import ctypes.util
import json
import os
import re
import shutil
import struct
import subprocess
from pathlib import Path

MAGIC = b"Elten3AppPackage"
SOUND_EXTENSIONS = {
    ".ogg", ".opus", ".wav", ".wave", ".mp3",
    ".flac", ".aac", ".m4a", ".wma", ".spx", ".webm",
}
MANIFEST_BEGIN = re.compile(r"^=begin[ \t]+Elten3AppInfo[ \t]*\r?\n", re.M)
MANIFEST_END = re.compile(r"^=end[ \t]+Elten3AppInfo[ \t]*$", re.M)
DEFAULT_INSTALL_NAME = "MileByMile.eltenapp"


def extract_manifest(code: str) -> dict:
    start = MANIFEST_BEGIN.search(code)
    if start is None:
        raise SystemExit("Missing Elten3AppInfo block in __app.rb")
    rest = code[start.end():]
    end = MANIFEST_END.search(rest)
    if end is None:
        raise SystemExit("Unclosed Elten3AppInfo block in __app.rb")
    return json.loads(rest[:end.start()])


def _ctypes_zstd_compress(data: bytes, level: int) -> bytes:
    name = ctypes.util.find_library("zstd") or "zstd"
    lib = ctypes.CDLL(name)
    lib.ZSTD_compressBound.argtypes = [ctypes.c_size_t]
    lib.ZSTD_compressBound.restype = ctypes.c_size_t
    lib.ZSTD_compress.argtypes = [
        ctypes.c_void_p, ctypes.c_size_t,
        ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int,
    ]
    lib.ZSTD_compress.restype = ctypes.c_size_t
    lib.ZSTD_isError.argtypes = [ctypes.c_size_t]
    lib.ZSTD_isError.restype = ctypes.c_uint
    lib.ZSTD_getErrorName.argtypes = [ctypes.c_size_t]
    lib.ZSTD_getErrorName.restype = ctypes.c_char_p

    bound = lib.ZSTD_compressBound(len(data))
    dst = ctypes.create_string_buffer(bound)
    src = ctypes.create_string_buffer(data, len(data))
    written = lib.ZSTD_compress(dst, bound, src, len(data), level)
    if lib.ZSTD_isError(written):
        raise SystemExit(f"zstd compress error: {lib.ZSTD_getErrorName(written)}")
    return dst.raw[:written]


def init_zstd():
    try:
        import zstandard

        def compress(data: bytes, level: int) -> bytes:
            return zstandard.ZstdCompressor(level=level).compress(data)

        return compress, "zstandard module"
    except ImportError:
        pass

    if shutil.which("zstd"):
        def compress(data: bytes, level: int) -> bytes:
            proc = subprocess.run(
                ["zstd", f"-{level}", "-q", "-c"], input=data, capture_output=True,
            )
            if proc.returncode != 0:
                raise SystemExit(
                    "zstd CLI error: " + proc.stderr.decode(errors="replace"),
                )
            return proc.stdout

        return compress, "zstd CLI"

    try:
        # smoke-test ctypes loading before committing to it
        _ctypes_zstd_compress(b"x", 1)
        return _ctypes_zstd_compress, "system libzstd"
    except Exception:
        raise SystemExit(
            "No zstd backend found. Install it with: pip install zstandard",
        )


def walk_files(source_dir: Path):
    # mirrors Ruby Dir.glob(source_dir + "/**/*").sort() filtered to files;
    # sorting full paths (byte order) makes the record order deterministic
    paths = []
    for root, _dirs, files in os.walk(source_dir):
        for name in files:
            paths.append(Path(root) / name)
    paths.sort(key=lambda p: str(p))
    return paths


def language_code(relative: str):
    if not relative.startswith("locale/"):
        return None
    if Path(relative).suffix.lower() != ".mo":
        return None
    code = Path(relative).stem[:2]
    if not re.fullmatch(r"[a-zA-Z]{2}", code):
        return None
    return code.upper()


def write_named_record(out: bytearray, type_: int, name: str, content: bytes):
    name_b = name.encode("utf-8")
    if len(name_b) > 0xFFFF:
        raise SystemExit(f"File name too long: {name}")
    out.append(type_)
    out += struct.pack("<H", len(name_b))
    out += name_b
    out += struct.pack("<I", len(content))
    out += content


def build(source_dir: Path, output: Path, compress) -> int:
    main_file = source_dir / "__app.rb"
    metadata = extract_manifest(main_file.read_text(encoding="utf-8"))
    if not metadata.get("main"):
        metadata["main"] = "__app.rb"

    files = []
    for path in walk_files(source_dir):
        relative = path.relative_to(source_dir).as_posix()
        ext = path.suffix.lower()
        if ext == ".rb":
            files.append((1, relative, compress(path.read_bytes(), 19)))
        elif relative.startswith("Audio/") and ext in SOUND_EXTENSIONS:
            files.append((2, relative, path.read_bytes()))
        else:
            code = language_code(relative)
            if code is not None:
                files.append((3, code, compress(path.read_bytes(), 19)))

    code_file = bytearray(MAGIC)
    meta_bytes = json.dumps(
        metadata, ensure_ascii=False, separators=(",", ":"),
    ).encode("utf-8")
    comp_meta = compress(meta_bytes, 19)
    code_file += struct.pack("<I", len(comp_meta))
    code_file += comp_meta
    for type_, name, content in files:
        if type_ == 3:
            code_file.append(3)
            code_file += name.encode("ascii")
            code_file += struct.pack("<I", len(content))
            code_file += content
        else:
            write_named_record(code_file, type_, name, content)

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(bytes(code_file))
    print(f"Built {output} ({len(files)} files, {len(code_file) / 1024.0:.1f} KiB)")
    return len(files)


def install_to_elten(output: Path):
    appdata = os.environ.get("APPDATA")
    if not appdata:
        print("APPDATA not set (not Windows?) — install skipped.")
        return
    dst_dir = Path(appdata) / "elten" / "apps" / "src"
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / DEFAULT_INSTALL_NAME
    shutil.copyfile(output, dst)
    print(f"Installed {DEFAULT_INSTALL_NAME} into {dst_dir}")


def main():
    import argparse

    repo = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Build the MileByMile .eltenapp and (on Windows) install it into Elten.",
    )
    parser.add_argument(
        "--source", default=None,
        help=f"source dir (default: {repo / 'elten_app'})",
    )
    parser.add_argument(
        "--output", default=None,
        help="output .eltenapp path (default: <repo>/MileByMile.eltenapp)",
    )
    parser.add_argument(
        "--no-install", action="store_true",
        help="build only, do not copy into Elten apps/src",
    )
    args = parser.parse_args()

    source_dir = Path(args.source) if args.source else repo / "elten_app"
    output = Path(args.output) if args.output else repo / DEFAULT_INSTALL_NAME
    if not source_dir.is_dir():
        raise SystemExit(f"SOURCE_DIR is not a directory: {source_dir}")

    compress, backend = init_zstd()
    print(f"zstd backend: {backend}")
    build(source_dir, output, compress)
    if not args.no_install:
        install_to_elten(output)


if __name__ == "__main__":
    main()
