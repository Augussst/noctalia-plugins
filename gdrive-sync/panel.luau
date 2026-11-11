--!nonstrict
-- GDrive Sync panel: Folders, Trash and Settings tabs, plus a Setup page that
-- shows instead of the tabs until the dependencies, an rclone Google Drive
-- account and the CLI/timer/Dolphin menus are in place.
--
-- All changes go through bin/gdrive-sync (see core.luau). Long jobs (adding a
-- folder, syncing) are started in the background; the panel follows them by
-- re-reading ~/.cache/gdrive-sync/status.json every second while open.

local core = require("./core.luau")

local tr = noctalia.tr

local tab = "folders"
local openRev = 0
local doctor = nil -- result of `gdrive-sync doctor`, nil while loading
local busy = nil -- text of a short blocking action (install, save, ...)
local confirmKey = nil -- id of the button waiting for a second click

local remoteIndex = 0 -- selected account in the Folders tab (0-based)
local offlineDraft = ""
local formRev = 0

local trashItems = nil
local trashLoading = false

local drafts = {}
local settingsRev = 0

local lastStatusRaw = nil
local hostname = nil

local render -- forward declaration

-- Helpers -------------------------------------------------------------------

local function radius(base)
  local scale = tonumber(noctalia.getSetting("shell.corner_radius_scale")) or 1
  return base * math.max(scale, 0)
end

local function host()
  if hostname == nil then
    hostname = noctalia.string.trim(noctalia.readFile("/etc/hostname") or "")
    if hostname == "" then
      hostname = "this-pc"
    end
  end
  return hostname
end

local function remotes()
  return (doctor and doctor.remotes) or {}
end

local function selectedRemote()
  return remotes()[remoteIndex + 1]
end

local function dim(text, extra)
  local props = { text = text, fontSize = 12, color = "on_surface/0.65" }
  for k, v in pairs(extra or {}) do
    props[k] = v
  end
  return ui.label(props)
end

local function sectionTitle(text)
  return ui.label({ text = text, fontWeight = "bold", color = "primary" })
end

local function fail(result, what)
  local msg = noctalia.string.trim((result and (result.stderr or result.stdout)) or "")
  noctalia.notifyError(tr("title"), what .. (msg ~= "" and (": " .. msg) or ""))
end

-- A button that needs two clicks: the first turns it into "Confirm?".
local function confirmButton(key, props, action)
  local armed = confirmKey == key
  props.variant = armed and "destructive" or (props.variant or "ghost")
  if armed then
    props.text = tr("confirm")
    props.tooltip = nil
  end
  props.onClick = function()
    if confirmKey == key then
      confirmKey = nil
      action()
    else
      confirmKey = key
    end
    render()
  end
  return ui.button(props)
end

-- Data ----------------------------------------------------------------------

local loadDoctor -- forward

local function install(after)
  busy = tr("setup.installing")
  render()
  core.run({ "install" }, function(result)
    busy = nil
    if result.exitCode ~= 0 then
      fail(result, tr("setup.install_failed"))
    end
    if after then
      after(result.exitCode == 0)
    end
    loadDoctor()
  end, 120000)
end

loadDoctor = function()
  core.run({ "doctor" }, function(result)
    local ok, value = pcall(function()
      return noctalia.json.decode(result.stdout or "")
    end)
    if not ok or type(value) ~= "table" then
      doctor = { error = noctalia.string.trim(result.stderr or "doctor failed"), deps = {}, remotes = {} }
      render()
      return
    end
    doctor = value
    if remoteIndex >= #remotes() then
      remoteIndex = 0
    end
    -- An older copy is installed (the plugin was updated): update it quietly.
    local iv = doctor.installed_version or ""
    if iv ~= "" and iv ~= doctor.version and busy == nil then
      install(function(done)
        if done then
          noctalia.notify(tr("title"), tr("setup.updated", { version = doctor.version }))
        end
      end)
      return
    end
    render()
  end, 30000)
end

local function loadTrash()
  trashLoading = true
  render()
  core.run({ "trash", "list" }, function(result)
    trashLoading = false
    local ok, value = pcall(function()
      return noctalia.json.decode(result.stdout or "")
    end)
    trashItems = (ok and type(value) == "table") and value or {}
    if result.exitCode ~= 0 then
      fail(result, tr("trash.load_failed"))
    end
    render()
  end, 120000)
