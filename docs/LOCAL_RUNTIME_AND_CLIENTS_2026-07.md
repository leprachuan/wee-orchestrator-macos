# Wee Orchestrator for macOS — July 2026 Update

## Workspace and task workflow

- Refreshed the compact dark workspace with the existing Wee icon and the
  green, black, and dark-purple visual system. Views prioritize dense,
  readable, high-contrast information rather than unused space.
- Background Tasks and Scheduled Tasks are separate sidebar destinations.
  Both have a Local/Remote selector so listing, creation, editing, execution,
  and history operate against the selected API.
- Scheduled task editing includes creation, updates, and execution history.
- Kanban task editing uses a larger modal, supports labels, and supports
  type-ahead selection or creation of labels.

## Chat and accessibility

- Recent sessions remain visible immediately, including the active session
  when a history refresh is delayed or unavailable.
- Chat supports speech-to-text input and text-to-speech playback where the
  local platform services are available.
- Wee tool activity is shown during streaming. Completed `search` tool events
  now display their returned sources while the final response is prepared.
- Native macOS multi-window behavior is enabled: use **File → New Window** to
  open another Wee workspace window. **New Chat** remains available separately.

## Local and remote operation

- Local and Remote agents are clearly separated. Local API agents use an
  isolated configuration file and no longer duplicate the remote agent list.
- Local Settings includes safe controls to clone or pull the API source,
  bootstrap Python dependencies, start/stop/restart the local API, and manage
  the local/remote connection independently.
- The local service is stopped when the app quits, avoiding orphan API
  processes on the local port.

## Local models and Wee runtime

- Each app launch installs or repairs `~/.local/bin/wee` and adds that
  directory to the user's zsh/bash login PATH. The app clones or fast-forwards
  a dedicated runtime under `~/Library/Application Support/WeeOrchestrator/CLI`,
  refreshes its isolated Python environment when the runtime commit changes,
  and makes the launcher prefer that managed copy. Developer checkouts and
  their uncommitted work are never modified just to update the shell command.
- A Local Models destination manages Ollama installation, startup, downloads,
  deletion, and selected on-device models.
- Recommendations are memory-aware and restrict the curated choices to models
  with at least a 64K context window. Registry search/custom tags require a
  declared long-context capability.
- Downloaded Ollama models are exposed in the `wee` runtime model list and
  refresh after downloads, deletion, and runner startup.
- Local Settings accepts an OpenRouter API key for the local Wee runtime. It is
  stored in macOS Keychain and injected only into the child API process on
  restart; it is never saved in UserDefaults or source files.

## Security and release behavior

- Local API authentication is provisioned as a private shared key, with the
  client token held in Keychain.
- The app does not include API tokens, OpenRouter keys, Telegram/Webex bot
  tokens, or local shared-key values in source or release configuration.
- A source and built-app audit accompanies this release; see the API release
  notes for the associated runtime contract.
