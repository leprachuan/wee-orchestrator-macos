# Wee Orchestrator for macOS v0.10.6

Released August 5, 2026.

## Added

- Per-agent Webex bot configuration (#491): the agent card now has a Webex
  Bot section to set/clear that agent's own bot token and to start or
  restart its Webex connector service, showing whether a token is
  configured and whether the service is currently running.

# Wee Orchestrator for macOS v0.10.5

Released August 5, 2026.

## Fixed

- Editing or creating a scheduled task against an older remote API could fail
  with `Unknown fields: permission_mode`. The app now retries that exact
  legacy-schema response without the unsupported field, while retaining the
  permission setting for current API versions.
