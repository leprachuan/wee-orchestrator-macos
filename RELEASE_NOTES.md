# Wee Orchestrator for macOS v0.10.1

Released August 2, 2026.

## Fixed

- The Local API stayed down after it stopped unexpectedly. Nothing restarted
  it — the auto-start setting only applies when Wee launches — so a crash left
  the Local environment unusable until you noticed and started it by hand. Wee
  now brings it back on its own, retrying up to three times with a growing
  delay, and tells you the exit code while it does. If it still won't stay up,
  Wee stops retrying and says so rather than looping.
- When the Local API is not running, chats showed only "Could not connect to
  the server", which didn't say what was wrong or what to do. The message now
  names the Local API, the address that refused, and where to start it. Chats
  against the Remote backend are unaffected — the same failure there means
  something else.
