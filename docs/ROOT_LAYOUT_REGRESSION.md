# Root layout regression — issue535

1. Launch the private app at a large window size (tested3420×2034 backing pixels).
2. Open Agents and refresh until local/remote agents load.
3. Verify the Agents header starts immediately beneath the window title area, the navigation rail starts at the top, and all14 agent cards are accessible by normal scrolling.
4. Open an agent's Always-On panel, close it, and verify the root layout remains at the top.

Failure reproduced in0.13.1: the empty top safe-area inset reserved roughly half the window. Removing that obsolete container in0.13.2 restores the header and rail to the top. Installed build37 verified with7 local and7 remote agents; full-window screenshot retained in the private build artifacts as agents-layout-fixed.png.
