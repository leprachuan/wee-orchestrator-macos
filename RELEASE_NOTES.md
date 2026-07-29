# Wee Orchestrator for macOS v0.9.3

Released July 29, 2026.

## Fixed

- After the "didn't quit to finish installing" dialog appeared, clicking
  "Update and Restart" did nothing. It now forces the update through instead
  of repeating the same failed quit.
- Periodic stalls, especially when starting a new chat thread, caused by chat
  responses holding a connection open for minutes at a time and crowding out
  the connections that starting a new thread needs. Chat streaming, file
  uploads, transcription, and text-to-speech now use their own separate pool
  of connections.
