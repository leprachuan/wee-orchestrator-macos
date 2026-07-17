#!/usr/bin/env bash
# Package a binary-only macOS release archive.
# Usage: scripts/package-macos-release.sh 0.4.1 [app-path] [output-directory]

set -Eeuo pipefail

VERSION="${1:-}"
APP_PATH="${2:-build/Release/WeeOrchestrator.app}"
OUTPUT_DIR="${3:-dist}"
ARCHIVE_NAME="WeeOrchestrator-macOS-v${VERSION}.zip"
ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  die "Usage: $0 MAJOR.MINOR.PATCH [app-path] [output-directory]"
[[ -d "$APP_PATH" ]] || die "App bundle not found: $APP_PATH"
[[ -f "$APP_PATH/Contents/Info.plist" ]] || die "Not a macOS app bundle: $APP_PATH"

mkdir -p "$OUTPUT_DIR"
rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"

# Keep the app bundle as the only top-level archive item. `ditto` preserves
# macOS resource forks and extended attributes required by signed bundles.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

entry_count=0
while IFS= read -r entry; do
  entry_count=$((entry_count + 1))
  [[ "$entry" == "WeeOrchestrator.app/"* || "$entry" == "__MACOSX/"* ]] || \
    die "Unexpected release entry: $entry"
  case "$entry" in
    *.swift|*.m|*.mm|*.h|*.xcodeproj/*|*Tests/*|*/.git/*)
      die "Source code is not allowed in a macOS release: $entry"
      ;;
  esac
done < <(unzip -Z1 "$ARCHIVE_PATH")

(( entry_count > 0 )) || die "Release archive is empty"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$ARCHIVE_PATH" > "$CHECKSUM_PATH"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$ARCHIVE_PATH" > "$CHECKSUM_PATH"
else
  die "shasum or sha256sum is required to create a release checksum."
fi

printf 'Created binary-only release: %s\n' "$ARCHIVE_PATH"
printf 'Created checksum: %s\n' "$CHECKSUM_PATH"
