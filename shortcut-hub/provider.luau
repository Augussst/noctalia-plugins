--!nonstrict
-- Launcher logic shared by the two launcher entries:
--   launcher.luau (`/hub`)      - hub items, then every plugin and shell panel
--   search.luau (global search) - hub items only, so internal panels of other
--                                 plugins do not clutter normal search
-- A provider script cannot tell whether it was reached by its prefix or by
-- global search, hence two entries.

local items = require("./items.luau")

local M = {}

local OPEN_HUB = "open-hub"
local byId = {}

local function tr(key)
  return noctalia.tr(key)
end

local function row(item, label, glyph, subtitle, score)
  local id = items.key(item)
  byId[id] = item
  return { id = id, title = label, subtitle = subtitle, glyph = glyph, score = score }
end

function M.query(query, includeCatalog)
  local text = noctalia.string.trim(query)
  byId = {}

  local catalog = items.catalog()
  local catalogByKey = items.indexByKey(catalog)
  local saved = items.load()
  local seen = {}
  local results = {}

  local hubTitle = tr("launcher.open_hub")
  local hubScore = text == "" and 1000 or noctalia.fuzzyScore(text, hubTitle)
  if hubScore ~= nil then
    table.insert(results, { id = OPEN_HUB, title = hubTitle, subtitle = tr("launcher.open_hub_subtitle"), glyph = "layout-grid", score = hubScore + 1 })
  end

  -- Hub items first, in hub order when nothing is typed.
  local total = #saved
  for i, item in ipairs(saved) do
    seen[items.key(item)] = true
    local label, glyph = items.display(item, catalogByKey)
    local score = text == "" and (500 + total - i) or noctalia.fuzzyScore(text, label)
    if score ~= nil then
      table.insert(results, row(item, label, glyph, tr("launcher.in_hub") .. " · " .. items.kindLabel(item), score + 0.5))
    end
  end

  if includeCatalog then
    for _, item in ipairs(catalog) do
      if not seen[items.key(item)] then
        local score = text == "" and 0 or noctalia.fuzzyScore(text, item.label)
        if score ~= nil then
          table.insert(results, row(item, item.label, item.glyph, items.kindLabel(item), score))
        end
      end
    end
  end

  launcher.setResults(query, results)
end

function M.activate(id)
  if id == OPEN_HUB then
    noctalia.togglePanel(items.panelId())
    return
  end
  local item = byId[id]
  if item ~= nil then
    items.run(item)
  end
end

return M
