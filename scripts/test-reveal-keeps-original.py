"""Regression tests for deleting the original stego file after a reveal.

Guards a data-loss path: reveal_file() deleted the input whenever an extraction
method reported success, without checking that anything had actually reached the
disk. An archive whose members are all directory entries, an empty archive, or
names that sanitize_path() rejects all end with a method returning True and zero
files written -- and the original was removed anyway. The archive inside the
stego file is the only remaining copy once that happens.

The two halves are both asserted, because a guard that simply stopped deleting
anything would pass the first half and silently break the documented default
(delete_original_after_reveal defaults to True).
"""

import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULE_PATH = os.path.join(REPO_ROOT, "Steganographier.py")

PAYLOAD_NAME = "payload.bin"
PAYLOAD_SIZE = 28 * 1024


def build_payload(seed=20260921):
    import random

    rng = random.Random(seed)
    return bytes(rng.getrandbits(8) for _ in range(PAYLOAD_SIZE))


def write_synthetic_cover(path):
    """A minimal but well-formed top-level atom chain."""

    def atom(atom_type, payload=b""):
        return struct.pack(">I4s", 8 + len(payload), atom_type) + payload

    data = (
        atom(b"ftyp", b"isom" + struct.pack(">I", 512) + b"isomiso2mp41")
        + atom(b"free")
        + atom(b"mdat", b"\x00" * 2048)
        + atom(b"moov", b"\x00" * 64)
    )
    with open(path, "wb") as handle:
        handle.write(data)


def append_directory_only_archive(cover_path, stego_path):
    """Append an archive whose only member is a directory entry.

    This is a legitimate thing for a user to have produced (zipping an empty
    folder), and it is the shape that makes an extractor report success while
    writing no files.
    """
    with open(stego_path, "wb") as handle:
        with open(cover_path, "rb") as cover:
            shutil.copyfileobj(cover, handle)
        with zipfile.ZipFile(handle, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("empty-folder/", b"")


def run_cli(*arguments):
    return subprocess.run(
        [sys.executable, MODULE_PATH] + list(arguments),
        cwd=REPO_ROOT,
        capture_output=True,
        timeout=300,
    )


def hide(payload_path, cover_path, output_path):
    result = run_cli(
        "-i", payload_path, "-c", cover_path, "-t", "mp4", "-o", output_path, "--no-log"
    )
    if result.returncode != 0:
        raise AssertionError(
            "hide failed (%d)\n%s" % (result.returncode, result.stderr.decode("utf-8", "replace"))
        )


def test_nothing_written_keeps_the_original(work_root):
    cover_path = os.path.join(work_root, "cover-empty.zip-case.mp4")
    write_synthetic_cover(cover_path)
    stego_path = os.path.join(work_root, "dir-only.mp4")
    append_directory_only_archive(cover_path, stego_path)

    result = run_cli("-r", "-i", stego_path, "--no-log")
    if result.returncode != 0:
        raise AssertionError(
            "reveal failed (%d)\n%s" % (result.returncode, result.stderr.decode("utf-8", "replace"))
        )
    if not os.path.exists(stego_path):
        raise AssertionError(
            "the stego file was deleted even though no file was extracted from it; "
            "the archive inside it was the only remaining copy"
        )
    print("  ok   nothing extracted -> original stego file kept")


def test_normal_reveal_still_deletes_the_original(work_root):
    payload_path = os.path.join(work_root, PAYLOAD_NAME)
    with open(payload_path, "wb") as handle:
        handle.write(build_payload())
    cover_path = os.path.join(work_root, "cover-normal.mp4")
    write_synthetic_cover(cover_path)

    # Its own directory: reveal writes the payload next to its input.
    case_dir = os.path.join(work_root, "normal")
    os.makedirs(case_dir)
    stego_path = os.path.join(case_dir, "stego.mp4")
    hide(payload_path, cover_path, stego_path)

    result = run_cli("-r", "-i", stego_path, "--no-log")
    if result.returncode != 0:
        raise AssertionError(
            "reveal failed (%d)\n%s" % (result.returncode, result.stderr.decode("utf-8", "replace"))
        )
    extracted = os.path.join(case_dir, PAYLOAD_NAME)
    if not os.path.exists(extracted):
        raise AssertionError("reveal produced no %s" % PAYLOAD_NAME)
    if open(extracted, "rb").read() != build_payload():
        raise AssertionError("revealed file differs from the original payload")
    if os.path.exists(stego_path):
        raise AssertionError(
            "the stego file survived a successful reveal; the default is to delete it "
            "and this guard must not change that"
        )
    print("  ok   successful reveal still deletes the original")


def test_keep_original_flag_still_works(work_root):
    payload_path = os.path.join(work_root, PAYLOAD_NAME)
    cover_path = os.path.join(work_root, "cover-normal.mp4")
    case_dir = os.path.join(work_root, "keep")
    os.makedirs(case_dir)
    stego_path = os.path.join(case_dir, "stego.mp4")
    hide(payload_path, cover_path, stego_path)

    result = run_cli("-r", "-i", stego_path, "--keep-original", "--no-log")
    if result.returncode != 0:
        raise AssertionError("reveal --keep-original failed (%d)" % result.returncode)
    if not os.path.exists(stego_path):
        raise AssertionError("--keep-original did not keep the original")
    print("  ok   --keep-original still keeps the original")


def main():
    work_root = tempfile.mkdtemp(prefix="steg-reveal-keep-test-")
    try:
        print("reveal deleting the original")
        test_nothing_written_keeps_the_original(work_root)
        test_normal_reveal_still_deletes_the_original(work_root)
        test_keep_original_flag_still_works(work_root)
    finally:
        shutil.rmtree(work_root, ignore_errors=True)

    print("reveal keep-original tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
