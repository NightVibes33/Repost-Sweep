#!/usr/bin/env python3
"""The app icon is committed artwork. This script must not replace it."""

import sys


def main():
    sys.stderr.write(
        "AppIcon.appiconset is the committed icon. "
        "scripts/render-icon.py does not draw or overwrite it.\n"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
