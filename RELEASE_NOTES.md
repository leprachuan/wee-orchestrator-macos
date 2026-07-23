# Wee Orchestrator for macOS v0.7.0

Released July 23, 2026.

- Archive and rename chats from Recent Chats, with agent-specific colors for quick scanning.
- Make completed chat switching immediate with a local LRU transcript cache and idle prefetching.
- Keep background history refreshes and session metadata out of the interaction path.
- Prevent stale network responses from replacing a newly selected conversation.
- Limit history reads to an 8-second timeout so an unavailable API never leaves chat navigation blocked.
- Stabilize the shared Xcode project scheme and register chat-organization tests.
