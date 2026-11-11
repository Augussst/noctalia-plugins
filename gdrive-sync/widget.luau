--!nonstrict
-- Bar icon: sync state at a glance. Click opens the panel.
--   cloud-check  everything synced      refresh  a sync is running
--   cloud-x      a folder failed        cloud    nothing synced yet

local core = require("./core.luau")

local function render()
  local folders = core.folders()
  local status = core.status()
  local state, detail = core.summary(folders, status)

  barWidget.setText("")
  if state == "running" then
    barWidget.setGlyph("refresh")
    barWidget.setGlyphColor("primary")
    barWidget.setTooltip(noctalia.tr("widget.running", { name = core.basename(detail) }))
  elseif state == "error" then
    local s = status.folders[detail["local"]] or {}
    barWidget.setGlyph("cloud-x")
    barWidget.setGlyphColor("error")
    barWidget.setTooltip(noctalia.tr("widget.error", { name = core.basename(detail["local"]), msg = tostring(s.msg or "") }))
  elseif state == "ok" then
    barWidget.setGlyph("cloud-check")
    barWidget.setGlyphColor("on_surface")
    barWidget.setTooltip(noctalia.tr("widget.ok", { n = #folders, ago = core.ago(status.last_run) }))
  else
    barWidget.setGlyph("cloud")
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setTooltip(noctalia.tr("widget.empty"))
  end
end

function update()
  render()
end

function onClick()
  noctalia.togglePanel(core.PANEL_ID)
end

noctalia.setUpdateInterval(3000)
render()
