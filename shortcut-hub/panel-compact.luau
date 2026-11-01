--!nonstrict
-- Hub panel, compact size. The logic is in hub.luau.

local hub = require("./hub.luau")
hub.setup("compact")

function onOpen(context)
  hub.onOpen(context)
end

function onClose()
  hub.onClose()
end

function onIpc(event, payload)
  hub.onIpc(event, payload)
end