end

local function missingRequired()
  local out = {}
  for _, d in ipairs((doctor and doctor.deps) or {}) do
    if d.required and not d.ok then
      table.insert(out, d)
    end
  end
  return out
end

local function needsSetup()
  if doctor == nil then
    return false
  end
  return doctor.error ~= nil
    or #missingRequired() > 0
    or #remotes() == 0
    or (doctor.installed_version or "") == ""
end

-- Setup ---------------------------------------------------------------------

local function setupBody()
  local children = {}
  table.insert(children, dim(tr("setup.intro")))

  if doctor.error then
    table.insert(children, ui.label({ text = doctor.error, color = "error" }))
  end

  -- 1. Programs
  table.insert(children, sectionTitle(tr("setup.step_deps")))
  local missingPkgs = {}
  for _, d in ipairs(doctor.deps or {}) do
    if not d.ok then
      local pkg = string.match(d.package or "", "^(%S+)") or d.name
      if not string.find(d.package or "", "AUR", 1, true) then
        table.insert(missingPkgs, pkg)
      end
    end
    table.insert(children, ui.row({ key = "dep-" .. d.name, gap = 6, align = "center" }, {
      ui.glyph({ name = d.ok and "circle-check" or "circle-x", size = 16, color = d.ok and "primary" or (d.required and "error" or "on_surface/0.6") }),
      ui.label({ text = d.name, flexGrow = 1 }),
      dim(d.ok and tr("setup.found") or ((d.required and tr("setup.required") or tr("setup.optional")) .. " · " .. (d.package or ""))),
    }))
  end
  if #missingPkgs > 0 then
    local cmd = "sudo pacman -S --needed " .. table.concat(missingPkgs, " ")
    table.insert(children, ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = cmd, fontSize = 12, flexGrow = 1, maxLines = 2 }),
      ui.button({ glyph = "copy", variant = "ghost", controlSize = "sm", tooltip = tr("copy"), onClick = function()
        noctalia.copyToClipboard(cmd)
      end }),
      ui.button({ text = tr("setup.run_in_terminal"), glyph = "terminal-2", variant = "outline", controlSize = "sm", onClick = function()
        noctalia.runInTerminal(cmd)
      end }),
    }))
  end

  -- 2. Accounts
  table.insert(children, ui.separator({ spacing = 4 }))
  table.insert(children, sectionTitle(tr("setup.step_accounts")))
  if #remotes() == 0 then
    table.insert(children, dim(tr("setup.no_accounts")))
  else
    local config = core.config()
    for _, r in ipairs(remotes()) do
      table.insert(children, ui.row({ key = "acc-" .. r, gap = 6, align = "center" }, {
        ui.glyph({ name = "brand-google-drive", size = 16, color = "primary" }),
        ui.label({ text = core.label(config, r), flexGrow = 1 }),
        dim(r .. ":"),
      }))
    end
  end
  table.insert(children, ui.row({ gap = 6 }, {
    ui.button({ text = tr("setup.add_account"), glyph = "user-plus", variant = "outline", controlSize = "sm", onClick = function()
      noctalia.runInTerminal("rclone config")
    end }),
  }))

  -- 3. Install
  table.insert(children, ui.separator({ spacing = 4 }))
  table.insert(children, sectionTitle(tr("setup.step_install")))
  table.insert(children, dim(tr("setup.install_hint")))
  local ready = #missingRequired() == 0 and #remotes() > 0
  table.insert(children, ui.row({ gap = 6 }, {
    ui.button({
      text = (doctor.installed_version or "") ~= "" and tr("setup.installed") or tr("setup.install"),
      glyph = "download",
      variant = "primary",
      enabled = ready and busy == nil and (doctor.installed_version or "") == "",
      onClick = function()
        install(nil)
      end,
    }),
    ui.button({ text = tr("setup.check_again"), glyph = "refresh", variant = "ghost", onClick = function()
      doctor = nil
      render()
      loadDoctor()
    end }),
  }))
  return children
end

-- Folders tab ---------------------------------------------------------------

