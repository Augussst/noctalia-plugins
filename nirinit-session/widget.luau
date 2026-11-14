--!nonstrict
-- Bar icon. Highlighted with a count while a saved session is waiting for your
-- answer; click opens the panel. At login (setting "auto_open") the panel
-- opens by itself once per waiting session.

local core = require("./core.luau")

local pending = nil

local function hideWhenIdle()
  local v = noctalia.getConfig("hide_when_idle")
  return v == nil or v == true or v == "true"
end

local function render(status)
  barWidget.setText("")
  -- Invisible unless a session is waiting (polling continues while hidden).
  barWidget.setVisible(not hideWhenIdle() or (status ~= nil and status.pending ~= nil))
  if status == nil then
    barWidget.setGlyph("history")
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setTooltip(noctalia.tr("widget.unavailable"))
  elseif status.pending then
    barWidget.setGlyph("history")
    barWidget.setText(tostring(status.pending.count))
    barWidget.setGlyphColor("primary")
    barWidget.setTooltip(noctalia.tr("widget.pending", { n = status.pending.count }))
  else
    barWidget.setGlyph("history")
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setTooltip(noctalia.tr(status.running and "widget.idle" or "widget.not_running"))
  end
end

local function autoOpen()
  local v = noctalia.getConfig("auto_open")
  return v == nil or v == true or v == "true"
end

local function poll()
  core.status(function(status)
    pending = status
    render(status)
    -- `claim` answers "yes" once per waiting session, so several bar widgets
    -- (one per monitor) never toggle the panel open and shut again.
    if status and status.pending and not status.claimed and autoOpen() then
      core.run({ "claim" }, function(result)
        if noctalia.string.trim(result.stdout or "") == "yes" then
          noctalia.togglePanel(core.PANEL_ID)
        end
      end)
    end
  end)
end

function update()
  poll()
end

function onClick()
  noctalia.togglePanel(core.PANEL_ID)
end

noctalia.setUpdateInterval(3000)
render(nil)
poll()
