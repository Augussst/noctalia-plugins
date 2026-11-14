--!nonstrict
-- Session Restore panel. Shows the session saved before the last logout and
-- asks: Restore, Start fresh, or Later. Everything goes through
-- bin/nirinit-ctl (see core.luau).

local core = require("./core.luau")
local tr = noctalia.tr

local status = nil -- last `nirinit-ctl status`, nil while loading
local busy = nil -- text while a restore is running
local cfg = nil -- last `nirinit-ctl config`
local tab = "session"
local intervalDraft = ""
local formRev = 0
local render

local function dim(text, extra)
  local props = { text = text, fontSize = 12, color = "on_surface/0.65" }
  for k, v in pairs(extra or {}) do
    props[k] = v
  end
  return ui.label(props)
end

local function fail(result, what)
  local msg = noctalia.string.trim((result and (result.stderr or result.stdout)) or "")
  noctalia.notifyError(tr("title"), what .. (msg ~= "" and (": " .. msg) or ""))
end

local function load()
  core.status(function(s)
    status = s
    render()
  end)
end

local function loadConfig()
  core.run({ "config" }, function(result)
    local ok, value = pcall(function()
      return noctalia.json.decode(result.stdout or "")
    end)
    if ok and type(value) == "table" then
      cfg = value
      intervalDraft = tostring(value.save_interval or 0)
      formRev += 1
    end
    render()
  end)
end

-- Runs a config change, then reloads the config.
local function change(args, what)
  core.run(args, function(result)
    if result.exitCode ~= 0 then
      fail(result, what)
    end
    loadConfig()
  end)
end

local function restore()
  busy = tr("restoring")
  render()
  -- Each window is waited for, so this can take a while for a big session.
  core.run({ "restore" }, function(result)
    busy = nil
    if result.exitCode ~= 0 then
      fail(result, tr("restore_failed"))
      load()
      return
    end
    panel.close()
  end, 240000)
end

local function discard()
  core.run({ "discard" }, function(result)
    if result.exitCode ~= 0 then
      fail(result, tr("discard_failed"))
    end
    panel.close()
  end)
end

local function undo()
  core.run({ "undo" }, function(result)
    if result.exitCode ~= 0 then
      fail(result, tr("undo_failed"))
    end
    load()
  end)
end

local function appRows(session)
  local rows = {}
  for _, a in ipairs(session.apps or {}) do
    table.insert(rows, ui.row({ key = "app-" .. a.app_id, gap = 8, align = "center" }, {
      ui.glyph({ name = "app-window", size = 16, color = "on_surface/0.65" }),
      ui.label({ text = core.appName(a.app_id), flexGrow = 1, maxLines = 1 }),
      dim("×" .. tostring(a.count)),
    }))
  end
  return rows
end

local function sectionTitle(text)
  return ui.label({ text = text, fontWeight = "bold", color = "primary" })
end

