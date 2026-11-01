--!nonstrict
-- Shared by the panel and the launcher provider: the saved hub items, the
-- catalog of things that can be added (panels of enabled plugins, built-in
-- shell panels), and running an item.
--
-- An item is { kind, target, label, glyph }:
--   kind "plugin"  - target is a plugin panel id, "author/plugin:panel"
--   kind "builtin" - target is a shell panel id ("launcher", ...) or "settings"
--   kind "command" - target is a shell command line, run with /bin/sh -c
-- Items are saved as JSON in the plugin data dir, so they survive updates.

local M = {}

local SELF_ID = "augussst/shortcut-hub"
local PANEL_BY_SIZE = { compact = "compact", normal = "panel", wide = "wide" }

-- The hub panel in the size chosen in the plugin settings.
function M.panelId()
  return SELF_ID .. ":" .. (PANEL_BY_SIZE[noctalia.getConfig("panel_size")] or "panel")
end

local BUILTINS = {
  { target = "launcher", label_key = "builtin.launcher", glyph = "search" },
  { target = "control-center", label_key = "builtin.control_center", glyph = "adjustments" },
  { target = "clipboard", label_key = "builtin.clipboard", glyph = "clipboard" },
  { target = "wallpaper", label_key = "builtin.wallpaper", glyph = "photo" },
  { target = "session", label_key = "builtin.session", glyph = "power" },
  { target = "settings", label_key = "builtin.settings", glyph = "settings" },
}

function M.key(item)
  return item.kind .. ":" .. item.target
end

-- Saved items -----------------------------------------------------------------

local function storePath()
  local dir = noctalia.pluginDataDir()
  if dir == nil then
    return nil
  end
  return dir .. "/items.json"
end

local function validItem(value)
  return type(value) == "table"
    and (value.kind == "plugin" or value.kind == "builtin" or value.kind == "command")
    and type(value.target) == "string"
    and value.target ~= ""
end

function M.load()
  local path = storePath()
  local out = {}
  if path == nil then
    return out
  end
  local raw = noctalia.readFile(path)
  if raw == nil then
    return out
  end
  local decoded = noctalia.json.decode(raw)
  if type(decoded) ~= "table" then
    return out
  end
  for _, value in ipairs(decoded) do
    if validItem(value) then
      table.insert(out, {
        kind = value.kind,
        target = value.target,
        label = type(value.label) == "string" and value.label or "",
        glyph = type(value.glyph) == "string" and value.glyph or "",
      })
    end
  end
  return out
end

function M.save(items)
  local path = storePath()
  if path == nil then
    return false, "no data dir"
  end
  local encoded = noctalia.json.encode(items, true)
  if encoded == nil then
    return false, "encode failed"
  end
  return noctalia.writeFile(path, encoded)
end

-- Plugin manifests ------------------------------------------------------------

-- Reads the few manifest fields the hub needs: root `id`, `name`, `icon`, and
-- the `id` of each [[panel]] table. Not a TOML parser; it only understands the
-- `key = "value"` lines that plugin manifests use for these fields.
local function parseManifest(text)
  local root = {}
  local panels = {}
  local section = "" -- "" is the root table
  local current = nil
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local s = line:gsub("^%s+", "")
    if s:sub(1, 1) == "[" then
      local arrayName = s:match("^%[%[%s*([%w_%.]+)%s*%]%]")
      if arrayName == "panel" then
        current = {}
        table.insert(panels, current)
        section = "panel"
      else
        section = arrayName or "other"
        current = nil
      end
    else
      local k, v = s:match('^([%w_]+)%s*=%s*"(.-)"')
      if k == nil then
        k, v = s:match("^([%w_]+)%s*=%s*'(.-)'")
      end
      if k ~= nil then
        if section == "" then
          if root[k] == nil then
            root[k] = v
          end
        elseif section == "panel" and current ~= nil and current[k] == nil then
          current[k] = v
        end
      end
    end
  end
  return root, panels
end

