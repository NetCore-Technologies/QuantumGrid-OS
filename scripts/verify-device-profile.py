#!/usr/bin/env python3
"""Validate a QuantumGrid hardware profile before any firmware build work."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
TOKEN = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
PROFILE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
DISPLAY = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$")
BOARD_ID = re.compile(r"^[a-z0-9][a-z0-9,._-]{0,63}$")
RELATIVE_PATH = re.compile(r"^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$")
ARTIFACT_GLOB = re.compile(r"^[A-Za-z0-9_*?.-]{1,160}$")


class ProfileError(ValueError):
    """Raised when a device profile is unsafe or inconsistent."""


def require_object(value: Any, label: str, keys: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProfileError(f"{label} must be an object")
    actual = set(value)
    if actual != keys:
        missing = sorted(keys - actual)
        extra = sorted(actual - keys)
        details = []
        if missing:
            details.append("missing " + ", ".join(missing))
        if extra:
            details.append("unexpected " + ", ".join(extra))
        raise ProfileError(f"{label} has invalid keys ({'; '.join(details)})")
    return value


def require_string(value: Any, label: str, pattern: re.Pattern[str]) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise ProfileError(f"{label} has an invalid value")
    return value


def safe_repo_file(value: Any, label: str, *, must_exist: bool = True) -> str:
    relative = require_string(value, label, RELATIVE_PATH)
    candidate = (ROOT / relative).resolve()
    if not candidate.is_relative_to(ROOT):
        raise ProfileError(f"{label} escapes the repository")
    if must_exist and not candidate.is_file():
        raise ProfileError(f"{label} does not name an existing repository file: {relative}")
    return relative


def safe_repo_directory(value: Any, label: str) -> str:
    relative = require_string(value, label, RELATIVE_PATH)
    candidate = (ROOT / relative).resolve()
    if not candidate.is_relative_to(ROOT):
        raise ProfileError(f"{label} escapes the repository")
    return relative


def validate(profile_path: Path) -> list[str]:
    resolved_profile = profile_path.resolve()
    if not resolved_profile.is_relative_to(ROOT):
        raise ProfileError("profile path must be inside the repository")
    if not resolved_profile.is_file():
        raise ProfileError(f"profile file does not exist: {profile_path}")

    try:
        data = json.loads(resolved_profile.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ProfileError(f"cannot read profile JSON: {exc}") from exc

    root = require_object(data, "profile", {"schema_version", "platform", "capabilities", "artifacts"})
    if type(root["schema_version"]) is not int or root["schema_version"] != 1:
        raise ProfileError("schema_version must be integer 1")

    platform = require_object(
        root["platform"],
        "platform",
        {
            "id", "vendor", "model", "openwrt_device", "openwrt_target",
            "openwrt_subtarget", "config_file", "board_compatible",
        },
    )
    profile_id = require_string(platform["id"], "platform.id", PROFILE_ID)
    vendor = require_string(platform["vendor"], "platform.vendor", DISPLAY)
    model = require_string(platform["model"], "platform.model", DISPLAY)
    device = require_string(platform["openwrt_device"], "platform.openwrt_device", TOKEN)
    target = require_string(platform["openwrt_target"], "platform.openwrt_target", TOKEN)
    subtarget = require_string(platform["openwrt_subtarget"], "platform.openwrt_subtarget", TOKEN)
    config_file = safe_repo_file(platform["config_file"], "platform.config_file")

    board_ids = platform["board_compatible"]
    if not isinstance(board_ids, list) or not board_ids or len(board_ids) > 16:
        raise ProfileError("platform.board_compatible must contain 1 to 16 board IDs")
    validated_board_ids = [
        require_string(item, f"platform.board_compatible[{index}]", BOARD_ID)
        for index, item in enumerate(board_ids)
    ]
    if len(set(validated_board_ids)) != len(validated_board_ids):
        raise ProfileError("platform.board_compatible contains duplicate board IDs")

    capabilities = require_object(root["capabilities"], "capabilities", {"nss", "fxs"})
    nss = require_object(capabilities["nss"], "capabilities.nss", {"supported", "config_fragment", "feed_pins", "pin_script", "required_config_symbols"})
    fxs = require_object(capabilities["fxs"], "capabilities.fxs", {"supported", "setup_script"})

    if not isinstance(nss["supported"], bool):
        raise ProfileError("capabilities.nss.supported must be boolean")
    if not isinstance(fxs["supported"], bool):
        raise ProfileError("capabilities.fxs.supported must be boolean")

    nss_fragment = "-"
    nss_feed_pins = "-"
    nss_pin_script = "-"
    nss_required_config_symbols = "-"
    required_nss_symbols = nss["required_config_symbols"]
    if not isinstance(required_nss_symbols, list) or len(required_nss_symbols) > 64:
        raise ProfileError("capabilities.nss.required_config_symbols must be a list of at most 64 entries")
    validated_nss_symbols = [
        require_string(
            item,
            f"capabilities.nss.required_config_symbols[{index}]",
            re.compile(r"^CONFIG_[A-Za-z0-9_-]+=[A-Za-z0-9_.+-]+$"),
        )
        for index, item in enumerate(required_nss_symbols)
    ]
    if len(set(validated_nss_symbols)) != len(validated_nss_symbols):
        raise ProfileError("capabilities.nss.required_config_symbols contains duplicates")
    if nss["supported"]:
        if not validated_nss_symbols:
            raise ProfileError("a supported NSS capability must declare at least one required config symbol")
        nss_fragment = safe_repo_file(nss["config_fragment"], "capabilities.nss.config_fragment")
        nss_feed_pins = safe_repo_file(nss["feed_pins"], "capabilities.nss.feed_pins")
        nss_pin_script = safe_repo_file(nss["pin_script"], "capabilities.nss.pin_script")
        nss_required_config_symbols = ";".join(validated_nss_symbols)
    elif any(nss[field] is not None for field in ("config_fragment", "feed_pins", "pin_script")):
        raise ProfileError("unsupported NSS capability must not declare build inputs")
    elif validated_nss_symbols:
        raise ProfileError("unsupported NSS capability must not declare required config symbols")

    fxs_script = "-"
    if fxs["supported"]:
        fxs_script = safe_repo_file(fxs["setup_script"], "capabilities.fxs.setup_script")
    elif fxs["setup_script"] is not None:
        raise ProfileError("unsupported FXS capability must not declare a setup script")

    artifacts = require_object(
        root["artifacts"],
        "artifacts",
        {"output_directory", "factory_glob", "initramfs_glob", "sysupgrade_glob"},
    )
    output_directory = safe_repo_directory(artifacts["output_directory"], "artifacts.output_directory")
    factory_glob = require_string(artifacts["factory_glob"], "artifacts.factory_glob", ARTIFACT_GLOB)
    initramfs_glob = require_string(artifacts["initramfs_glob"], "artifacts.initramfs_glob", ARTIFACT_GLOB)
    sysupgrade_glob = require_string(artifacts["sysupgrade_glob"], "artifacts.sysupgrade_glob", ARTIFACT_GLOB)
    artifact_globs = (factory_glob, initramfs_glob, sysupgrade_glob)
    if any(device not in glob for glob in artifact_globs):
        raise ProfileError("all firmware artifact globs must include the OpenWrt device profile")
    if len(set(artifact_globs)) != len(artifact_globs):
        raise ProfileError("factory, initramfs and sysupgrade artifact globs must be distinct")

    config_text = (ROOT / config_file).read_text(encoding="utf-8")
    expected_config = (
        f"CONFIG_TARGET_{target}=y",
        f"CONFIG_TARGET_{target}_{subtarget}=y",
        f"CONFIG_TARGET_{target}_{subtarget}_DEVICE_{device}=y",
    )
    for setting in expected_config:
        if config_text.splitlines().count(setting) != 1:
            raise ProfileError(f"{config_file} must contain exactly one {setting!r}")

    return [
        profile_id,
        vendor,
        model,
        target,
        subtarget,
        device,
        config_file,
        "1" if nss["supported"] else "0",
        nss_fragment,
        nss_feed_pins,
        nss_pin_script,
        nss_required_config_symbols,
        "1" if fxs["supported"] else "0",
        fxs_script,
        output_directory,
        factory_glob,
        initramfs_glob,
        sysupgrade_glob,
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "profile",
        nargs="?",
        default=str(ROOT / "profiles" / "arcadyan-aw1000.json"),
        help="device profile JSON inside the repository",
    )
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--fields", action="store_true", help="print validated tab-separated build fields")
    output.add_argument("--lines", action="store_true", help="print one validated build field per line")
    output.add_argument("--check-only", action="store_true", help="validate without printing build fields")
    args = parser.parse_args()

    try:
        fields = validate(Path(args.profile))
    except ProfileError as exc:
        print(f"ERROR: device profile invalid: {exc}", file=sys.stderr)
        return 2

    if args.fields:
        print("\t".join(fields))
    elif args.lines:
        print("\n".join(fields))
    elif not args.check_only:
        print(
            "Valid device profile: "
            f"{fields[1]} {fields[2]} ({fields[3]}/{fields[4]}/{fields[5]})"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