local function settingsBody()
  if cfg == nil then
    return { dim(tr("loading")) }
  end
  local rows = {}

  table.insert(rows, sectionTitle(tr("cfg.login")))
  table.insert(rows, ui.row({ gap = 6 }, {
    ui.button({ text = tr("cfg.ask"), variant = cfg.mode == "ask" and "primary" or "outline", controlSize = "sm", onClick = function()
      change({ "set", "mode", "ask" }, tr("cfg.failed"))
    end }),
    ui.button({ text = tr("cfg.auto"), variant = cfg.mode == "auto" and "primary" or "outline", controlSize = "sm", onClick = function()
      change({ "set", "mode", "auto" }, tr("cfg.failed"))
    end }),
  }))
  table.insert(rows, dim(tr(cfg.mode == "auto" and "cfg.auto_hint" or "cfg.ask_hint")))

  table.insert(rows, ui.separator({ spacing = 4 }))
  table.insert(rows, sectionTitle(tr("cfg.interval")))
  table.insert(rows, ui.row({ gap = 6, align = "center" }, {
    ui.input({
      key = "interval-" .. formRev,
      value = intervalDraft,
      controlSize = "sm",
      flexGrow = 1,
      onChange = function(v)
        intervalDraft = v or ""
      end,
    }),
    ui.button({ text = tr("cfg.save"), glyph = "check", variant = "primary", controlSize = "sm", onClick = function()
      local n = string.match(noctalia.string.trim(intervalDraft), "^%d+$")
      if n == nil then
        noctalia.notifyError(tr("title"), tr("cfg.bad_interval"))
        return
      end
      change({ "set", "save_interval", n }, tr("cfg.failed"))
    end }),
  }))
  table.insert(rows, dim(tr("cfg.interval_hint")))

  table.insert(rows, ui.separator({ spacing = 4 }))
  table.insert(rows, sectionTitle(tr("cfg.skip")))
  table.insert(rows, dim(tr("cfg.skip_hint")))
  local skipped = {}
  for _, a in ipairs(cfg.skip or {}) do
    skipped[a] = true
    table.insert(rows, ui.row({ key = "skip-" .. a, gap = 8, align = "center" }, {
      ui.glyph({ name = "ban", size = 16, color = "on_surface/0.65" }),
      ui.label({ text = a, flexGrow = 1, maxLines = 1 }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = tr("cfg.remove"), onClick = function()
        change({ "skip-remove", a }, tr("cfg.failed"))
      end }),
    }))
  end
  local first = true
  for _, a in ipairs(cfg.seen or {}) do
    if not skipped[a] then
      if first then
        table.insert(rows, dim(tr("cfg.add_from_windows")))
        first = false
      end
      table.insert(rows, ui.row({ key = "seen-" .. a, gap = 8, align = "center" }, {
        ui.label({ text = a, flexGrow = 1, maxLines = 1 }),
        ui.button({ glyph = "plus", variant = "ghost", controlSize = "sm", tooltip = tr("cfg.add"), onClick = function()
          change({ "skip-add", a }, tr("cfg.failed"))
        end }),
      }))
    end
  end

  table.insert(rows, dim(tr("cfg.next_login")))
  return rows
end

local function tabButton(name, glyph)
  return ui.button({
    text = tr("tab." .. name),
    glyph = glyph,
    variant = tab == name and "primary" or "ghost",
    controlSize = "sm",
    onClick = function()
      tab = name
      if name == "settings" then
        loadConfig()
      end
      render()
    end,
  })
end

render = function()
  local header = ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = "history", size = 20, color = "primary" }),
    ui.label({ text = tr("title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
    ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = tr("close"), onClick = function()
      panel.close()
    end }),
  })

  local tabs = ui.row({ gap = 6 }, {
    tabButton("session", "history"),
    tabButton("settings", "settings"),
  })

  local body
  if tab == "settings" then
    body = { ui.scroll({ key = "cfg-body", flexGrow = 1, gap = 8 }, settingsBody()) }
  elseif status == nil then
    body = { dim(tr("loading")) }
  elseif status.pending then
    local p = status.pending
    body = {
      ui.label({ text = tr("ask", { n = p.count }), fontWeight = "bold" }),
      dim(tr("saved", { ago = core.ago(p.saved_at) })),
      ui.scroll({ key = "apps", flexGrow = 1, gap = 6 }, appRows(p)),
    }
    if (p.skipped or 0) > 0 then
      table.insert(body, dim(tr("skipped", { n = p.skipped })))
    end
    table.insert(body, ui.row({ gap = 6, justify = "end" }, {
      ui.button({ text = tr("later"), variant = "ghost", enabled = busy == nil, onClick = function()
        panel.close()
      end }),
      ui.button({ text = tr("fresh"), glyph = "trash", variant = "outline", enabled = busy == nil, onClick = discard }),
      ui.button({ text = tr("restore"), glyph = "restore", variant = "primary", enabled = busy == nil, onClick = restore }),
    }))
    if busy then
      table.insert(body, dim(busy))
    end
  else
    body = {
      ui.label({ text = tr("nothing"), fontWeight = "bold" }),
      dim(tr(status.running and "running" or "not_running")),
      ui.spacer({ flexGrow = 1 }),
    }
    if status.last then
      table.insert(body, dim(tr("last", { n = status.last.count })))
      table.insert(body, ui.row({ gap = 6, justify = "end" }, {
        ui.button({ text = tr("undo"), glyph = "arrow-back-up", variant = "outline", onClick = undo }),
      }))
    end
  end

  local rows = { header, tabs }
  for _, r in ipairs(body) do
    table.insert(rows, r)
  end
  panel.render(ui.column({ key = "root", gap = 10, flexGrow = 1 }, rows))
end

function onOpen()
  render()
  load()
  if tab == "settings" then
    loadConfig()
  end
end

function onClose()
  busy = nil
end
