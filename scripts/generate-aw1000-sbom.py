#!/usr/bin/env python3
"""Generate a CycloneDX SBOM for the AW1000 firmware release.

The installed package inventory is sourced from the exact OpenWrt image manifest.
Release artifacts are hashed independently and recorded as CycloneDX components.
This generator intentionally uses only the Python standard library.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
import uuid
from pathlib import Path
from urllib.parse import quote


PACKAGE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+_.-]{0,127}$")
PACKAGE_VERSION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+_.:~%-]{0,255}$")
MAX_PACKAGES = 8192
COMMIT = re.compile(r"^[0-9a-f]{40}$")


class SbomError(ValueError):
    """Raised when source inventory or release metadata is unsafe."""


def parse_manifest(path: Path) -> list[tuple[str, str]]:
    if path.is_symlink() or not path.is_file():
        raise SbomError("The image package manifest must be a regular, non-symlink file.")
    raw = path.read_bytes()
    if not raw or len(raw) > 4 * 1024 * 1024:
        raise SbomError("The image package manifest is empty or exceeds 4 MiB.")
    try:
        content = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise SbomError("The image package manifest is not valid UTF-8.") from exc

    packages: dict[str, str] = {}
    for line_number, raw_line in enumerate(content.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 3 or fields[1] != "-":
            raise SbomError(
                f"Unrecognised package manifest row at line {line_number}; expected 'name - version'."
            )
        name, _, version = fields
        if not PACKAGE_NAME.fullmatch(name) or not PACKAGE_VERSION.fullmatch(version):
            raise SbomError(f"Unsafe package name or version at manifest line {line_number}.")
        if len(packages) >= MAX_PACKAGES:
            raise SbomError("The image package manifest exceeds the 8,192-component SBOM safety limit.")
        previous = packages.get(name)
        if previous is not None:
            if previous != version:
                raise SbomError(f"Package {name!r} appears with conflicting versions.")
            raise SbomError(f"Package {name!r} appears more than once.")
        packages[name] = version

    if not packages:
        raise SbomError("The image package manifest contains no installed packages.")
    return sorted(packages.items(), key=lambda item: item[0])


def sha256_file(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise SbomError(f"Release artifact {path} must be a regular, non-symlink file.")
    if path.stat().st_size <= 0:
        raise SbomError(f"Release artifact {path} is empty.")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--firmware-image", required=True, type=Path)
    parser.add_argument("--packages-archive", required=True, type=Path)
    parser.add_argument("--feeds-report", required=True, type=Path)
    parser.add_argument("--phone-source-archive", required=True, type=Path)
    parser.add_argument("--build-info", required=True, type=Path)
    parser.add_argument("--build-config", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--build-profile", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--openwrt-commit", required=True)
    return parser.parse_args()


def build_sbom(args: argparse.Namespace) -> dict:
    if not args.version or len(args.version) > 128 or any(ord(ch) < 32 for ch in args.version):
        raise SbomError("Release version is missing or malformed.")
    if not args.target or len(args.target) > 128 or any(ord(ch) < 32 for ch in args.target):
        raise SbomError("OpenWrt target is missing or malformed.")
    if args.profile != "arcadyan_aw1000":
        raise SbomError("This SBOM generator only accepts the validated Arcadyan AW1000 profile.")
    if not COMMIT.fullmatch(args.source_commit) or not COMMIT.fullmatch(args.openwrt_commit):
        raise SbomError("Source and OpenWrt commit identifiers must be full 40-character Git SHAs.")
    if args.build_profile not in {"AW1000 stable upstream OpenWrt", "AW1000 experimental NSS"}:
        raise SbomError("Build profile is not an admitted AW1000 release profile.")

    packages = parse_manifest(args.manifest)
    firmware_sha = sha256_file(args.firmware_image)
    package_archive_sha = sha256_file(args.packages_archive)
    manifest_sha = sha256_file(args.manifest)
    feeds_report_sha = sha256_file(args.feeds_report)
    phone_source_sha = sha256_file(args.phone_source_archive)
    build_info_sha = sha256_file(args.build_info)
    build_config_sha = sha256_file(args.build_config)
    root_ref = (
        "pkg:generic/quantumgrid-os@"
        + quote(args.version, safe="._-")
        + "?profile=arcadyan_aw1000&target="
        + quote(args.target, safe="")
    )
    package_components = []
    package_refs = []
    for name, version in packages:
        purl = f"pkg:generic/{quote(name, safe='._-')}@{quote(version, safe='._-')}"
        package_refs.append(purl)
        package_components.append({
            "type": "library",
            "bom-ref": purl,
            "name": name,
            "version": version,
            "purl": purl,
            "properties": [
                {"name": "quantumgrid:inventory-source", "value": "OpenWrt AW1000 image package manifest"},
                {"name": "quantumgrid:package-manager", "value": "OpenWrt"},
            ],
        })

    firmware_ref = f"urn:quantumgrid:firmware:aw1000:{args.version}"
    packages_ref = f"urn:quantumgrid:packages:aw1000:{args.version}"
    components = package_components + [
        {
            "type": "firmware",
            "bom-ref": firmware_ref,
            "name": "QuantumGrid OS AW1000 squashfs factory UBI image",
            "version": args.version,
            "hashes": [{"alg": "SHA-256", "content": firmware_sha}],
        },
        {
            "type": "file",
            "bom-ref": packages_ref,
            "name": "QuantumGrid OS AW1000 APK/IPK package archive",
            "version": args.version,
            "hashes": [{"alg": "SHA-256", "content": package_archive_sha}],
        },
    ]
    evidence_files = [
        ("package-manifest", args.manifest, manifest_sha, "Exact installed OpenWrt package manifest used for the component inventory"),
        ("openwrt-feed-report", args.feeds_report, feeds_report_sha, "Resolved OpenWrt package feed revisions"),
        ("phone-source-archive", args.phone_source_archive, phone_source_sha, "Pinned AW1000 phone source archive"),
        ("build-info", args.build_info, build_info_sha, "Resolved source commits and build provenance metadata"),
        ("build-config", args.build_config, build_config_sha, "Exact QuantumGrid AW1000 firmware build configuration"),
    ]
    for artifact_id, path, digest, role in evidence_files:
        components.append({
            "type": "file",
            "bom-ref": f"urn:quantumgrid:artifact:aw1000:{args.version}:{artifact_id}",
            "name": path.name,
            "version": args.version,
            "hashes": [{"alg": "SHA-256", "content": digest}],
            "properties": [
                {"name": "quantumgrid:artifact-role", "value": role},
            ],
        })
    timestamp = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": "urn:uuid:" + str(uuid.uuid4()),
        "version": 1,
        "metadata": {
            "timestamp": timestamp,
            "tools": {
                "components": [{
                    "type": "application",
                    "name": "QuantumGrid AW1000 SBOM Generator",
                    "version": "1.0.0",
                }]
            },
            "component": {
                "type": "operating-system",
                "bom-ref": root_ref,
                "name": "QuantumGrid OS",
                "version": args.version,
                "purl": root_ref,
                "properties": [
                    {"name": "quantumgrid:device", "value": "Arcadyan AW1000"},
                    {"name": "quantumgrid:target", "value": args.target},
                    {"name": "quantumgrid:profile", "value": args.profile},
                    {"name": "quantumgrid:build-profile", "value": args.build_profile},
                    {"name": "quantumgrid:source-commit", "value": args.source_commit},
                    {"name": "quantumgrid:openwrt-commit", "value": args.openwrt_commit},
                    {"name": "quantumgrid:package-count", "value": str(len(packages))},
                    {"name": "quantumgrid:firmware-image-sha256", "value": firmware_sha},
                    {"name": "quantumgrid:package-archive-sha256", "value": package_archive_sha},
                    {"name": "quantumgrid:package-manifest-sha256", "value": manifest_sha},
                    {"name": "quantumgrid:openwrt-feed-report-sha256", "value": feeds_report_sha},
                    {"name": "quantumgrid:phone-source-archive-sha256", "value": phone_source_sha},
                    {"name": "quantumgrid:buildinfo-sha256", "value": build_info_sha},
                    {"name": "quantumgrid:build-config-sha256", "value": build_config_sha},
                    {"name": "quantumgrid:inventory-source", "value": args.manifest.name},
                    {"name": "quantumgrid:inventory-method", "value": "Installed package names and versions only; licenses and transitive dependency metadata are not inferred from the image manifest."},
                ],
            },
        },
        "components": components,
        "dependencies": [{
            "ref": root_ref,
            "dependsOn": package_refs,
        }],
    }


def main() -> int:
    args = parse_args()
    try:
        sbom = build_sbom(args)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8", newline="\n") as handle:
            json.dump(sbom, handle, indent=2, sort_keys=True)
            handle.write("\n")
        print(
            f"Generated CycloneDX 1.6 SBOM with {len(sbom['dependencies'][0]['dependsOn'])} "
            f"installed packages: {args.output}"
        )
        return 0
    except (OSError, SbomError) as exc:
        print(f"SBOM generation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
