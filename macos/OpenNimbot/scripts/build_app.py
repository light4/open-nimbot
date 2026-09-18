#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""Build a signed OpenNimbot.app bundle from the Swift package."""

import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "dist" / "OpenNimbot.app"
CONTENTS = APP / "Contents"


def main() -> None:
    subprocess.run(["swift", "build", "-c", "release"], cwd=ROOT, check=True, timeout=300)
    shutil.rmtree(APP, ignore_errors=True)
    macos = CONTENTS / "MacOS"
    macos.mkdir(parents=True)
    shutil.copy2(ROOT / ".build" / "release" / "OpenNimbot", macos / "OpenNimbot")
    with (CONTENTS / "Info.plist").open("wb") as file:
        plistlib.dump(
            {
                "CFBundleExecutable": "OpenNimbot",
                "CFBundleIdentifier": "com.light4.OpenNimbot",
                "CFBundleName": "OpenNimbot",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "LSMinimumSystemVersion": "15.0",
                "NSBluetoothAlwaysUsageDescription": "OpenNimbot uses Bluetooth to find and print to your label printer.",
                "NSHighResolutionCapable": True,
            },
            file,
        )
    subprocess.run(["codesign", "--force", "--sign", "-", APP], check=True, timeout=60)
    print(APP)


if __name__ == "__main__":
    main()
