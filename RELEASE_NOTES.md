# Wee Orchestrator for macOS v0.9.1

Released July 27, 2026.

## Fixed

- Switching between chats, and creating a new chat, could stall for 25–45
  seconds. Each chat you visited left a background browser connection open, and
  after six of them the app ran out of connections and every new request had to
  wait for one to free up. Only the chat you are looking at keeps a connection
  now, and those connections are kept separate from the ones chat, history, and
  new sessions use.
- An app update that asked the app to quit but never got a response could sit on
  "Installing…" indefinitely, with no error and no way to retry. It now recovers
  on its own after about ten seconds and tells you how to finish the update.
