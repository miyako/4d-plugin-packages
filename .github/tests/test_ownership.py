"""Actual native sources plus complete pinned SDK, unsigned synthetic host only."""

import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("OWNERSHIP_SOURCE_ROOT", ROOT)).resolve()
SDK = {
    "4DPluginAPI.c": "bdb2e7894e66d5abf3ebfedb41aa4e47739e2fc6",
    "4DPluginAPI.h": "9054b45ffc7ff6f5b8d57529a3788a55d977b314",
    "EntryPoints.h": "730f2f77ff2713fb2fe4b7d6562baeedf5f664cb",
    "Flags.h": "fdd2757c25d9a2f95c23614a003d61669feb8638",
    "PrivateTypes.h": "77053dc0c0a3718d2d3b6f158371a6af78c6ae66",
    "PublicTypes.h": "2bb392e73e9c556c274fe0a75b3a6b83e310b77c",
    "4DPluginAPI.def": "996ecc4ab11ad165de9192eba2e7478db141c757",
}


@unittest.skipUnless(sys.platform == "darwin", "macOS synthetic platform harness")
class OwnershipTests(unittest.TestCase):
    leaf_runs = 0
    leaf_passes = 0

    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(
            prefix="packages-ownership-", dir=os.environ.get("OWNERSHIP_TMPDIR"),
        )
        cls.binary = Path(cls.temp.name) / "ownership"
        api = SOURCE / "4D Plugin API"
        for name, expected in SDK.items():
            contents = (api / name).read_bytes()
            blob = hashlib.sha1(f"blob {len(contents)}\0".encode() + contents).hexdigest()
            if blob != expected:
                cls.temp.cleanup()
                raise AssertionError(f"Re-audit changed SDK: {name}: {blob}")
        command = [
            "clang++", "-std=c++14", "-x", "objective-c++",
            "-include", str(ROOT / ".github/tests/ownership_platform.h"),
            "-I", str(api), "-I", str(api / "Classes"),
            "-fsanitize=address,undefined", "-fno-sanitize=alignment",
            "-fno-omit-frame-pointer", "-g",
            "-Wno-deprecated-declarations", "-Wno-return-type-c-linkage",
            "-Wno-ignored-attributes", "-Wno-writable-strings",
            str(api / "4DPluginAPI.c"),
            *map(str, sorted((api / "Classes").glob("*.cpp"))),
            str(SOURCE / "4DPlugin.cpp"),
            str(ROOT / ".github/tests/ownership_host.mm"),
            "-framework", "Cocoa", "-framework", "Carbon", "-framework", "ImageIO",
            "-o", str(cls.binary),
        ]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            cls.temp.cleanup()
            raise AssertionError(result.stdout + result.stderr)
        imports = subprocess.check_output(["nm", "-u", str(cls.binary)], text=True)
        forbidden = (
            "_OBJC_CLASS_$_NSWorkspace", "_OBJC_CLASS_$_NSFileManager",
            "_OBJC_CLASS_$_NSURL", "_OBJC_CLASS_$_NSImage",
            "_CFURLCreateWithFileSystemPath", "_CFURLCopyFileSystemPath",
            "_CGImageDestinationCreateWithData", "_CGImageDestinationAddImage",
            "_CGImageDestinationFinalize", "_system", "_popen", "_execve",
            "_posix_spawn",
        )
        for symbol in forbidden:
            if any(line.strip().endswith(symbol) for line in imports.splitlines()):
                cls.temp.cleanup()
                raise AssertionError(f"Real platform boundary linked: {symbol}")

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()
        print(f"LEAF runs={cls.leaf_runs} passed={cls.leaf_passes} "
              f"failed={cls.leaf_runs - cls.leaf_passes}", file=sys.stderr)

    def run_case(self, case, text="", empty="allocated", *args):
        type(self).leaf_runs += 1
        result = subprocess.run(
            [str(self.binary), case, text, empty, *map(str, args)],
            env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0",
                 "UBSAN_OPTIONS": "halt_on_error=1"},
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            type(self).leaf_passes += 1
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("strings=0 pictures=0 handles=0 objects=0 collections=0", result.stdout)

    def test_path_single_disposal_and_retained_output(self):
        for text in ("ASCII", "\u65e5", "\U0001f600", ""):
            for empty in ("allocated", "null"):
                with self.subTest(text=text, empty=empty):
                    self.run_case("path", text, empty)

    def test_setbytes_temporary_release(self):
        self.run_case("bytes")

    def test_copy_byte_unit_boundary(self):
        for text in (".png", "\u65e5", "\U0001f600"):
            with self.subTest(text=text):
                self.run_case("copy", text, "null")

    def test_copy_initial_empty_owners(self):
        self.run_case("copy", "")

    def test_grayscale_initial_empty_owner(self):
        self.run_case("gray")

    def test_size_input_owner(self):
        self.run_case("size")

    def test_thumbnail_input_and_owning_return(self):
        self.run_case("thumbnail")

    def test_array_transfers_copies_churn_shrink_clear_rejection(self):
        for empty in ("allocated", "null"):
            with self.subTest(empty=empty):
                self.run_case("arrays", "", empty)

    def test_scalar_borrowed_copy_and_content_setter_returns(self):
        for text in ("ASCII", "\u65e5", "\U0001f600", ""):
            for empty in ("allocated", "null"):
                with self.subTest(text=text, empty=empty):
                    self.run_case("scalar", text, empty)

    def test_command_failure_preserves_owners_and_surfaces_error(self):
        for case in ("path", "copy", "gray", "size", "thumbnail"):
            for failure in ("handle", "command"):
                with self.subTest(case=case, failure=failure):
                    self.run_case(f"{case}-{failure}-failure")

    def test_sdk_failure_contract_characterization(self):
        self.run_case("sdk-failures")

    def test_pointer_success_owning_lookup_and_failure_poison(self):
        for case in ("pointer", "pointer-failure"):
            with self.subTest(case=case):
                self.run_case(case, "ASCII")

    def test_dispatch_all_commands_synthetic_boundaries(self):
        for selector in range(1, 12):
            with self.subTest(selector=selector):
                self.run_case("dispatch", "ASCII", "allocated", selector, 0)

    def test_dispatch_strings_exact_and_property_failure(self):
        for selector in (6, 11):
            for text in ("ASCII", "\u65e5", "\U0001f600", ""):
                for empty in ("allocated", "null"):
                    for mode in (0, 4):
                        with self.subTest(selector=selector, text=text, empty=empty, mode=mode):
                            self.run_case("dispatch", text, empty, selector, mode)
        self.run_case("dispatch", "ASCII", "allocated", 6, 1)

    def test_dispatch_icon_success_and_failures(self):
        for mode in range(6):
            with self.subTest(mode=mode):
                self.run_case("dispatch", "", "allocated", 10, mode)


if __name__ == "__main__":
    unittest.main()
