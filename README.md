
Always-On approval support (development): an app-wide Approvals button and a Settings entry connect to the shared `/api/v1/autonomy` service. Online authorized macOS/iOS/WebUI clients see the same durable requests and winning decisions. Permanent grants show their exact scope before saving; saved rules can be edited or revoked. Requires the matching API feature release. Offline catch-up uses authoritative state; opt-in iOS push requires the matching API and configured APNs credentials.

The initial worker observes API agent/task counts and drafts reports in isolated workspaces. Persistent responsibilities start paused and offer resume, pause, cancel, goal revision and interrupted-work reconciliation. Routine model settings include provider-qualified inexpensive models, request/token caps and a permitted escalation list; escalation requires two failed checks and shared approval. General shell/browser/delegation and external host tools are unavailable. This branch prepares macOS 0.13.0 build 35 for the matching Wee API 1.6.0 release; it is not installed or published by development builds.

Always-On configuration is under Agents → an agent’s Always-On button (also available in its editor). Responsibilities, runtime/model selection, budgets, approvals and action rules are agent-scoped and shared with authorized clients connected to the same API.

## Repository-backed Always-On goals

Agent Always-On panels configure work repositories and per-agent defaults, request issue creation/linking through shared approvals, migrate unlinked goals, show issue checklists and sync state, and request completion for finite goals. Recurring goals remain open after a report. Use the dev API to validate issue-538 changes; the server needs GitHub issue access through its existing CLI login or an environment credential.


Adaptive Always-On (#542): the agent chooses a persisted next heartbeat from 5 minutes to 4 hours, reviewing all active goals. Each goal has plain-text “Allowed autonomously” and “Ask permission first” editors; saving pauses the goal. Issue mirrors use the existing shared approval boundary. A global request badge remains visible outside agent settings and opens approvals and steering for every agent. Responses use origin identity and exact request revision; remote decisions remain queued until the origin reconnects. Native clients require the matching API #542 release.
The app subscribes to both configured local and remote APIs and publishes local requests to the remote hub while running. A headless local service can use WEE_ALWAYS_ON_HUB_URL and WEE_ALWAYS_ON_HUB_TOKEN instead. No token is added to repository files.

Validate inbox/relay/legacy JSON models without launching the app: `python3 scripts/check-always-on-contract.py`.
