# Wee Orchestrator for macOS v0.10.5

Released August 5, 2026.

## Fixed

- Editing or creating a scheduled task against an older remote API could fail
  with `Unknown fields: permission_mode`. The app now retries that exact
  legacy-schema response without the unsupported field, while retaining the
  permission setting for current API versions.
