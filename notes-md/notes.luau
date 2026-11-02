--!nonstrict
-- Bar widget that opens the notes panel.

local panels = require("./panels.luau")

local glyph = noctalia.getConfig("glyph")

local function render()
  barWidget.setGlyph(glyph)
  barWidget.setTooltip(noctalia.tr("title"))
end

function update()
  render()
end

function onClick()
  noctalia.togglePanel(panels.current())
end

render()
