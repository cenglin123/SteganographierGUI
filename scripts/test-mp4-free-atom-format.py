"""Regression tests for the mp4-mode container layout.

Guards issue #26. mp4 mode used to append the archive as a bare blob after the
video, then append two "random signature + random bytes" blocks and a fake mdat
box. Xunlei (and presumably any scanner keying on structure) treated that as a
suspicious carrier: the same file that played and downloaded fine could not be
shared, while mkv mode -- which carries the archive as a container attachment --
was unaffected. Measured on a 28 KB payload: the atom chain ended exactly at the
cover's size and 44,389 bytes of bare appended data followed, including stray
GZIP/BZIP2 signatures and a second ZIP local header.

The archive now lives inside a `free` atom, which is a legal MP4 atom type that
players skip by declared size, so the file is one complete atom chain and nothing
is appended after it. The archive bytes themselves are unchanged and still sit at
the very end of the file, which is what keeps "rename it to .zip and open it with
WinRAR" working -- WinRAR scans backwards for the end-of-central-directory record.
That core behaviour is asserted here, because the first attempt at this fix (XOR
the archive to hide the PK signature) satisfied the scanner and broke exactly it.
"""

import hashlib
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULE_PATH = os.path.join(REPO_ROOT, "Steganographier.py")

PAYLOAD_NAME = "payload.bin"
PAYLOAD_SIZE = 28 * 1024  # the size the reporter used to isolate the behaviour


def build_payload(seed=20260920):
    """Incompressible bytes, so the stored archive contains no readable patterns.

    A compressible payload would let the deflate stream contain byte sequences
    that happen to look like archive signatures, which would make the
    signature-count assertion below flaky for the wrong reason.
    """
    rng = random.Random(seed)
    return bytes(rng.getrandbits(8) for _ in range(PAYLOAD_SIZE))


def write_synthetic_cover(path):
    """A minimal but well-formed top-level atom chain: ftyp, free, mdat, moov.

    The mp4 pack path copies the cover verbatim and appends to it, so a real
    video is not needed and a 4 KB fixture keeps this test hermetic and fast.
    """

    def atom(atom_type, payload=b""):
        return struct.pack(">I4s", 8 + len(payload), atom_type) + payload

    data = (
        atom(b"ftyp", b"isom" + struct.pack(">I", 512) + b"isomiso2mp41")
        + atom(b"free")
        + atom(b"mdat", b"\x00" * 4096)
        + atom(b"moov", b"\x00" * 128)
    )
    with open(path, "wb") as handle:
        handle.write(data)


def walk_top_level_atoms(path):
    """Return (atoms, end_of_walk, file_size) for the top-level atom chain.

    The walk stops at the first thing that is not a plausible atom, which is
    precisely what a bare appended archive is.
    """
    atoms = []
    with open(path, "rb") as handle:
        handle.seek(0, os.SEEK_END)
        size = handle.tell()
        pos = 0
        while pos + 8 <= size:
            handle.seek(pos)
            header = handle.read(8)
            if len(header) < 8:
                break
            declared = struct.unpack(">I", header[:4])[0]
            atom_type = header[4:8]
            if declared == 1:
                extended = handle.read(8)
                if len(extended) < 8:
                    break
                declared = struct.unpack(">Q", extended)[0]
                if declared < 16:
                    break
            elif declared == 0:
                declared = size - pos
            if declared < 8 or pos + declared > size:
                break
            atoms.append((atom_type, declared, pos))
            pos += declared
    return atoms, pos, size


def run_cli(*arguments):
    return subprocess.run(
        [sys.executable, MODULE_PATH] + list(arguments),
        cwd=REPO_ROOT,
        capture_output=True,
        timeout=300,
    )


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hide(payload_path, cover_path, output_path):
    result = run_cli(
        "-i", payload_path,
        "-c", cover_path,
        "-t", "mp4",
        "-o", output_path,
        "--no-log",
    )
    if result.returncode != 0:
        raise AssertionError(
            "hide failed with exit code %d\n%s\n%s"
            % (result.returncode, result.stdout.decode("utf-8", "replace"),
               result.stderr.decode("utf-8", "replace"))
        )


def test_atom_chain_covers_the_whole_file(stego_path):
    atoms, end, size = walk_top_level_atoms(stego_path)
    if end != size:
        raise AssertionError(
            "the atom chain stops at %d but the file is %d bytes: %d bytes are "
            "appended outside any atom (this is the structure issue #26 was "
            "about). Atoms seen: %s"
            % (end, size, size - end, [(t.decode('latin1'), s) for t, s, _ in atoms])
        )
    if not atoms or atoms[-1][0] != b"free":
        raise AssertionError(
            "expected the last top-level atom to be the free atom carrying the "
            "archive, got %s" % [t.decode("latin1") for t, _, _ in atoms]
        )
    # The old layout ended with a fake empty mdat box written by the removed
    # add_randomization_data(). Kept as an explicit guard against its return.
    with open(stego_path, "rb") as handle:
        handle.seek(-8, os.SEEK_END)
        if handle.read() == struct.pack(">I4s", 8, b"mdat"):
            raise AssertionError("file still ends with the fake mdat box")
    print("  ok   atom chain tiles the file (%d atoms, ends with free)" % len(atoms))