local function folderStatusLine(f, status)
  local s = status.folders[f["local"]]
  if status.running == f["local"] then
    return ui.label({ text = tr("folders.syncing"), fontSize = 12, color = "primary" })
  elseif type(s) ~= "table" then
    return dim(tr("folders.waiting"))
  elseif s.ok == false then
    return ui.label({ text = tr("folders.failed", { msg = tostring(s.msg or "") }), fontSize = 12, color = "error", maxLines = 3 })
  end
  return dim(tr("folders.synced", { ago = core.ago(s.last) }))
end

local function folderRow(f, config, status)
  local isOffline = f.kind == "offline"
  local running = status.running == f["local"]
  return ui.row({
    key = "folder-" .. f["local"],
    gap = 8,
    align = "center",
    paddingH = 10,
    paddingV = 8,
    fill = "surface_container",
    radius = radius(10),
  }, {
    ui.glyph({
      name = isOffline and "cloud-download" or "cloud-upload",
      size = 20,
      color = "primary",
    }),
    ui.column({ flexGrow = 1, gap = 1 }, {
      ui.label({ text = core.basename(f["local"]), fontWeight = "bold", maxLines = 1 }),
      dim(core.label(config, f.remote) .. " · " .. tostring(f.remote_path), { maxLines = 1 }),
      folderStatusLine(f, status),
    }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = tr("folders.sync_now"), enabled = not running, onClick = function()
      core.detach({ "run", f["local"] })
    end }),
    ui.button({ glyph = "folder-open", variant = "ghost", controlSize = "sm", tooltip = tr("folders.open_local"), onClick = function()
      noctalia.runAsync({ "xdg-open", f["local"] }, nil, 5000)
    end }),
    ui.button({ glyph = "external-link", variant = "ghost", controlSize = "sm", tooltip = tr("folders.open_drive"), onClick = function()
      noctalia.runAsync({ "dolphin", "rclone:/" .. f.remote .. "/" .. f.remote_path }, nil, 5000)
    end }),
    confirmButton("stop-" .. f["local"], { glyph = "x", controlSize = "sm", tooltip = tr("folders.stop") }, function()
      core.run({ "remove", f["local"] }, function(result)
        if result.exitCode ~= 0 then
          fail(result, tr("folders.stop_failed"))
        end
        render()
      end)
    end),
  })
end

local function addFolder()
  local r = selectedRemote()
  if r == nil then
    return
  end
  noctalia.runAsync({ "zenity", "--file-selection", "--directory", "--title=" .. tr("folders.pick_title") }, function(result)
    local path = noctalia.string.trim(result.stdout or "")
    if result.exitCode == 0 and path ~= "" then
      core.detach({ "add", r, path })
    end
  end, 600000)
end

local function keepOffline()
  local r = selectedRemote()
  local path = noctalia.string.trim(offlineDraft)
  path = string.gsub(string.gsub(path, "^/+", ""), "/+$", "")
  if r == nil or path == "" then
    noctalia.notifyError(tr("title"), tr("folders.offline_missing"))
    return
  end
  core.detach({ "offline", r .. ":" .. path })
  offlineDraft = ""
  formRev += 1
  render()
end

