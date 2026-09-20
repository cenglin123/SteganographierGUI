"""Regression tests for the temporary archive used during steganography.

Guards a defect where a directory path with a trailing separator (exactly what
PowerShell produces when you tab-complete a folder name, e.g. '.\\folder\\')
made the temporary zip land *inside* the input directory. compress_files() then
os.walk()ed that directory, found the archive itself, and zipfile.write()
copied the archive into itself -- reading and appending to the same file -- so
the archive grew without bound (measured ~60 MB/s: 1 MB of input reached 7.25 GB
in 120 seconds) and the command never finished.

A watchdog thread is required: in the broken case the offending write() call
never returns, so no post-hoc size assertion can ever run.
"""

import importlib.util
import os
import random
import shutil
import sys
import tempfile
import threading
import time
import zipfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULE_PATH = os.path.join(REPO_ROOT, "Steganographier.py")

# A healthy run compresses ~1 MB. Anything past the cap means the archive is
# feeding on itself, so abort the whole test process rather than risk the disk.
ARCHIVE_CAP_BYTES = 32 * 1024 * 1024
WORKER_COUNT = 3
WORKER_SIZE = 200 * 1024


def load_module():
    spec = importlib.util.spec_from_file_location("steganographier_under_test",
                                                  MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def is_inside(child, parent):
    child_abs = os.path.normcase(os.path.abspath(child))
    parent_abs = os.path.normcase(os.path.abspath(parent))
    return child_abs != parent_abs and child_abs.startswith(parent_abs + os.sep)


def make_fixture(root, folder_name):
    """Create a folder with deterministic, incompressible-ish payload files."""
    folder = os.path.join(root, folder_name)
    os.makedirs(folder)
    expected = []
    for index in range(WORKER_COUNT):
        name = "worker%d.bin" % index
        rng = random.Random(1000 + index)
        payload = bytes(rng.getrandbits(8) for _ in range(WORKER_SIZE))
        with open(os.path.join(folder, name), "wb") as handle:
            handle.write(payload)
        expected.append(name)
    return folder, sorted(expected)


class Watchdog:
    """Abort hard if the archive grows past the cap.

    os._exit() skips the caller's finally block, so the fixture directory must
    be removed here or a detected regression would leave the runaway archive
    behind. rmtree may fail while the writer still holds the file open, hence
    ignore_errors.
    """

    def __init__(self, archive_path, cleanup_root=None, cap=ARCHIVE_CAP_BYTES):
        self.archive_path = archive_path
        self.cleanup_root = cleanup_root
        self.cap = cap
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        while not self.stop_event.is_set():
            try:
                size = os.path.getsize(self.archive_path)
            except OSError:
                size = 0
            if size > self.cap:
                if self.cleanup_root:
                    shutil.rmtree(self.cleanup_root, ignore_errors=True)
                sys.stdout.flush()
                sys.stderr.write(
                    "\nFAIL: archive '%s' exceeded %d bytes; it is being "
                    "written into itself and will never finish.\n"
                    % (self.archive_path, self.cap))
                sys.stderr.flush()
                os._exit(3)
            time.sleep(0.02)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.stop_event.set()
        return False


def make_compressor(module):
    """A Steganographier instance without running __init__ (no GUI needed)."""
    compressor = module.Steganographier.__new__(module.Steganographier)
    compressor.progress_callback = None
    compressor.log = lambda message: None
    return compressor


def test_archive_never_lands_inside_input(module):
    """The trailing-separator form must not put the archive in the input dir."""
    failures = []
    base = os.path.join(tempfile.gettempdir(), "StegGUI archive path test")
    cases = [
        ("plain", os.path.join(base, "folder")),
        ("trailing separator", os.path.join(base, "folder") + os.sep),
        ("double trailing separator", os.path.join(base, "folder") + os.sep * 2),
        ("trailing separator + dot", os.path.join(base, "folder") + os.sep + "."),
    ]
    for label, input_path in cases:
        input_directory = os.path.normpath(input_path)
        archive = module.build_temp_archive_path(input_path)
        if is_inside(archive, input_directory):
            failures.append(
                "%-26s archive '%s' is inside input directory '%s'"
                % (label, archive, input_directory))
        elif os.path.dirname(os.path.normcase(os.path.abspath(archive))) != \
                os.path.dirname(os.path.normcase(os.path.abspath(input_directory))):
            failures.append(
                "%-26s archive '%s' is not a sibling of '%s'"
                % (label, archive, input_directory))
        else:
            print("  ok   %-26s -> %s" % (label, os.path.basename(archive)))

    if failures:
        raise AssertionError("build_temp_archive_path:\n  " + "\n  ".join(failures))


def test_compress_excludes_archive_from_itself(module, work_root):
    """Even with the archive forced inside the input dir, compress must finish."""
    folder_name = "self_include_case"
    folder, expected_names = make_fixture(work_root, folder_name)
    # Deliberately reproduce the broken layout: archive inside the input dir.
    archive = os.path.join(folder, "_hidden_0.zip")

    with Watchdog(archive, work_root):
        started = time.time()
        make_compressor(module).compress_files(archive, folder + os.sep)
        elapsed = time.time() - started

    if not os.path.exists(archive):
        raise AssertionError("compress_files did not produce an archive")

    with zipfile.ZipFile(archive) as handle:
        stored = sorted(os.path.basename(name.replace("/", os.sep))
                        for name in handle.namelist())

    if stored != expected_names:
        raise AssertionError(
            "archive members are %r, expected exactly %r"
            % (stored, expected_names))

    archive_size = os.path.getsize(archive)
    if archive_size > ARCHIVE_CAP_BYTES:
        raise AssertionError("archive unexpectedly large: %d" % archive_size)

    print("  ok   archive excluded itself; %d members, %d bytes, %.2fs"
          % (len(stored), archive_size, elapsed))


def test_normal_input_keeps_folder_prefix(module, work_root):
    """A plain folder argument still names members after the folder."""
    folder_name = "normal_case"
    folder, expected_names = make_fixture(work_root, folder_name)
    archive = module.build_temp_archive_path(folder)

    if is_inside(archive, folder):
        raise AssertionError("archive landed inside the input directory")

    with Watchdog(archive, work_root):
        make_compressor(module).compress_files(archive, folder)

    with zipfile.ZipFile(archive) as handle:
        stored = sorted(handle.namelist())

    # zipfile.write() rewrites os.sep to '/' inside the archive.
    expected = sorted(os.path.join(folder_name, name).replace(os.sep, "/")
                      for name in expected_names)
    if stored != expected:
        raise AssertionError("archive members are %r, expected %r"
                             % (stored, expected))

    print("  ok   folder prefix preserved: %s" % (stored[0],))


def main():
    module = load_module()
    work_root = tempfile.mkdtemp(prefix="steg-temp-archive-test-")
    try:
        print("build_temp_archive_path")
        test_archive_never_lands_inside_input(module)
        print("compress_files self-inclusion")
        test_compress_excludes_archive_from_itself(module, work_root)
        print("compress_files normal input")
        test_normal_input_keeps_folder_prefix(module, work_root)
    finally:
        shutil.rmtree(work_root, ignore_errors=True)

    print("Temporary-archive tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