local function prettify(id)
  local s = id:gsub("[-_]+", " ")
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- Where git-installed plugins are unpacked: the sibling of the data dir,
-- <state>/plugins/materialized/<source>/<plugin>.
local function materializedDir()
  local dir = noctalia.pluginDataDir()
  if dir == nil then
    return nil
  end
  local base = dir:match("^(.*)/data/[^/]+/[^/]+/?$")
  if base == nil then
    return nil
  end
  return base .. "/materialized"
end

local function asList(value)
  return type(value) == "table" and value or {}
end

-- Panels of every enabled plugin (except this one), as items.
local cache = nil
local cacheTime = 0

function M.pluginPanels()
  local now = os.time()
  if cache ~= nil and now - cacheTime < 10 then
    return cache
  end

  local enabled = asList(noctalia.getSetting("plugins.enabled"))
  local sources = asList(noctalia.getSetting("plugins.source"))
  local materialized = materializedDir()
  local out = {}

  for _, id in ipairs(enabled) do
    local pluginName = type(id) == "string" and id:match("^[^/]+/(.+)$") or nil
    if pluginName ~= nil and id ~= SELF_ID then
      for _, source in ipairs(sources) do
        local dir = nil
        if type(source) == "table" then
          if source.kind == "path" and type(source.location) == "string" then
            dir = noctalia.expandPath(source.location) .. "/" .. pluginName
          elseif materialized ~= nil and type(source.name) == "string" then
            dir = materialized .. "/" .. source.name .. "/" .. pluginName
          end
        end
        local raw = dir and noctalia.readFile(dir .. "/plugin.toml") or nil
        if raw ~= nil then
          local root, panels = parseManifest(raw)
          if root.id == id then
            local name = root.name or pluginName
            for _, p in ipairs(panels) do
              if type(p.id) == "string" and p.id ~= "" then
                table.insert(out, {
                  kind = "plugin",
                  target = id .. ":" .. p.id,
                  label = #panels > 1 and (name .. " · " .. prettify(p.id)) or name,
                  glyph = root.icon or "puzzle",
                  plugin = name,
                })
              end
            end
            break
          end
        end
      end
    end
  end

  table.sort(out, function(a, b)
    return a.label:lower() < b.label:lower()
  end)
  cache = out
  cacheTime = now
  return out
end

function M.builtins()
  local out = {}
  for _, b in ipairs(BUILTINS) do
    table.insert(out, { kind = "builtin", target = b.target, label = noctalia.tr(b.label_key), glyph = b.glyph })
  end
  return out
end

-- Everything that can be added: plugin panels first, then built-in panels.
function M.catalog()
  local out = {}
  for _, item in ipairs(M.pluginPanels()) do
    table.insert(out, item)
  end
  for _, item in ipairs(M.builtins()) do
    table.insert(out, item)
  end
  return out
end

-- Display helpers ---------------------------------------------------------------

-- Saved items store their own label/glyph; fall back to the catalog's, then
-- to something derived from the target.
function M.display(item, catalogByKey)
  local known = catalogByKey and catalogByKey[M.key(item)] or nil
  local label = item.label ~= "" and item.label or (known and known.label) or item.target
  local glyph = item.glyph ~= "" and item.glyph or (known and known.glyph)
  if glyph == nil or glyph == "" then
    glyph = item.kind == "command" and "terminal" or "puzzle"
  end
  return label, glyph
end

function M.indexByKey(list)
  local out = {}
  for _, item in ipairs(list) do
    out[M.key(item)] = item
  end
  return out
end

function M.kindLabel(item)
  if item.kind == "plugin" then
    return noctalia.tr("kind.plugin")
  elseif item.kind == "builtin" then
    return noctalia.tr("kind.builtin")
  end
  return noctalia.tr("kind.command")
end

-- Running -----------------------------------------------------------------------

function M.run(item)
  if item.kind == "plugin" then
    noctalia.togglePanel(item.target)
  elseif item.kind == "builtin" then
    if item.target == "settings" then
      noctalia.runAsync({ "noctalia", "msg", "settings-toggle" })
    else
      noctalia.runAsync({ "noctalia", "msg", "panel-toggle", item.target })
    end
  elseif item.kind == "command" then
    noctalia.runAsync(item.target)
  end
end

return M
