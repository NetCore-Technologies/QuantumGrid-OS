#!/usr/bin/env python3
"""Regression tests for QuantumGrid's declarative hardware profile contract."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "profiles" / "arcadyan-aw1000.json"
VALIDATOR_PATH = ROOT / "scripts" / "verify-device-profile.py"

SPEC = importlib.util.spec_from_file_location("qg_device_profile_validator", VALIDATOR_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load device profile validator")
VALIDATOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VALIDATOR
SPEC.loader.exec_module(VALIDATOR)


class DeviceProfileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(prefix=".device-profile-test-", dir=ROOT)
        self.temp_path = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def write_profile(self, value: dict) -> Path:
        path = self.temp_path / "profile.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def profile(self) -> dict:
        return json.loads(PROFILE.read_text(encoding="utf-8"))

    def test_aw1000_profile_matches_its_pinned_openwrt_config(self) -> None:
        fields = VALIDATOR.validate(PROFILE)
        self.assertEqual(len(fields), 17)
        self.assertEqual(fields[0], "arcadyan-aw1000")
        self.assertEqual(fields[3:6], ["qualcommax", "ipq807x", "arcadyan_aw1000"])
        self.assertEqual(fields[7], "1")
        self.assertEqual(len(fields[11].split(";")), 18)
        self.assertIn("CONFIG_ATH11K_NSS_SUPPORT=y", fields[11])
        self.assertEqual(fields[12], "1")
        self.assertEqual(fields[15], "*arcadyan_aw1000-squashfs-factory.ubi")

    def test_line_output_is_a_fixed_seventeen_field_contract(self) -> None:
        result = subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), str(PROFILE), "--lines"],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(len(result.stdout.rstrip("\n").splitlines()), 17)

    def test_tab_output_is_a_fixed_seventeen_field_contract(self) -> None:
        result = subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), str(PROFILE), "--fields"],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(len(result.stdout.rstrip("\n").split("\t")), 17)

    def test_device_must_be_selected_by_the_profile_config(self) -> None:
        profile = self.profile()
        profile["platform"]["openwrt_device"] = "another_device"
        with self.assertRaisesRegex(VALIDATOR.ProfileError, "must contain exactly one"):
            VALIDATOR.validate(self.write_profile(profile))

    def test_repository_paths_cannot_escape_with_parent_segments(self) -> None:
        profile = self.profile()
        profile["platform"]["config_file"] = "../README.md"
        with self.assertRaisesRegex(VALIDATOR.ProfileError, "escapes the repository"):
            VALIDATOR.validate(self.write_profile(profile))

    def test_artifact_globs_must_match_the_declared_device(self) -> None:
        profile = self.profile()
        profile["artifacts"]["factory_glob"] = "*another_device-squashfs-factory.ubi"
        with self.assertRaisesRegex(VALIDATOR.ProfileError, "must both include"):
            VALIDATOR.validate(self.write_profile(profile))

    def test_duplicate_board_compatibility_ids_are_rejected(self) -> None:
        profile = self.profile()
        profile["platform"]["board_compatible"].append("arcadyan,aw1000")
        with self.assertRaisesRegex(VALIDATOR.ProfileError, "duplicate board IDs"):
            VALIDATOR.validate(self.write_profile(profile))

    def test_unsupported_nss_must_not_carry_build_inputs(self) -> None:
        profile = self.profile()
        profile["capabilities"]["nss"] = {
            "supported": False,
            "config_fragment": None,
            "feed_pins": None,
            "pin_script": None,
            "required_config_symbols": [],
        }
        fields = VALIDATOR.validate(self.write_profile(profile))
        self.assertEqual(fields[7:12], ["0", "-", "-", "-", "-"])

    def test_enabled_nss_must_declare_required_config_symbols(self) -> None:
        profile = self.profile()
        profile["capabilities"]["nss"]["required_config_symbols"] = []
        with self.assertRaisesRegex(VALIDATOR.ProfileError, "must declare at least one"):
            VALIDATOR.validate(self.write_profile(profile))

    def test_nss_config_symbols_reject_shell_metacharacters(self) -> None:
        profile = self.profile()
        profile["capabilities"]["nss"]["required_config_symbols"][0] = "CONFIG_BAD=y;touch /tmp/pwned"
        with self.assertRaisesRegex(VALIDATOR.ProfileError, "invalid value"):
            VALIDATOR.validate(self.write_profile(profile))

    def test_duplicate_nss_config_symbols_are_rejected(self) -> None:
        profile = self.profile()
        profile["capabilities"]["nss"]["required_config_symbols"].append(
            profile["capabilities"]["nss"]["required_config_symbols"][0]
        )
        with self.assertRaisesRegex(VALIDATOR.ProfileError, "contains duplicates"):
            VALIDATOR.validate(self.write_profile(profile))

    def test_nss_capability_requires_a_boolean(self) -> None:
        profile = self.profile()
        profile["capabilities"]["nss"]["supported"] = "true"
        with self.assertRaisesRegex(VALIDATOR.ProfileError, "must be boolean"):
            VALIDATOR.validate(self.write_profile(profile))

    def test_unknown_schema_fields_are_rejected(self) -> None:
        profile = self.profile()
        profile["platform"]["hardware_notes"] = "not yet supported"
        with self.assertRaisesRegex(VALIDATOR.ProfileError, "unexpected hardware_notes"):
            VALIDATOR.validate(self.write_profile(profile))

    def test_profiles_outside_the_repository_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="qg-profile-outside-") as outside:
            path = Path(outside) / "profile.json"
            path.write_text(PROFILE.read_text(encoding="utf-8"), encoding="utf-8")
            with self.assertRaisesRegex(VALIDATOR.ProfileError, "inside the repository"):
                VALIDATOR.validate(path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
