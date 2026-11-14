--!nonstrict
-- Shared by the widget and the panel: runs bin/nirinit-ctl and reads its JSON.
-- All state lives in ~/.local/share/nirinit/ and is changed only by that
-- script, which is also what niri's autostart runs.

local M = {}

M.PANEL_ID = "augussst/nirinit-session:panel"
M.BIN = noctalia.pluginDir() .. "/bin/nirinit-ctl"

-- Runs `nirinit-ctl <args>` and calls `callback(result)`.
function M.run(args, callback, timeoutMs)
  local argv = { "python3", M.BIN }
  for _, a in ipairs(args) do
    table.insert(argv, a)
  end
  noctalia.runAsync(argv, function(result)
    if callback then
      callback(result)
    end
  end, timeoutMs or 15000)
end

-- Calls `callback(status)` with the decoded `status`, or nil if it failed.
function M.status(callback)
  M.run({ "status" }, function(result)
    local ok, value = pcall(function()
      return noctalia.json.decode(result.stdout or "")
    end)
    if result.exitCode == 0 and ok and type(value) == "table" then
      callback(value)
    else
      callback(nil)
    end
  end)
end

-- "org.kde.dolphin" -> "dolphin", "com.slack.Slack" -> "Slack".
function M.appName(appId)
  local last = string.match(appId or "", "([^.]+)$")
  return last or appId or "?"
end

function M.ago(t)
  t = tonumber(t)
  if t == nil or t <= 0 then
    return noctalia.tr("time.unknown")
  end
  local d = os.time() - t
  if d < 60 then
    return noctalia.tr("time.just_now")
  elseif d < 3600 then
    return noctalia.tr("time.minutes", { n = math.floor(d / 60) })
  elseif d < 86400 then
    return noctalia.tr("time.hours", { n = math.floor(d / 3600) })
  end
  return noctalia.tr("time.days", { n = math.floor(d / 86400) })
end

return M
