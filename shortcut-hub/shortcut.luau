--!nonstrict
-- Control-center tile that opens the hub, so one of the control center's
-- slots can hold every other shortcut.

local items = require("./items.luau")

shortcut.setLabel(noctalia.tr("shortcut.label"))
shortcut.setIcon("layout-grid")
shortcut.setActive(false)

function onClick()
  noctalia.togglePanel(items.panelId())
end
