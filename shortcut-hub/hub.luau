--!nonstrict
-- The hub panel, shared by the three size entries (panel-compact.luau,
-- panel.luau, panel-wide.luau). A grid of tiles, one per saved item. "Edit"
-- switches to a list where items are added (from the panels of enabled
-- plugins, built-in panels, or a custom command), removed, and reordered.
--
-- A module's globals are private, so each entry defines onOpen/onClose/onIpc
-- itself and forwards them here.

local items = require("./items.luau")

local M = {}

-- Panel width comes from the manifest; keep these in step with plugin.toml.
-- `content` is the width minus the host's padding (17 px a side).
local SIZES = {
  compact = { content = 286, columns = 3 },
  normal = { content = 406, columns = 4 },
  wide = { content = 606, columns = 6 },
}
local size = SIZES.normal
local selfId = "augussst/shortcut-hub:panel"
-- Bumped on every open: a fresh root key makes the host lay the panel out
-- again, so its height fits the current content.
local openRev = 0

local saved = {}
local editing = false
local catalog = {}
local catalogByKey = {}

-- Custom-command form. Inputs are uncontrolled, so a new formRev gives them a
-- fresh key and clears them after an add.
local formLabel = ""
local formCommand = ""
local formGlyph = ""
local formRev = 0

local render -- forward declaration

local function tr(key, subst)
  return noctalia.tr(key, subst)
end

-- The Columns setting overrides the size's default; 0 means "use the default".
local function columns()
  local n = math.floor(tonumber(noctalia.getConfig("columns")) or 0)
  if n <= 0 then
    return size.columns
  end
  -- Never so many that a tile gets narrower than ~70 px.
  return math.clamp(n, 1, math.max(1, math.floor((size.content + 8) / 78)))
end

local function persist()
  local ok, err = items.save(saved)
  if not ok then
    noctalia.notifyError(tr("title"), err or "")
  end
end

local function hasKey(key)
  for _, item in ipairs(saved) do
    if items.key(item) == key then
      return true
    end
  end
  return false
end

local function refreshCatalog()
  catalog = items.catalog()
  catalogByKey = items.indexByKey(catalog)
end

-- View mode -----------------------------------------------------------------

local GAP = 8

local function tileWidth(cols)
  return math.floor((size.content - GAP * (cols - 1)) / cols)
end

local function tile(item, index, width)
  local label, glyph = items.display(item, catalogByKey)
  return ui.column({
    key = "tile-" .. index .. "-" .. items.key(item),
    width = width,
    minHeight = 76,
    gap = 6,
    paddingV = 10,
    paddingH = 6,
    align = "center",
    justify = "center",
    fill = "surface_container",
    radius = 12,
    tooltip = label,
    onClick = function()
      items.run(item)
    end,
  }, {
    ui.glyph({ name = glyph, size = 22, color = "primary" }),
    ui.label({ text = label, maxLines = 2, maxWidth = width - 12, textAlign = "center" }),
  })
end