local function foldersBody()
  local config = core.config()
  local folders = core.folders()
  local status = core.status()
  local children = {}

  local labels = {}
  for _, r in ipairs(remotes()) do
    table.insert(labels, core.label(config, r))
  end

  table.insert(children, ui.row({ gap = 6, align = "center" }, {
    ui.select({ key = "account", options = labels, selectedIndex = remoteIndex, controlSize = "sm", width = 130, onChange = function(index)
      remoteIndex = tonumber(index) or 0
      render()
    end }),
    ui.button({ text = tr("folders.add"), glyph = "folder-plus", variant = "primary", controlSize = "sm", onClick = addFolder }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({ glyph = "brand-google-drive", variant = "ghost", controlSize = "sm", tooltip = tr("folders.browse"), onClick = function()
      local r = selectedRemote()
      if r then
        noctalia.runAsync({ "dolphin", "rclone:/" .. r .. "/" }, nil, 5000)
      end
    end }),
  }))
  table.insert(children, ui.row({ gap = 6, align = "center" }, {
    ui.input({
      key = "offline-" .. formRev,
      placeholder = tr("folders.offline_placeholder"),
      controlSize = "sm",
      flexGrow = 1,
      onChange = function(v)
        offlineDraft = v or ""
      end,
      onSubmit = keepOffline,
    }),
    ui.button({ text = tr("folders.keep_offline"), glyph = "folder-down", variant = "outline", controlSize = "sm", onClick = keepOffline }),
  }))
  table.insert(children, dim(tr("folders.hint")))
  table.insert(children, ui.separator({ spacing = 4 }))

  if #folders == 0 then
    table.insert(children, ui.column({ gap = 8, padding = 16, align = "center" }, {
      ui.glyph({ name = "cloud", size = 32, color = "on_surface/0.5" }),
      ui.label({ text = tr("folders.empty"), color = "on_surface/0.7", textAlign = "center" }),
    }))
  end
  for _, f in ipairs(folders) do
    table.insert(children, folderRow(f, config, status))
  end
  return children
end

-- Trash tab -----------------------------------------------------------------

local function folderForTrash(item)
  for _, f in ipairs(core.folders()) do
    if f.remote == item.remote and core.basename(f.remote_path) == item.folder then
      return f
    end
  end
  return nil
end

local function trashRow(item, i)
  local where = item.side == "local" and tr("trash.deleted_on_drive") or tr("trash.deleted_here")
  local args = { item.side, item.remote, item.folder, item.path }
  return ui.row({
    key = "trash-" .. i .. "-" .. item.side .. "-" .. item.path,
    gap = 8,
    align = "center",
    paddingH = 10,
    paddingV = 6,
    fill = "surface_container",
    radius = radius(8),
  }, {
    ui.glyph({ name = item.side == "local" and "device-laptop" or "brand-google-drive", size = 16, color = "on_surface/0.8" }),
    ui.column({ flexGrow = 1, gap = 1 }, {
      ui.label({ text = item.name, maxLines = 1 }),
      dim(core.ago(item.deleted) .. " · " .. where .. " · " .. item.folder, { maxLines = 1 }),
    }),
    ui.button({ glyph = "arrow-back-up", variant = "ghost", controlSize = "sm", tooltip = tr("trash.restore"), onClick = function()
      core.run({ "trash", "restore", item.side, item.remote, item.folder, item.path, item.name }, function(result)
        if result.exitCode ~= 0 then
          fail(result, tr("trash.restore_failed"))
        else
          local f = folderForTrash(item)
          if f then
            core.detach({ "run", f["local"] })
          end
          noctalia.notify(tr("title"), tr("trash.restored", { name = item.name }))
        end
        loadTrash()
      end, 120000)
    end }),
    confirmButton("del-" .. i .. "-" .. item.path, { glyph = "trash-x", controlSize = "sm", tooltip = tr("trash.delete") }, function()
      local a = { "trash", "delete" }
      for _, v in ipairs(args) do
        table.insert(a, v)
      end
      core.run(a, function(result)
        if result.exitCode ~= 0 then
          fail(result, tr("trash.delete_failed"))
        end
        loadTrash()
      end, 60000)
    end),
  })
end

local function trashBody()
  local config = core.config()
  local children = {}
  table.insert(children, ui.row({ gap = 6, align = "center" }, {
    dim(tr("trash.hint", { days = tostring(config.trash_days or 30) }), { flexGrow = 1 }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = tr("refresh"), enabled = not trashLoading, onClick = loadTrash }),
    confirmButton("empty-trash", { text = tr("trash.empty_all"), glyph = "trash", controlSize = "sm" }, function()
      trashLoading = true
      render()
      core.run({ "trash", "clean", "0" }, function(result)
        if result.exitCode ~= 0 then
          fail(result, tr("trash.delete_failed"))
        end
        loadTrash()
      end, 600000)
    end),
  }))
  table.insert(children, ui.separator({ spacing = 4 }))
  if trashItems == nil or (trashLoading and #trashItems == 0) then
    table.insert(children, dim(tr("loading")))
  elseif #trashItems == 0 then
    table.insert(children, ui.column({ gap = 8, padding = 16, align = "center" }, {
      ui.glyph({ name = "trash", size = 32, color = "on_surface/0.5" }),
      ui.label({ text = tr("trash.none"), color = "on_surface/0.7" }),
    }))
  else
    for i, item in ipairs(trashItems) do
      table.insert(children, trashRow(item, i))
    end
  end
  return children
end

-- Settings tab --------------------------------------------------------------

local function loadDrafts()
  local c = core.config()
  drafts = {
    root = tostring(c.root or ""),
    prefix = tostring(c.prefix or ""),
    interval_min = tostring(c.interval_min or 5),
    trash_days = tostring(c.trash_days or 30),
  }
  for _, r in ipairs(remotes()) do
    drafts["label." .. r] = core.label(c, r)
  end
  settingsRev += 1
end

local function saveSettings()
  local c = core.config()
  local current = {
    root = tostring(c.root or ""),
    prefix = tostring(c.prefix or ""),
    interval_min = tostring(c.interval_min or 5),
    trash_days = tostring(c.trash_days or 30),
  }
  for _, r in ipairs(remotes()) do
    current["label." .. r] = core.label(c, r)
  end
  local changes = {}
  for k, v in pairs(drafts) do
    if current[k] ~= v then
      table.insert(changes, { k, v })
    end
  end
  if #changes == 0 then
    return
  end
  busy = tr("settings.saving")
  render()
  local function step(i)
    if i > #changes then
      busy = nil
      noctalia.notify(tr("title"), tr("settings.saved"))
      loadDrafts()
      render()
      return
    end
    core.run({ "config", "set", changes[i][1], changes[i][2] }, function(result)
      if result.exitCode ~= 0 then
        busy = nil
        fail(result, tr("settings.save_failed", { key = changes[i][1] }))
        loadDrafts()
        render()
        return
      end
      step(i + 1)
    end, 30000)
  end
  step(1)
end

local function field(key, labelText, hint)
  local parts = {
    ui.label({ text = labelText }),
    ui.input({
      key = "input-" .. key .. "-" .. settingsRev,
      value = drafts[key] or "",
      controlSize = "sm",
      onChange = function(v)
        drafts[key] = v or ""
      end,
    }),
  }
  if hint then
    table.insert(parts, dim(hint))
  end
  return ui.column({ key = "field-" .. key, gap = 3 }, parts)
end

local function settingsBody()
  local children = {}
  local prefix = string.gsub(drafts.prefix or "", "{host}", host())
  if string.match(prefix, "%w$") then
    prefix ..= " "
  end
  local example = (drafts.root or "") .. "/" .. prefix .. "Documents"

  table.insert(children, sectionTitle(tr("settings.section_drive")))
  table.insert(children, field("root", tr("settings.root")))
  table.insert(children, field("prefix", tr("settings.prefix"), tr("settings.prefix_hint")))
  table.insert(children, dim(tr("settings.example", { path = example })))
  table.insert(children, dim(tr("settings.applies_to_new")))

  table.insert(children, ui.separator({ spacing = 4 }))
  table.insert(children, sectionTitle(tr("settings.section_sync")))
  table.insert(children, ui.row({ gap = 10 }, {
    ui.column({ flexGrow = 1 }, { field("interval_min", tr("settings.interval")) }),
    ui.column({ flexGrow = 1 }, { field("trash_days", tr("settings.trash_days")) }),
  }))

  if #remotes() > 0 then
    table.insert(children, ui.separator({ spacing = 4 }))
    table.insert(children, sectionTitle(tr("settings.section_accounts")))
    for _, r in ipairs(remotes()) do
      table.insert(children, field("label." .. r, tr("settings.account_label", { remote = r })))
    end
  end

  table.insert(children, ui.row({ gap = 6, justify = "end" }, {
    ui.button({ text = tr("settings.reset"), variant = "ghost", controlSize = "sm", onClick = function()
      loadDrafts()
      render()
    end }),
    ui.button({ text = tr("settings.save"), glyph = "check", variant = "primary", controlSize = "sm", enabled = busy == nil, onClick = saveSettings }),
  }))

  table.insert(children, ui.separator({ spacing = 4 }))
  table.insert(children, sectionTitle(tr("settings.section_maintenance")))
  table.insert(children, ui.row({ gap = 6, align = "center" }, {
    ui.button({ text = tr("settings.resync"), glyph = "refresh", variant = "outline", controlSize = "sm", onClick = function()
      core.detach({ "resync" })
    end }),
    dim(tr("settings.resync_hint"), { flexGrow = 1 }),
  }))
  table.insert(children, ui.row({ gap = 6, align = "center" }, {
    ui.button({ text = tr("settings.reinstall"), glyph = "tool", variant = "outline", controlSize = "sm", enabled = busy == nil, onClick = function()
      install(nil)
    end }),
    confirmButton("uninstall", { text = tr("settings.uninstall"), glyph = "trash", controlSize = "sm" }, function()
      core.run({ "uninstall" }, function(result)
        if result.exitCode ~= 0 then
          fail(result, tr("settings.uninstall_failed"))
        end
        loadDoctor()
      end, 60000)
    end),
    ui.spacer({ flexGrow = 1 }),
    dim("v" .. tostring(doctor and doctor.version or "?")),
  }))
  table.insert(children, dim(tr("settings.uninstall_hint")))
  return children
end

-- Frame ---------------------------------------------------------------------

local function setTab(name)
  tab = name
  confirmKey = nil
  if name == "trash" then
    loadTrash()
  elseif name == "settings" then
    loadDrafts()
  end
  render()
end

local function tabButton(name, glyph)
  return ui.button({
    text = tr("tab." .. name),
    glyph = glyph,
    variant = tab == name and "primary" or "ghost",
    controlSize = "sm",
    onClick = function()
      setTab(name)
    end,
  })
end

render = function()
  local folders = core.folders()
  local status = core.status()
  local state = core.summary(folders, status)

  local statusText = ""
  if busy then
    statusText = busy
  elseif state == "running" then
    statusText = tr("folders.syncing")
  elseif state == "ok" then
    statusText = tr("header.ok", { ago = core.ago(status.last_run) })
  elseif state == "error" then
    statusText = tr("header.error")
  end

  local header = ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = "brand-google-drive", size = 20, color = "primary" }),
    ui.column({ flexGrow = 1, gap = 0 }, {
      ui.label({ text = tr("title"), fontSize = 16, fontWeight = "bold" }),
      ui.label({ text = statusText, fontSize = 12, color = state == "error" and "error" or "on_surface/0.65", maxLines = 1 }),
    }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = tr("sync_all"), enabled = state ~= "running" and #folders > 0, onClick = function()
      core.detach({ "run" })
    end }),
    ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = tr("close"), onClick = function()
      panel.close()
    end }),
  })

  local body
  local tabs = nil
  if doctor == nil then
    body = { dim(tr("loading")) }
  elseif needsSetup() then
    body = setupBody()
  else
    tabs = ui.row({ gap = 4 }, {
      tabButton("folders", "folder"),
      tabButton("trash", "trash"),
      tabButton("settings", "settings"),
    })
    if tab == "trash" then
      body = trashBody()
    elseif tab == "settings" then
      body = settingsBody()
    else
      body = foldersBody()
    end
  end

  local rows = { header }
  if tabs then
    table.insert(rows, tabs)
  end
  table.insert(rows, ui.scroll({ key = "body-" .. tab, flexGrow = 1, gap = 8 }, body))

  panel.render(ui.column({ key = "root-" .. openRev, gap = 10, flexGrow = 1 }, rows))
end

-- Entry points --------------------------------------------------------------

function onOpen(context)
  openRev += 1
  confirmKey = nil
  if context == "trash" or context == "settings" or context == "folders" then
    tab = context
  end
  lastStatusRaw = nil
  panel.setWantsSecondTicks(true)
  render()
  loadDoctor()
  if tab == "trash" then
    loadTrash()
  elseif tab == "settings" then
    loadDrafts()
  end
end

function onClose()
  panel.setWantsSecondTicks(false)
  confirmKey = nil
end

-- Called every second while open: re-render when a sync changed the status.
function update()
  local raw = (noctalia.fileExists(core.STATUS) and noctalia.readFile(core.STATUS)) or ""
  local folders = (noctalia.fileExists(core.FOLDERS) and noctalia.readFile(core.FOLDERS)) or ""
  local key = raw .. "\0" .. folders
  if key ~= lastStatusRaw then
    lastStatusRaw = key
    render()
  end
end

-- `noctalia msg plugin augussst/gdrive-sync:panel all tab trash`
function onIpc(event, payload)
  if event == "tab" and (payload == "folders" or payload == "trash" or payload == "settings") then
    setTab(payload)
  end
end
