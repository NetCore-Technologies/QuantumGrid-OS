#!/usr/bin/env python3
"""Validate QuantumGrid's static Pages site using only Python's standard library."""
from __future__ import annotations

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "website"
PAGES = (
    "index.html",
    "features.html",
    "hardware.html",
    "downloads.html",
    "docs.html",
    "roadmap.html",
    "community.html",
)


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.references: list[str] = []
        self.ids: set[str] = set()
        self.duplicates: list[str] = []
        self.nav_count = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "nav":
            self.nav_count += 1
        for attribute in ("href", "src"):
            value = values.get(attribute)
            if value:
                self.references.append(value)
        element_id = values.get("id")
        if element_id:
            if element_id in self.ids:
                self.duplicates.append(element_id)
            self.ids.add(element_id)


def main() -> int:
    errors: list[str] = []
    for name in PAGES:
        path = SITE / name
        if not path.is_file():
            errors.append(f"missing page: {name}")
            continue

        source = path.read_text(encoding="utf-8")
        parser = PageParser()
        parser.feed(source)
        parser.close()

        if parser.nav_count != 2:
            errors.append(f"{name}: expected header and footer navigation landmarks, found {parser.nav_count}")
        if parser.duplicates:
            errors.append(f"{name}: duplicate IDs: {', '.join(parser.duplicates)}")
        if "<title>" not in source or 'name="description"' not in source:
            errors.append(f"{name}: missing title or description metadata")

        for reference in parser.references:
            parsed = urlparse(reference)
            if parsed.scheme or reference.startswith(("#", "mailto:", "tel:", "data:")):
                continue
            if reference.startswith("//"):
                continue
            target = (path.parent / parsed.path).resolve()
            try:
                target.relative_to(SITE.resolve())
            except ValueError:
                errors.append(f"{name}: local link escapes website directory: {reference}")
                continue
            if not target.exists():
                errors.append(f"{name}: broken local reference: {reference}")

    for name in ("styles.css", "site.js", "assets/quantumgrid.svg", "robots.txt", "sitemap.xml"):
        if not (SITE / name).is_file():
            errors.append(f"missing site asset: {name}")

    sitemap = SITE / "sitemap.xml"
    if sitemap.is_file():
        try:
            ET.parse(sitemap)
        except ET.ParseError as exc:
            errors.append(f"invalid sitemap.xml: {exc}")

    if errors:
        print("Website validation failed:")
        for error in errors:
            print(f" - {error}")
        return 1

    print(f"Website validation passed: {len(PAGES)} pages and shared assets checked.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
