#!/usr/bin/env bash
# Publish the same macOS release assets to both repositories.
# The installed app checks the core Wee-Orchestrator repository for updates,
# while this repository is the macOS source of truth. Keeping both releases in
# sync is therefore required for in-app updates to work.
#
# Usage: scripts/publish-macos-release.sh MAJOR.MINOR.PATCH ARCHIVE CHECKSUM NOTES_FILE

set -Eeuo pipefail

VERSION="${1:-}"
ARCHIVE_PATH="${2:-}"
CHECKSUM_PATH="${3:-}"
NOTES_PATH="${4:-}"

MACOS_REPOSITORY="${MACOS_RELEASE_REPOSITORY:-leprachuan/wee-orchestrator-macos}"
CORE_REPOSITORY="${CORE_RELEASE_REPOSITORY:-leprachuan/Wee-Orchestrator}"
# GitHub accepts a remote branch or commit SHA as a release target, but not
# the literal string "HEAD".  Default to the currently checked-out branch so
# publishing from a feature/release branch works without an override.
MACOS_TARGET="${MACOS_RELEASE_TARGET:-$(git branch --show-current)}"
CORE_TARGET="${CORE_RELEASE_TARGET:-main}"
TAG="macos-v${VERSION}"
TITLE="Wee Orchestrator for macOS v${VERSION}"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  die "Usage: $0 MAJOR.MINOR.PATCH ARCHIVE CHECKSUM NOTES_FILE"
[[ -f "$ARCHIVE_PATH" ]] || die "Release archive not found: $ARCHIVE_PATH"
[[ -f "$CHECKSUM_PATH" ]] || die "Release checksum not found: $CHECKSUM_PATH"
[[ -f "$NOTES_PATH" ]] || die "Release notes not found: $NOTES_PATH"
command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required."

publish_release() {
  local repository="$1"
  local target="$2"

  if gh release view "$TAG" --repo "$repository" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ARCHIVE_PATH" "$CHECKSUM_PATH" --clobber --repo "$repository"
    gh release edit "$TAG" --repo "$repository" --title "$TITLE" --notes-file "$NOTES_PATH"
  else
    gh release create "$TAG" "$ARCHIVE_PATH" "$CHECKSUM_PATH" \
      --repo "$repository" \
      --target "$target" \
      --title "$TITLE" \
      --notes-file "$NOTES_PATH"
  fi
}

publish_release "$MACOS_REPOSITORY" "$MACOS_TARGET"
publish_release "$CORE_REPOSITORY" "$CORE_TARGET"

printf 'Published %s to %s and %s\n' "$TAG" "$MACOS_REPOSITORY" "$CORE_REPOSITORY"
