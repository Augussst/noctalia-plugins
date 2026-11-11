--!nonstrict
-- Shared helpers for the widget and the panel: file locations, reading the
-- JSON files the gdrive-sync script keeps, and running that script.
--
-- The plugin never edits those files itself: every change goes through
-- bin/gdrive-sync, which is also what the systemd timer and the Dolphin menus
-- run, so the three always agree.

local M = {}

M.PANEL_ID = "augussst/gdrive-sync:panel"

M.BIN = noctalia.pluginDir() .. "/bin/gdrive-sync"
M.CONFIG = noctalia.expandPath("~/.config/gdrive-sync/config.json")
M.FOLDERS = noctalia.expandPath("~/.config/gdrive-sync/folders.json")
M.STATUS = noctalia.expandPath("~/.cache/gdrive-sync/status.json")

local function readJson(path, fallback)
  if not noctalia.fileExists(path) then
    return fallback
  end
  local ok, value = pcall(function()
    return noctalia.json.decode(noctalia.readFile(path) or "")
  end)
  if ok and type(value) == "table" then
    return value
  end
  return fallback
end

function M.config()
  return readJson(M.CONFIG, {})
end

function M.folders()
  return readJson(M.FOLDERS, {})
end

function M.status()
  local s = readJson(M.STATUS, {})
  if type(s.folders) ~= "table" then
    s.folders = {}
  end
  return s
end

-- Display name of an rclone remote ("gdrive" → "Personal").
function M.label(config, remote)
  local accounts = config.accounts or {}
  local a = accounts[remote]
  if type(a) == "table" and type(a.label) == "string" and a.label ~= "" then
    return a.label
  end
  return remote
end

function M.basename(path)
  return string.match(path or "", "([^/]+)/*$") or path or ""
end

-- Runs the script and calls `callback(result)` with its output.
function M.run(args, callback, timeoutMs)
  local argv = { "bash", M.BIN }
  for _, a in ipairs(args) do
    table.insert(argv, a)
  end
  noctalia.runAsync(argv, function(result)
    if callback then
      callback(result)
    end
  end, timeoutMs or 60000)
end

-- Starts the script in the background and returns at once. Used for anything
-- that syncs, which can take minutes; progress shows up in status.json.
function M.detach(args)
  local argv = { "setsid", "-f", "bash", M.BIN }
  for _, a in ipairs(args) do
    table.insert(argv, a)
  end
  noctalia.runAsync(argv, nil, 5000)
end

function M.now()
  return os.time()
end

-- "just now", "5 min ago", "3 h ago", "2 days ago".
function M.ago(t)
  t = tonumber(t)
  if t == nil or t <= 0 then
    return noctalia.tr("time.never")
  end
  local d = M.now() - t
  if d < 60 then
    return noctalia.tr("time.just_now")
  elseif d < 3600 then
    return noctalia.tr("time.minutes", { n = math.floor(d / 60) })
  elseif d < 86400 then
    return noctalia.tr("time.hours", { n = math.floor(d / 3600) })
  end
  return noctalia.tr("time.days", { n = math.floor(d / 86400) })
end

-- Overall state for the bar icon: "running", "error", "ok" or "empty".
function M.summary(folders, status)
  if #folders == 0 then
    return "empty", nil
  end
  if type(status.running) == "string" and status.running ~= "" then
    return "running", status.running
  end
  for _, f in ipairs(folders) do
    local s = status.folders[f["local"]]
    if type(s) == "table" and s.ok == false then
      return "error", f
    end
  end
  return "ok", nil
end

return M
