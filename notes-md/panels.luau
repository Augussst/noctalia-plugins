--!nonstrict
-- Which panel entry shows the notes. "panel" closes on an outside click like any
-- shell panel; "pinned" is the same panel.luau declared persistent, so it stays
-- open while the user works in other windows. The choice lives in the shared
-- noctalia.state (entries share no Lua memory), so the bar widget, the launcher
-- and both panel copies agree on it.

local M = {}

M.NORMAL = "augussst/notes-md:panel"
M.PINNED = "augussst/notes-md:pinned"

function M.isPinned()
  return noctalia.state.get("panel_pinned") == true
end

function M.current()
  return M.isPinned() and M.PINNED or M.NORMAL
end

-- Shows the notes after the caller put a target in "open_note" / "open_home".
-- togglePanel would close a pinned panel that is already open, so an open
-- pinned panel is left to pick the target up through its state watch.
function M.show()
  if M.isPinned() then
    if noctalia.state.get("pinned_open") ~= true then
      noctalia.togglePanel(M.PINNED)
    end
  else
    noctalia.togglePanel(M.NORMAL)
  end
end

return M
