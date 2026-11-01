--!nonstrict
-- Hub panel, wide size. The logic is in hub.luau.

local hub = require("./hub.luau")
hub.setup("wide")

function onOpen(context)
  hub.onOpen(context)
end

function onClose()
  hub.onClose()
end

function onIpc(event, payload)
  hub.onIpc(event, payload)
end
