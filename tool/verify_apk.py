"""Fail when a distributed APK contains incompatible or incomplete native code."""

import sys
import zipfile
from pathlib import Path


def verify(path: Path) -> None:
    with zipfile.ZipFile(path) as apk:
        names = set(apk.namelist())
        abis = {
            name.split("/")[1]
            for name in names
            if name.startswith("lib/") and name.endswith(".so")
        }
        if abis != {"arm64-v8a"}:
            raise SystemExit(f"Unexpected native ABIs: {sorted(abis)}")
        for required in (
            "AndroidManifest.xml",
            "classes.dex",
            "lib/arm64-v8a/libflutter.so",
        ):
            if required not in names:
                raise SystemExit(f"Missing APK entry: {required}")
    print(f"Verified arm64-only Flutter APK: {path.name}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 tool/verify_apk.py <apk>")
    verify(Path(sys.argv[1]))
