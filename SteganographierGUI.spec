# -*- mode: python ; coding: utf-8 -*-

from PyInstaller.utils.hooks import collect_data_files


tkinterdnd_data = collect_data_files("tkinterdnd2")

a = Analysis(
    ["Steganographier.py"],
    pathex=[],
    binaries=[],
    datas=tkinterdnd_data,
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="SteganographierGUI",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    version="build/version_info.txt",
    icon="modules/favicon.ico",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    name="SteganographierGUI",
    # PyInstaller 6 moved the bundled runtime into a _internal subdirectory by
    # default; stated explicitly so the layout cannot drift back. Without it the
    # distribution root holds ~70 loose runtime files (python3*.dll, api-ms-win-*,
    # *.pyd, base_library.zip), which is what v1.3.10 shipped and v1.3.9 did not.
    contents_directory="_internal",
)
