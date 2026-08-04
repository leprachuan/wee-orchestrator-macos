# Wee Orchestrator for macOS v0.10.3

Released August 4, 2026.

## Fixed

- Chat messages with a relative `/ai-media/<session>/<file>` image (Wee's
  documented media route) showed a failed-image chip even when the server
  returned the image successfully, because the native app never resolved
  that path against the active environment's address. It now resolves
  correctly for both local and remote environments. Codex inline
  visualization directives (`::codex-inline-vis{...}`) no longer render as
  literal text; they show a labeled placeholder instead.
- A shell panel created by sending the first message in a brand-new chat
  could fail to take keyboard focus, since a single focus-reclaim attempt on
  appear could lose the race to the browser's web view. Focus is now
  reclaimed across several run-loop turns. A duplicated divider line and a
  floating panel-toggle button that could sit on top of the shell/browser's
  own navigation controls have also been fixed.
- The window's minimum width was fixed regardless of how many chat-section
  panels (session list, shell, browser) were open, so opening several at once
  could force those panels to compress below their own minimum widths. The
  window now grows its minimum width to fit whichever panels are visible.
- Switching chat sessions could interrupt an in-flight remote browser-control
  command (used by the iOS app) before its result reached the server, which
  showed up as the same command being reported canceled more than once. A
  dequeued command now always finishes and reports its result even if the
  session is switched mid-command.

## Added

- The chat session list can now collapse to a narrow icon rail instead of
  only being shown or fully hidden.
