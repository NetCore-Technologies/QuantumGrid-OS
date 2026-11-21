#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "generate-aw1000-sbom.py"
SPEC = importlib.util.spec_from_file_location("quantumgrid_sbom", SCRIPT)
assert SPEC and SPEC.loader
SBOM = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SBOM)


class Aw1000SbomTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.manifest = self.root / "aw1000.manifest"
        self.firmware = self.root / "factory.ubi"
        self.packages = self.root / "packages.tar.zst"
        self.output = self.root / "sbom.cdx.json"
        self.manifest.write_text(
            "base-files - 1652~a1b2c3d4\n"
            "busybox - 1.36.1-r2\n"
            "kmod-nft-core - 6.6.80~r1\n",
            encoding="utf-8",
        )
        self.firmware.write_bytes(b"factory-ubi-image")
        self.packages.write_bytes(b"apk-ipk-package-archive")
        self.args = SBOM.argparse.Namespace(
            manifest=self.manifest,
            firmware_image=self.firmware,
            packages_archive=self.packages,
            output=self.output,
            version="0.4.0",
            target="qualcommax/ipq807x",
            profile="arcadyan_aw1000",
            build_profile="AW1000 stable upstream OpenWrt",
            source_commit="0123456789abcdef0123456789abcdef01234567",
            openwrt_commit="fedcba9876543210fedcba9876543210fedcba98",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_generates_cyclonedx_inventory_and_artifact_hashes(self) -> None:
        sbom = SBOM.build_sbom(self.args)
        self.assertEqual(sbom["bomFormat"], "CycloneDX")
        self.assertEqual(sbom["specVersion"], "1.6")
        self.assertEqual(len(sbom["components"]), 5)
        packages = [item for item in sbom["components"] if item["type"] == "library"]
        self.assertEqual(
            [(item["name"], item["version"]) for item in packages],
            [
                ("base-files", "1652~a1b2c3d4"),
                ("busybox", "1.36.1-r2"),
                ("kmod-nft-core", "6.6.80~r1"),
            ],
        )
        root = sbom["metadata"]["component"]
        props = {item["name"]: item["value"] for item in root["properties"]}
        self.assertEqual(props["quantumgrid:device"], "Arcadyan AW1000")
        self.assertEqual(props["quantumgrid:package-count"], "3")
        self.assertEqual(
            props["quantumgrid:firmware-image-sha256"],
            hashlib.sha256(self.firmware.read_bytes()).hexdigest(),
        )
        self.assertEqual(
            props["quantumgrid:package-archive-sha256"],
            hashlib.sha256(self.packages.read_bytes()).hexdigest(),
        )
        self.assertEqual(len(sbom["dependencies"][0]["dependsOn"]), 3)

    def test_cli_writes_json_and_refuses_to_overwrite_existing_sbom(self) -> None:
        sbom = SBOM.build_sbom(self.args)
        with self.output.open("x", encoding="utf-8") as handle:
            json.dump(sbom, handle)
        self.assertEqual(json.loads(self.output.read_text())["specVersion"], "1.6")
        with self.assertRaises(FileExistsError):
            with self.output.open("x", encoding="utf-8"):
                pass

    def test_manifest_rejects_malformed_and_duplicate_rows(self) -> None:
        for invalid in (
            "base-files 1652~a1b2c3d4\n",
            "base-files - 1\nbase-files - 2\n",
            "bad/name - 1\n",
            "base-files - bad version\n",
            "base-files - 1 extra\n",
            "\n# empty manifest\n",
        ):
            self.manifest.write_text(invalid, encoding="utf-8")
            with self.subTest(manifest=invalid):
                with self.assertRaises(SBOM.SbomError):
                    SBOM.parse_manifest(self.manifest)

    def test_rejects_wrong_profile_and_incomplete_build_identity(self) -> None:
        self.args.profile = "other-router"
        with self.assertRaises(SBOM.SbomError):
            SBOM.build_sbom(self.args)
        self.args.profile = "arcadyan_aw1000"
        self.args.source_commit = "not-a-full-git-sha"
        with self.assertRaises(SBOM.SbomError):
            SBOM.build_sbom(self.args)

    def test_artifact_inputs_must_be_regular_non_symlink_files(self) -> None:
        link = self.root / "firmware-link.ubi"
        link.symlink_to(self.firmware)
        self.args.firmware_image = link
        with self.assertRaises(SBOM.SbomError):
            SBOM.build_sbom(self.args)


if __name__ == "__main__":
    unittest.main()
