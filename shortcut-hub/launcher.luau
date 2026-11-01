--!nonstrict
-- `/hub`: hub items, then every plugin panel and shell panel.

local provider = require("./provider.luau")

function onQuery(query)
  provider.query(query, true)
end

function onActivate(id)
  provider.activate(id)
end
