# Wee Orchestrator for macOS v0.9.4

Released July 29, 2026.

## Fixed

- The Kanban board reported "Internal server error" against the Local API. The
  local service could not find the `gh` command when Wee was launched from
  Finder, because apps started that way get a much shorter search path than a
  Terminal window does. The local service is now given the full path, which
  also fixes any other developer tool it needs to run.
- The app got slower the longer it stayed open, and only relaunching cleared
  it. Every chat thread you opened left behind a hidden browser view that was
  never released, so they piled up all day along with their supporting system
  processes. Only the few most recent are kept now.
