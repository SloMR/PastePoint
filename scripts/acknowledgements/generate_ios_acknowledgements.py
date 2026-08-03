#!/usr/bin/env python3
"""Generates the iOS Settings.bundle acknowledgements pane from the pinned SPM checkouts.

    python3 scripts/acknowledgements/generate_ios_acknowledgements.py           # write
    python3 scripts/acknowledgements/generate_ios_acknowledgements.py --check   # check

Packages are discovered from Package.resolved and their license files found by
name inside each checkout, so adding a dependency needs no edit here.

--check needs no checkouts: it compares Package.resolved against the section
titles already in Acknowledgements.plist, so CI catches a dependency nobody attributed.
"""

import argparse
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "client/ios"
SWIFTPM = "PastePoint.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
RESOLVED = IOS / SWIFTPM / "Package.resolved"
OUTPUT = IOS / "PastePoint/Resources/Settings.bundle/Acknowledgements.plist"

# LICENSE, LICENSE.md, LICENCE.txt, LICENSE-MIT, COPYING, NOTICE.txt.
LICENSE_FILE = re.compile(r"^(LICEN[CS]E|COPYING|NOTICE)([-._].*)?$", re.IGNORECASE)


def pins() -> dict[str, str]:
    """identity -> version, in Package.resolved order."""
    data = json.loads(RESOLVED.read_text(encoding="utf-8"))
    return {p["identity"]: p["state"]["version"] for p in data["pins"]}


def find_checkouts() -> Path:
    """Newest DerivedData checkouts directory, since a project can have several."""
    derived = Path.home() / "Library/Developer/Xcode/DerivedData"
    candidates = sorted(derived.glob("PastePoint-*/SourcePackages/checkouts"))
    if not candidates:
        sys.exit("No SPM checkouts found. Build the app in Xcode first.")
    return candidates[-1]


def checkout_for(checkouts: Path, identity: str) -> Path:
    """Checkout folders use the repo name, which differs in case from the identity."""
    for child in sorted(checkouts.iterdir()):
        if child.is_dir() and child.name.lower() == identity.lower():
            return child
    sys.exit(f"No checkout for '{identity}' under {checkouts}")


def license_text(package: Path) -> str:
    """Every LICENSE/NOTICE file the package ships, concatenated."""
    entries = (f for f in package.iterdir() if f.is_file())
    files = sorted(f for f in entries if LICENSE_FILE.match(f.name))
    if not files:
        sys.exit(f"'{package.name}' ships no LICENSE or NOTICE file")

    return "\n\n".join(f.read_text(encoding="utf-8").strip() for f in files).strip()


def generate(checkouts: Path) -> bytes:
    """Serialized pane: a lead-in section, then one titled section per package."""
    specifiers = [
        {
            "Type": "PSGroupSpecifier",
            "Title": "THIRD_PARTY_SOFTWARE",
            "FooterText": "THIRD_PARTY_FOOTER",
        }
    ]

    for identity, version in pins().items():
        package = checkout_for(checkouts, identity)
        specifiers.append(
            {
                "Type": "PSGroupSpecifier",
                "Title": f"{package.name} {version}",
                "FooterText": license_text(package),
            }
        )

    pane = {"StringsTable": "Root", "PreferenceSpecifiers": specifiers}
    return plistlib.dumps(pane, sort_keys=False)


def check() -> None:
    """Exits non-zero when a pinned package has no section in the committed pane."""
    with OUTPUT.open("rb") as f:
        specifiers = plistlib.load(f)["PreferenceSpecifiers"]
    titles = {s.get("Title", "").lower() for s in specifiers}

    wanted = (f"{identity} {version}" for identity, version in pins().items())
    missing = [w for w in wanted if w.lower() not in titles]

    if missing:
        print("Acknowledgements.plist is out of date. Regenerate it with:")
        print("  python3 scripts/acknowledgements/generate_ios_acknowledgements.py")
        for entry in missing:
            print(f"  missing: {entry}")
        sys.exit(1)

    print(f"Acknowledgements.plist covers all {len(pins())} pinned packages")


def main() -> None:
    """Writes the pane, or verifies it when passed --check."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.check:
        check()
        return

    generated = generate(find_checkouts())
    if OUTPUT.exists() and OUTPUT.read_bytes() == generated:
        print("Acknowledgements.plist already up to date")
        return

    OUTPUT.write_bytes(generated)
    print(f"wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
