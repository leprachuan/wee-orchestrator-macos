# Wee Orchestrator for macOS v0.10.2

Released August 3, 2026.

## Fixed

- A new session shell did not consistently receive keyboard focus. It now
  claims focus when opened, so you can type immediately.
- Showing the chat, shell, and browser simultaneously could enter a SwiftUI
  split-view layout loop. The workspace now uses stable nested splits.
- Resizing a browser or shell pane now updates the page viewport/resize event
  and PTY dimensions, allowing responsive pages and terminal programs to adapt.

## Added

- The session chat list can be collapsed from the chat header; the choice is
  remembered between launches.