def test_free_atom_payload_is_padded(stego_path):
    atoms, end, size = walk_top_level_atoms(stego_path)
    atom_type, declared, offset = atoms[-1]
    with open(stego_path, "rb") as handle:
        handle.seek(offset + 8)
        payload = handle.read(declared - 8)
    if len(payload) != declared - 8:
        raise AssertionError("free atom payload is short")
    if payload.startswith(b"PK\x03\x04"):
        raise AssertionError(
            "free atom payload starts with a ZIP local header; the random padding "
            "that keeps a PK signature off the atom boundary is missing"
        )
    if payload.find(b"PK\x03\x04") < 0:
        raise AssertionError("no ZIP local header found inside the free atom")
    print("  ok   free atom payload is padded and contains the archive")


def test_no_stray_archive_signatures(stego_path):
    with open(stego_path, "rb") as handle:
        blob = handle.read()
    # One local file header per member, and nothing else: the previous layout
    # wrote extra archive-looking signatures after the real archive.
    local_headers = blob.count(b"PK\x03\x04")
    if local_headers != 1:
        raise AssertionError(
            "expected exactly 1 ZIP local header in the file, found %d"
            % local_headers
        )
    for name, signature in (
        ("RAR4", b"Rar!\x1a\x07\x00"),
        ("RAR5", b"Rar!\x1a\x07\x01\x00"),
        ("7Z", b"7z\xbc\xaf\x27\x1c"),
        ("XZ", b"\xfd7zXZ\x00"),
    ):
        if signature in blob:
            raise AssertionError("found a stray %s signature in the output" % name)
    print("  ok   no stray archive signatures")


def test_archive_is_recoverable_from_the_whole_file(stego_path, payload_path):
    """The WinRAR mechanism: a backwards EOCD scan over the whole file.

    zipfile locates the archive the same way WinRAR does (scan back for the
    end-of-central-directory record) and tolerates everything prepended to it,
    so this is a faithful proxy and runs everywhere.
    """
    with zipfile.ZipFile(stego_path) as archive:
        names = archive.namelist()
        if names != [PAYLOAD_NAME]:
            raise AssertionError("unexpected archive members: %s" % names)
        with archive.open(PAYLOAD_NAME) as member:
            content = member.read()
    if hashlib.sha256(content).hexdigest() != sha256_of(payload_path):
        raise AssertionError("archive member does not match the original payload")
    print("  ok   archive recoverable from the whole file, content identical")


def test_cli_reveal_round_trip(stego_path, payload_path):
    reveal_dir = os.path.dirname(stego_path)
    result = run_cli("-r", "-i", stego_path, "--keep-original", "--no-log")
    if result.returncode != 0:
        raise AssertionError(
            "reveal failed with exit code %d\n%s\n%s"
            % (result.returncode, result.stdout.decode("utf-8", "replace"),
               result.stderr.decode("utf-8", "replace"))
        )
    extracted = os.path.join(reveal_dir, PAYLOAD_NAME)
    if not os.path.exists(extracted):
        raise AssertionError("reveal produced no %s" % PAYLOAD_NAME)
    if sha256_of(extracted) != sha256_of(payload_path):
        raise AssertionError("revealed file differs from the original payload")
    print("  ok   CLI reveal round-trips the payload")


def test_output_still_varies_between_runs(first_path, second_path):
    """Unique output per run used to come from add_randomization_data().

    That is gone, so the guarantee now rests on the random padding; assert it
    rather than assume it.
    """
    if sha256_of(first_path) == sha256_of(second_path):
        raise AssertionError(
            "two runs produced byte-identical output; the per-run randomisation "
            "the removed add_randomization_data() provided is no longer happening"
        )
    print("  ok   consecutive runs produce different bytes")


def main():
    work_root = tempfile.mkdtemp(prefix="steg-mp4-free-atom-test-")
    try:
        payload_path = os.path.join(work_root, PAYLOAD_NAME)
        with open(payload_path, "wb") as handle:
            handle.write(build_payload())
        cover_path = os.path.join(work_root, "cover.mp4")
        write_synthetic_cover(cover_path)

        # Each stego file gets its own directory: reveal writes the payload next
        # to its input, and a pre-existing file of that name would collide.
        first_dir = os.path.join(work_root, "first")
        second_dir = os.path.join(work_root, "second")
        os.makedirs(first_dir)
        os.makedirs(second_dir)
        first_path = os.path.join(first_dir, "stego.mp4")
        second_path = os.path.join(second_dir, "stego.mp4")

        print("mp4 mode container layout")
        hide(payload_path, cover_path, first_path)
        hide(payload_path, cover_path, second_path)
        test_atom_chain_covers_the_whole_file(first_path)
        test_free_atom_payload_is_padded(first_path)
        test_no_stray_archive_signatures(first_path)
        print("extraction compatibility")
        test_archive_is_recoverable_from_the_whole_file(first_path, payload_path)
        test_cli_reveal_round_trip(first_path, payload_path)
        test_output_still_varies_between_runs(first_path, second_path)
    finally:
        shutil.rmtree(work_root, ignore_errors=True)

    print("mp4 free-atom format tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
