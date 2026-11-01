--!nonstrict
-- Bar widget that opens the hub.

local items = require("./items.luau")

local function render()
  barWidget.setGlyph(noctalia.getConfig("glyph"))
  barWidget.setTooltip(noctalia.tr("title"))
end

function update()
  render()
end

function onClick()
  noctalia.togglePanel(items.panelId())
end

render()
