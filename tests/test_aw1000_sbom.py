#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
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
        self.feeds = self.root / "OPENWRT-FEEDS.txt"
        self.phone_source = self.root / "phone-source.tar.gz"
        self.build_info = self.root / "BUILDINFO.txt"
        self.build_config = self.root / "aw1000-max.config"
        self.output = self.root / "sbom.cdx.json"
        self.manifest.write_text(
            "base-files - 1652~a1b2c3d4\n"
            "busybox - 1.36.1-r2\n"
            "kmod-nft-core - 6.6.80~r1\n",
            encoding="utf-8",
        )
        self.firmware.write_bytes(b"factory-ubi-image")
        self.packages.write_bytes(b"apk-ipk-package-archive")
        self.feeds.write_text("openwrt/base revision abc123\\n", encoding="utf-8")
        self.phone_source.write_bytes(b"pinned-phone-source-archive")
        self.build_info.write_text("source commit: 0123456789abcdef\\n", encoding="utf-8")
        self.build_config.write_text("CONFIG_TARGET_qualcommax=y\\n", encoding="utf-8")
        self.args = SBOM.argparse.Namespace(
            manifest=self.manifest,
            firmware_image=self.firmware,
            packages_archive=self.packages,
            feeds_report=self.feeds,
            phone_source_archive=self.phone_source,
            build_info=self.build_info,
            build_config=self.build_config,
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
        self.assertEqual(len(sbom["components"]), 10)
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
        self.assertEqual(
            props["quantumgrid:package-manifest-sha256"],
            hashlib.sha256(self.manifest.read_bytes()).hexdigest(),
        )
        self.assertEqual(
            props["quantumgrid:openwrt-feed-report-sha256"],
            hashlib.sha256(self.feeds.read_bytes()).hexdigest(),
        )
        self.assertEqual(
            props["quantumgrid:phone-source-archive-sha256"],
            hashlib.sha256(self.phone_source.read_bytes()).hexdigest(),
        )
        self.assertEqual(
            props["quantumgrid:buildinfo-sha256"],
            hashlib.sha256(self.build_info.read_bytes()).hexdigest(),
        )
        self.assertEqual(
            props["quantumgrid:build-config-sha256"],
            hashlib.sha256(self.build_config.read_bytes()).hexdigest(),
        )
        evidence = {
            item["name"]: item for item in sbom["components"] if item["type"] == "file"
        }
        self.assertEqual(
            set(evidence),
            {
                self.packages.name,
                self.manifest.name,
                self.feeds.name,
                self.phone_source.name,
                self.build_info.name,
                self.build_config.name,
            },
        )
        for item in evidence.values():
            self.assertEqual(len(item["hashes"]), 1)
            self.assertEqual(item["hashes"][0]["alg"], "SHA-256")
            self.assertRegex(item["hashes"][0]["content"], r"^[0-9a-f]{64}$")
        self.assertEqual(len(sbom["dependencies"][0]["dependsOn"]), 3)

    def test_cli_writes_json_and_refuses_to_overwrite_existing_sbom(self) -> None:
        command = [
            sys.executable,
            str(SCRIPT),
            "--manifest", str(self.manifest),
            "--firmware-image", str(self.firmware),
            "--packages-archive", str(self.packages),
            "--feeds-report", str(self.feeds),
            "--phone-source-archive", str(self.phone_source),
            "--build-info", str(self.build_info),
            "--build-config", str(self.build_config),
            "--output", str(self.output),
            "--version", self.args.version,
            "--target", self.args.target,
            "--profile", self.args.profile,
            "--build-profile", self.args.build_profile,
            "--source-commit", self.args.source_commit,
            "--openwrt-commit", self.args.openwrt_commit,
        ]
        first = subprocess.run(command, check=False, capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        sbom = json.loads(self.output.read_text(encoding="utf-8"))
        self.assertEqual(sbom["specVersion"], "1.6")
        second = subprocess.run(command, check=False, capture_output=True, text=True)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("File exists", second.stderr)

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

    def test_manifest_enforces_component_limit(self) -> None:
        self.manifest.write_text(
            "".join(f"package-{index} - 1.0.0\n" for index in range(SBOM.MAX_PACKAGES + 1)),
            encoding="utf-8",
        )
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

    def test_manifest_must_be_regular_and_within_size_limit(self) -> None:
        link = self.root / "manifest-link"
        link.symlink_to(self.manifest)
        with self.assertRaises(SBOM.SbomError):
            SBOM.parse_manifest(link)
        self.manifest.write_bytes(b"#" + b"x" * (4 * 1024 * 1024))
        with self.assertRaises(SBOM.SbomError):
            SBOM.parse_manifest(self.manifest)

    def test_sbom_dependency_references_resolve_to_components(self) -> None:
        sbom = SBOM.build_sbom(self.args)
        refs = {item["bom-ref"] for item in sbom["components"]}
        dependencies = sbom["dependencies"]
        self.assertEqual(len(dependencies), 1)
        self.assertTrue(set(dependencies[0]["dependsOn"]).issubset(refs))
        self.assertEqual(len(refs), len(sbom["components"]), "component bom-ref values must be unique")
        self.assertEqual(len(dependencies[0]["dependsOn"]), 3)

    def test_rejects_unadmitted_build_profile_and_control_characters(self) -> None:
        self.args.build_profile = "unreviewed router image"
        with self.assertRaises(SBOM.SbomError):
            SBOM.build_sbom(self.args)
        self.args.build_profile = "AW1000 stable upstream OpenWrt"
        self.args.version = "0.4.0\\nmalicious"
        with self.assertRaises(SBOM.SbomError):
            SBOM.build_sbom(self.args)

    def test_metadata_evidence_inputs_must_be_nonempty_regular_files(self) -> None:
        for attr in ("feeds_report", "phone_source_archive", "build_info", "build_config"):
            path = getattr(self.args, attr)
            path.write_bytes(b"")
            with self.subTest(artifact=attr):
                with self.assertRaises(SBOM.SbomError):
                    SBOM.build_sbom(self.args)
            path.write_bytes(b"valid-evidence")
        link = self.root / "feeds-link.txt"
        link.symlink_to(self.feeds)
        self.args.feeds_report = link
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
