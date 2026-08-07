# Wee Orchestrator for macOS v0.10.8

Released August 7, 2026.

## Added

- Telegram Bot section on the agent card (#492): configure a per-agent
  Telegram bot token, start/restart its listener service, and view that
  listener's recent log output — the same controls the Webex Bot section
  already had, now available for both channels. Webex also gained a
  "View Logs" control alongside its existing token/restart controls.
- "Add to Reminders" on Kanban cards (#494): right-click a card for a
  context menu action that creates an Apple Reminder for it (title, notes,
  due date), using EventKit directly. Re-running it on the same card reports
  "Already in Reminders" instead of creating a duplicate.

## Changed

- The agent memories viewer is now editable (#461): the durable MEMORY.md
  and daily notes shown on the agent card can be edited and saved, not just
  viewed.

# Wee Orchestrator for macOS v0.10.7

Released August 6, 2026.

## Added

- In-app notification center (#60): a bell button in the header shows unread
  task-completion and kanban notifications, with per-item and mark-all-read
  controls.
- Per-session file browser (#62): browse an agent's working folder from a
  new Files panel, with breadcrumb navigation and inline preview for
  markdown, sandboxed HTML, and plain-text/source files.
- Agent memories viewer (#65): the agent config panel now lists and displays
  that agent's MEMORY.md and daily notes read-only.
- Text-size zoom controls for the embedded Wee browser (#64): −/percentage/+
  controls and ⌘-/⌘0/⌘+ shortcuts adjust page zoom, persisted per session.

## Changed

- Terminal and Browser toggle buttons moved from a floating overlay stack
  into the top-right action bar (#63), alongside the new Files toggle.
- The shell panel now accepts direct interactive keyboard input (#61):
  keystrokes are sent to the PTY as you type instead of being buffered in a
  separate command field, so prompts, menus, and full-screen terminal
  programs work correctly. ⌘V pastes directly to the shell; ⌘C and other
  system shortcuts still work normally.

## Fixed

- The chat panel now reliably auto-scrolls to new messages, with a "New
  messages" pill shown when you've scrolled up and new content arrives
  off-screen (#59).

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
