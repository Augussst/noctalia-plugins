--!nonstrict
-- Global launcher search: only the hub's own items (and the hub itself).
-- Its prefix, `/hubs`, does the same thing.

local provider = require("./provider.luau")

function onQuery(query)
  if noctalia.string.trim(query) == "" then
    launcher.setResults(query, {})
    return
  end
  provider.query(query, false)
end

function onActivate(id)
  provider.activate(id)
end