local function grid()
  local cols = columns()
  local width = tileWidth(cols)
  local rows = {}
  local row = {}
  for i, item in ipairs(saved) do
    table.insert(row, tile(item, i, width))
    if #row == cols then
      table.insert(rows, ui.row({ key = "row-" .. #rows, gap = GAP, justify = "center" }, row))
      row = {}
    end
  end
  if #row > 0 then
    -- Invisible fillers keep a short last row aligned with the full rows.
    while #row < cols do
      table.insert(row, ui.column({ key = "pad-" .. #row, width = width }, {}))
    end
    table.insert(rows, ui.row({ key = "row-" .. #rows, gap = GAP, justify = "center" }, row))
  end
  return ui.column({ gap = GAP }, rows)
end

local function viewBody()
  if #saved == 0 then
    return ui.column({ gap = 10, padding = 16, align = "center" }, {
      ui.glyph({ name = "layout-grid", size = 32, color = "on_surface/0.5" }),
      ui.label({ text = tr("empty"), color = "on_surface/0.7", textAlign = "center" }),
      ui.button({ text = tr("edit"), glyph = "pencil-plus", variant = "primary", onClick = function()
        M.setEditing(true)
      end }),
    })
  end
  return grid()
end

-- Edit mode -----------------------------------------------------------------

local function sectionTitle(text)
  return ui.label({ text = text, fontWeight = "bold", color = "primary" })
end

local function savedRow(item, index)
  local label, glyph = items.display(item, catalogByKey)
  return ui.row({
    key = "saved-" .. items.key(item),
    gap = 6,
    align = "center",
    paddingH = 8,
    paddingV = 4,
    fill = "surface_container",
    radius = 8,
  }, {
    ui.glyph({ name = glyph, size = 16, color = "primary" }),
    ui.column({ flexGrow = 1, gap = 0 }, {
      ui.label({ text = label, maxLines = 1 }),
      ui.label({ text = items.kindLabel(item), fontSize = 12, color = "on_surface/0.6", maxLines = 1 }),
    }),
    ui.button({ glyph = "arrow-up", variant = "ghost", controlSize = "sm", tooltip = tr("move_up"), enabled = index > 1, onClick = function()
      saved[index], saved[index - 1] = saved[index - 1], saved[index]
      persist()
      render()
    end }),
    ui.button({ glyph = "arrow-down", variant = "ghost", controlSize = "sm", tooltip = tr("move_down"), enabled = index < #saved, onClick = function()
      saved[index], saved[index + 1] = saved[index + 1], saved[index]
      persist()
      render()
    end }),
    ui.button({ glyph = "trash", variant = "ghost", controlSize = "sm", tooltip = tr("remove"), onClick = function()
      table.remove(saved, index)
      persist()
      render()
    end }),
  })
end

local function catalogRow(item)
  return ui.row({
    key = "add-" .. items.key(item),
    gap = 6,
    align = "center",
    paddingH = 8,
    paddingV = 2,
  }, {
    ui.glyph({ name = item.glyph, size = 16, color = "on_surface/0.8" }),
    ui.label({ text = item.label, maxLines = 1, flexGrow = 1 }),
    ui.button({ glyph = "plus", variant = "ghost", controlSize = "sm", tooltip = tr("add"), onClick = function()
      table.insert(saved, { kind = item.kind, target = item.target, label = item.label, glyph = item.glyph })
      persist()
      render()
    end }),
  })
end

local function addCommand()
  local command = noctalia.string.trim(formCommand)
  if command == "" then
    noctalia.notifyError(tr("title"), tr("command_missing"))
    return
  end
  local label = noctalia.string.trim(formLabel)
  table.insert(saved, {
    kind = "command",
    target = command,
    label = label ~= "" and label or command,
    glyph = noctalia.string.trim(formGlyph),
  })
  persist()
  formLabel, formCommand, formGlyph = "", "", ""
  formRev += 1
  render()
end

local function editBody()
  local children = {}

  table.insert(children, sectionTitle(tr("section.saved")))
  if #saved == 0 then
    table.insert(children, ui.label({ text = tr("section.saved_empty"), fontSize = 12, color = "on_surface/0.6" }))
  end
  for i, item in ipairs(saved) do
    table.insert(children, savedRow(item, i))
  end

  local pluginRows, builtinRows = {}, {}
  for _, item in ipairs(catalog) do
    if not hasKey(items.key(item)) then
      table.insert(item.kind == "plugin" and pluginRows or builtinRows, catalogRow(item))
    end
  end

  table.insert(children, ui.separator({ spacing = 4 }))
  table.insert(children, sectionTitle(tr("section.plugins")))
  if #pluginRows == 0 then
    table.insert(children, ui.label({ text = tr("section.plugins_empty"), fontSize = 12, color = "on_surface/0.6" }))
  end
  for _, r in ipairs(pluginRows) do
    table.insert(children, r)
  end

  if #builtinRows > 0 then
    table.insert(children, ui.separator({ spacing = 4 }))
    table.insert(children, sectionTitle(tr("section.builtin")))
    for _, r in ipairs(builtinRows) do
      table.insert(children, r)
    end
  end

  table.insert(children, ui.separator({ spacing = 4 }))
  table.insert(children, sectionTitle(tr("section.command")))
  table.insert(children, ui.input({
    key = "form-label-" .. formRev,
    placeholder = tr("form.label"),
    controlSize = "sm",
    onChange = function(v)
      formLabel = v
    end,
  }))
  table.insert(children, ui.input({
    key = "form-command-" .. formRev,
    placeholder = tr("form.command"),
    controlSize = "sm",
    onChange = function(v)
      formCommand = v
    end,
    onSubmit = function()
      addCommand()
    end,
  }))
  table.insert(children, ui.row({ gap = 6, align = "center" }, {
    ui.input({
      key = "form-glyph-" .. formRev,
      placeholder = tr("form.glyph"),
      controlSize = "sm",
      flexGrow = 1,
      onChange = function(v)
        formGlyph = v
      end,
    }),
    ui.button({ text = tr("add"), glyph = "plus", variant = "primary", controlSize = "sm", onClick = function()
      addCommand()
    end }),
  }))
  table.insert(children, ui.label({ text = tr("form.hint"), fontSize = 12, color = "on_surface/0.6" }))

  -- The panel fits its content (up to max_height), and a bare scroll is
  -- measured as almost nothing, so it sits in a column of fixed height.
  return ui.column({ height = 520 }, {
    ui.scroll({ flexGrow = 1, gap = 6 }, children),
  })
end

-- Frame ---------------------------------------------------------------------

render = function()
  local header = ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "layout-grid", size = 18, color = "primary" }),
    ui.label({ text = editing and tr("editing") or tr("title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
    ui.button({
      glyph = editing and "check" or "pencil-plus",
      variant = editing and "primary" or "ghost",
      controlSize = "sm",
      tooltip = editing and tr("done") or tr("edit"),
      onClick = function()
        M.setEditing(not editing)
      end,
    }),
    ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", tooltip = tr("close"), onClick = function()
      panel.close()
    end }),
  })

  -- No flexGrow on the root: the panel's height follows its content.
  panel.render(ui.column({ key = "root-" .. openRev, gap = 12 }, {
    header,
    editing and editBody() or viewBody(),
  }))
end

-- Entry id of each size's panel, as declared in plugin.toml.
local ENTRY_IDS = { compact = "compact", normal = "panel", wide = "wide" }

function M.setup(sizeName)
  size = SIZES[sizeName] or SIZES.normal
  selfId = "augussst/shortcut-hub:" .. (ENTRY_IDS[sizeName] or "panel")
end

-- A content-height panel grows while open but does not shrink back, so
-- leaving edit mode reopens the panel to fit the grid again.
function M.setEditing(value)
  if value then
    editing = true
    refreshCatalog()
    render()
  elseif editing then
    editing = false
    -- The panel reopens at the size of the last rendered tree, so render
    -- the grid before closing.
    render()
    panel.close()
    -- Reopening in the same callback races the close, so wait for it.
    noctalia.runAsync({ "sh", "-c", 'sleep 0.2; exec noctalia msg panel-open "$0"', selfId })
  end
end

-- `noctalia msg panel-open augussst/shortcut-hub:panel edit` opens in edit mode.
function M.onOpen(context)
  openRev += 1
  saved = items.load()
  editing = context == "edit"
  refreshCatalog()
  render()
end

function M.onClose()
  if editing then
    -- Closed from edit mode (Escape, outside click): leave the grid as the
    -- last rendered tree so the next open is not edit-sized.
    editing = false
    render()
  end
end

-- `noctalia msg plugin augussst/shortcut-hub:panel all edit` (or `view`)
-- switches mode while the panel is open.
function M.onIpc(event, _payload)
  if event == "edit" or event == "view" then
    M.setEditing(event == "edit")
  end
end

return M
