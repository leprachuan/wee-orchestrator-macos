# Wee Orchestrator for macOS v0.8.0

Released July 24, 2026.

## New

- Chats are now organized into a collapsible folder per agent in the chat
  sidebar, instead of one flat recent list. Folders follow your configured
  agent order, with anything untagged collected under "Unassigned". The folder
  holding the open conversation expands automatically, and each folder shows
  its five most recent chats with a show-more toggle.

## Improved

- The Background Tasks tab now leads with the task list, so previous and
  running work is visible first; the "new task" form sits below it.
- Task logs still open on a fast bounded tail, but the complete output is now
  reachable with "Show full log" — previously anything beyond the most recent
  100 lines could not be seen.
- The Appearance text-size setting now scales the entire client. 122 remaining
  text styles across Kanban, Tasks, Local Models, Agents and Chat previously
  ignored it.

## Fixed

- Models configured for the Copilot and copilot-sdk runtimes in Local Settings
  now appear in the model picker even when the local API does not report them.
- Newly pulled Ollama models reliably reach the chat model picker without a
  manual refresh or restart.
- An in-progress app update can no longer stall at "Installing…" when a window
  or sheet delays termination.
