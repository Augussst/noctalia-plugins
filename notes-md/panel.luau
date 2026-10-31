--!nonstrict
-- Markdown notes in a full-height side panel.
--
-- Notes are plain .md files in the configured notes directory. The panel shows
-- a note list and, per note, an interactive preview (default) or a multiline
-- editor with idle autosave (flushes after a short pause in typing, on
-- navigation, and on panel close). The preview itself lives in preview.luau.
--
-- Based on the official noctalia/notes plugin (MIT).

local AUTOSAVE_IDLE_TICKS = 2 -- 1s panel ticks with no edits before a flush
local SCRATCHPAD_BASE = "scratchpad"

local dirs = require("./dirs.luau")
local preview = require("./preview.luau")

local COPIED_TICKS = 2 -- seconds the "copied" check stays on a code block

local notesDir = ""
local suffix = ".md" -- "." .. the configured extension, resolved in onOpen
local files = {}
local view = "list" -- "list" | "editor"
local editorMode = "preview" -- "preview" | "edit"
local copiedKey = nil -- code block whose copy button shows a check
local copiedTicks = 0
local suggestFor = nil -- the "[[partial" being typed at the end of the note, or nil
local current = nil -- filename ("foo.md") while the editor is open
local buffer = ""
local loadedContent = "" -- what the file held when we last read/wrote it
local editorRev = 0 -- bumped to reseed the editor input after external changes
local dirty = false
local idleTicks = 0
local pendingDelete = nil -- filename awaiting the second (confirm) click
local sortMode = "name" -- "custom" (dragged order) | "name" | "date"
local customOrder = {} -- filenames in dragged order; persisted next to the notes
local DRAG_TYPE = "notes-md-note"
local pins = {} -- filename -> true; persisted in a sidecar next to the notes
local hoveredKey = nil
local cornerRadiusScale = 1.0
local closeButton = true

local render

local function tr(key)
  return noctalia.tr(key)
end

-- For strings added by this plugin: other languages fall back to English.
local function tx(key, fallback)
  local text = noctalia.tr(key)
  if type(text) ~= "string" or text == "" or text == key then
    return fallback
  end
  return text
end

local function displayName(file)
  return file:sub(1, #file - #suffix)
end

local function hasSuffix(name)
  return #name > #suffix and name:sub(-#suffix) == suffix
end

local function notePath(file)
  return notesDir .. "/" .. file
end

local function scratchName()
  return SCRATCHPAD_BASE .. suffix
end

-- Pins live in a hidden sidecar inside the notes directory so they sync and
-- survive restarts with the notes themselves.
local function pinsPath()
  return notesDir .. "/.pinned.json"
end

local function loadPins()
  pins = {}
  local raw = noctalia.readFile(pinsPath())
  if raw ~= nil then
    local decoded = noctalia.json.decode(raw)
    if type(decoded) == "table" then
      for name, value in pairs(decoded) do
        if type(name) == "string" and value == true then
          pins[name] = true
        end
      end
    end
  end
end

local function savePins()
  local encoded = noctalia.json.encode(pins)
  if encoded == nil then
    return
  end
  local ok, err = noctalia.writeFile(pinsPath(), encoded)
  if not ok then
    noctalia.notifyError(tr("title"), err or "")
  end
end

-- The dragged order lives in a hidden sidecar like the pins, so it syncs with
-- the notes. Its presence also makes "custom" the default sort.
local function orderPath()
  return notesDir .. "/.order.json"
end

local function loadOrder()
  customOrder = {}
  local raw = noctalia.readFile(orderPath())
  if raw ~= nil then
    local decoded = noctalia.json.decode(raw)
    if type(decoded) == "table" then
      for _, name in ipairs(decoded) do
        if type(name) == "string" then
          table.insert(customOrder, name)
        end
      end
    end
  end
  if #customOrder > 0 then
    sortMode = "custom"
  end
end

local function saveOrder()
  local encoded = noctalia.json.encode(customOrder)
  if encoded == nil then
    return
  end
  local ok, err = noctalia.writeFile(orderPath(), encoded)
  if not ok then
    noctalia.notifyError(tr("title"), err or "")
  end
end

local function renameInOrder(from, to)
  for i, name in ipairs(customOrder) do
    if name == from then
      if to == nil then
        table.remove(customOrder, i)
      else
        customOrder[i] = to
      end
      saveOrder()
      return
    end
  end
end

local function refreshFiles()
  files = {}
  local list = noctalia.listDir(notesDir)
  if list ~= nil then
    for _, name in ipairs(list) do
      if hasSuffix(name) and name ~= scratchName() and name:sub(1, 1) ~= "." then
        table.insert(files, name)
      end
    end
  end
  -- Pinned notes first, then the selected order within each group.
  local mtimes = {}
  local rank = {}
  for i, name in ipairs(customOrder) do
    rank[name] = i
  end
  if sortMode == "date" then
    for _, name in ipairs(files) do
      local info = noctalia.fileInfo(notePath(name))
      mtimes[name] = info ~= nil and info.mtime or 0
    end
  end
  table.sort(files, function(a, b)
    local aPinned = pins[a] == true
    local bPinned = pins[b] == true
    if aPinned ~= bPinned then
      return aPinned
    end
    if sortMode == "date" and mtimes[a] ~= mtimes[b] then
      return mtimes[a] > mtimes[b]
    end
    if sortMode == "custom" then
      -- Notes never dragged yet come after the ordered ones, by name.
      local ra, rb = rank[a] or math.huge, rank[b] or math.huge
      if ra ~= rb then
        return ra < rb
      end
    end
    return a < b
  end)
end

local function flush()
  if not dirty or current == nil then
    return
  end
  local ok, err = noctalia.writeFile(notePath(current), buffer)
  if not ok then
    noctalia.notifyError(tr("title"), err or tr("save_failed"))
    return
  end
  loadedContent = buffer
  dirty = false
end

local function openNote(file)
  flush()
  local contents = noctalia.readFile(notePath(file))
  buffer = contents or ""
  loadedContent = buffer
  current = file
  suggestFor = nil
  view = "editor"
  -- Notes with content open in the preview; empty ones go straight to editing.
  editorMode = (buffer:match("%S") ~= nil) and "preview" or "edit"
  dirty = false
  idleTicks = 0
  pendingDelete = nil
  render()
end

local function deleteNote(file)
  local ok, err = noctalia.removeFile(notePath(file))
  if not ok then
    noctalia.notifyError(tr("title"), err or "")
  end
  if pins[file] ~= nil then
    pins[file] = nil
    savePins()
  end
  renameInOrder(file, nil)
  if current == file then
    current = nil
    buffer = ""
    dirty = false
    view = "list"
  end
  pendingDelete = nil
  refreshFiles()
  render()
end

local function uniqueNoteName()
  local base = noctalia.formatTime("%Y-%m-%d %H.%M.%S")
  local name = base .. suffix
  local counter = 2
  while noctalia.fileExists(notePath(name)) do
    name = base .. " (" .. counter .. ")" .. suffix
    counter += 1
  end
  return name
end

local function deleteControls(file)
  return {
    ui.label({ text = tr("confirm_delete"), color = "error" }),
    ui.button({
      glyph = "check",
      variant = "primary",
      onClick = function()
        deleteNote(file)
      end,
    }),
    ui.button({
      glyph = "close",
      variant = "ghost",
      onClick = function()
        pendingDelete = nil
        render()
      end,
    }),
  }
end

local function togglePin(file)
  pins[file] = not pins[file] and true or nil
  savePins()
  refreshFiles()
  render()
end

local function listRow(file)
  local pinned = pins[file] == true
  local isHovered = hoveredKey == file
  -- Label elides natively with maxLines=1; the row wrapper supplies the click target.
  local titleChildren = {
    ui.label({
      text = displayName(file),
      maxLines = 1,
      flexGrow = 1,
      color = isHovered and "surface" or "on_surface",
    }),
  }
  -- Pinned notes stay on top in pin order, so they get a pin where unpinned
  -- notes have their drag grip.
  local handle
  if pinned then
    handle = ui.row({
      key = "pin-slot-" .. file,
      width = 18,
      height = 28,
      align = "center",
      justify = "center",
      tooltip = tx("pinned_no_drag", "Pinned notes stay on top"),
    }, {
      ui.glyph({ name = "pinned", size = 13, color = "on_surface_variant" }),
    })
  else
    handle = ui.dragSource({
      key = "grip-" .. file,
      dragType = DRAG_TYPE,
      payload = file,
      previewAncestor = 1, -- the drag ghost shows the whole row
      liftFromLayout = true, -- the row leaves the list while dragged
      width = 18,
      height = 28,
      align = "center",
      justify = "center",
      tooltip = tx("drag_to_reorder", "Drag to reorder"),
    }, {
      ui.glyph({ name = "menu-2", size = 13, color = "on_surface_variant" }),
    })
  end
  local children = {
    handle,
    ui.row({
      key = file,
      flexGrow = 1,
      gap = 6,
      align = "center",
      padding = 8,
      paddingH = 12,
      fill = isHovered and "tertiary" or "surface",
      radius = 6 * cornerRadiusScale,
      onHover = "onRowHover",
      onClick = function()
        openNote(file)
      end,
    }, titleChildren),
  }
  if pendingDelete == file then
    for _, node in ipairs(deleteControls(file)) do
      table.insert(children, node)
    end
  else
    table.insert(children, ui.button({
      glyph = pinned and "pinned-off" or "pin",
      variant = "ghost",
      onClick = function()
        togglePin(file)
      end,
    }))
    table.insert(children, ui.button({
      glyph = "trash",
      variant = "ghost",
      onClick = function()
        pendingDelete = file
        render()
      end,
    }))
  end
  -- Pin state is part of the key: retained buttons keep a previously set
  -- glyph, so the row is recreated when it flips.
  return ui.row({ key = "note-" .. file .. (pinned and "-pinned" or ""), gap = 6, align = "center" }, children)
end

local function listView()
  local scratchFile = scratchName()
  local isHovered = hoveredKey == scratchFile
  local rows = {
    -- The scratchpad is always present (created on first write) and not deletable from here.
    ui.row({ key = "scratchpad", gap = 6, align = "center" }, {
      -- The scratchpad is always on top: a pin in the grip slot, like pinned notes.
      ui.row({ width = 18, height = 28, align = "center", justify = "center" }, {
        ui.glyph({ name = "pinned", size = 13, color = "on_surface_variant" }),
      }),
      ui.row({
        key = scratchFile,
        flexGrow = 1,
        gap = 6,
        align = "center",
        padding = 8,
        paddingH = 12,
        fill = isHovered and "tertiary" or "surface",
        radius = 6 * cornerRadiusScale,
        onHover = "onRowHover",
        onClick = "onOpenScratchpad",
      }, {
        ui.label({
            text = tr("scratchpad"),
            maxLines = 1,
            flexGrow = 1,
            color = isHovered and "surface" or "on_surface",
          }),
      }),
    }),
  }
  -- Thin drop zones between the rows: dropping a note on zone i puts it at
  -- position i. They grow while a note is dragged over them.
  local function dropZone(index)
    return ui.dropZone({
      key = "drop-" .. index,
      accepts = { DRAG_TYPE },
      value = tostring(index),
      onDrop = "onNoteDropped",
      height = 2,
      radius = 6,
      expandOnDrag = true,
      hitSlop = 20,
    })
  end
  -- Only among unpinned notes: pinned ones are not reorderable.
  local unpinned = 0
  for i, file in ipairs(files) do
    if pins[file] ~= true then
      unpinned += 1
      table.insert(rows, dropZone(i))
    end
    table.insert(rows, listRow(file))
  end
  if unpinned > 0 then
    table.insert(rows, dropZone(#files + 1))
  end
  if #files == 0 then
    table.insert(rows, ui.label({ text = tr("empty"), color = "on_surface_variant" }))
  end
  return ui.scroll({ flexGrow = 1, gap = 4 }, rows)
end

local function editorStatusLine()
  local words = select(2, buffer:gsub("%S+", ""))
  local chars = utf8.len(buffer) or #buffer
  local status = dirty and tr("editing") or tr("saved")
  return status .. "  ·  " .. noctalia.tr("counts", { words = words, chars = chars })
end

local function editorHeader()
  local trailing
  if pendingDelete == current then
    trailing = deleteControls(current, "noteEditorDelete", 0)
  else
    trailing = {
      ui.button({ glyph = "trash", variant = "ghost", onClick = "onEditorDelete" }),
    }
  end
  local children = {
    ui.button({ glyph = "arrow-left", variant = "ghost", onClick = "onBack" }),
    ui.input({
      key = "rename-" .. current,
      value = displayName(current),
      onSubmit = "onRename",
      -- The scratchpad's identity is its name; renaming it would just respawn it.
      enabled = current ~= scratchName(),
      flexGrow = 1,
    }),
  }
  -- Keyed by mode: retained buttons keep a previously set glyph.
  table.insert(children, ui.button({
    key = "mode-" .. editorMode,
    glyph = editorMode == "preview" and "pencil" or "eye",
    variant = "ghost",
    tooltip = editorMode == "preview" and tx("edit", "Edit") or tx("preview", "Preview"),
    onClick = "onToggleEditorMode",
  }))
  for _, node in ipairs(trailing) do
    table.insert(children, node)
  end
  return ui.row({ gap = 6, align = "center" }, children)
end

-- ── Preview actions ──────────────────────────────────────────────────────────

local function toggleTask(lineIndex)
  local lines = preview.splitLines(buffer)
  if lines[lineIndex] == nil then
    return
  end
  -- A trailing newline shows up as a final empty entry; concat restores it.
  lines[lineIndex] = preview.toggleTaskLine(lines[lineIndex])
  buffer = table.concat(lines, "\n")
  dirty = true
  idleTicks = 0
  flush()
  editorRev += 1
  render()
end

-- "~/x", "/abs/x" or a path relative to the notes folder; %20 becomes a space.
local function resolveLocal(target)
  local path = target:gsub("^file://", ""):gsub("%%20", " ")
  if path:sub(1, 1) == "~" then
    return noctalia.expandPath(path)
  end
  if path:sub(1, 1) == "/" then
    return path
  end
  return notesDir .. "/" .. path:gsub("^%./", "")
end

-- "Name", "Name.md" -> "Name.md", or nil for an unusable name.
local function noteFile(name)
  local base = name:gsub("/", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if hasSuffix(base) then
    base = displayName(base)
  end
  if base == "" then
    return nil
  end
  return base .. suffix
end

local function noteExists(name)
  local file = noteFile(name)
  return file ~= nil and noctalia.fileExists(notePath(file))
end

-- Links never create notes: a typo in a link should not leave an empty note
-- behind. The preview only shows links to notes that exist.
local function openNoteByName(name)
  local file = noteFile(name)
  if file == nil or not noctalia.fileExists(notePath(file)) then
    noctalia.notifyError(tr("title"), tx("note_missing", "Note not found") .. ": " .. name)
    return
  end
  openNote(file)
end

local function openLink(target)
  if target:match("^#") then
    return -- in-page anchors have nowhere to go
  end
  if target:match("^[%a][%w+.-]*:") and not target:match("^file:") then
    noctalia.runAsync({ "xdg-open", target })
    return
  end
  local path = resolveLocal(target)
  -- A link to another note opens it here instead of in an external editor.
  local dir = notesDir .. "/"
  if hasSuffix(path) and path:sub(1, #dir) == dir and not path:sub(#dir + 1):find("/", 1, true) then
    openNoteByName(path:sub(#dir + 1))
    return
  end
  noctalia.runAsync({ "xdg-open", path })
end

local function copyCode(key, text)
  noctalia.copyToClipboard(text, "text/plain;charset=utf-8")
  copiedKey = key
  copiedTicks = COPIED_TICKS
  render()
end

local function resolveImage(target)
  if target:match("^https?://") then
    return nil, "remote"
  end
  local path = resolveLocal(target)
  if not noctalia.fileExists(path) then
    return nil, "missing"
  end
  return path
end

local function previewView()
  local children = preview.render(buffer, {
    keyPrefix = "pv-" .. current .. "-" .. editorRev,
    copiedKey = copiedKey,
    tr = tx,
    onToggleTask = toggleTask,
    onOpenLink = openLink,
    onOpenNote = openNoteByName,
    noteExists = noteExists,
    onCopy = copyCode,
    resolveImage = resolveImage,
  })
  if #children == 0 then
    children = { ui.label({ text = tr("editor_placeholder"), color = "on_surface_variant" }) }
  end
  -- Children go straight into the scroll with no padding, like Noctalia's own
  -- plugin store: with viewport padding the Markdown view measured its wrapped
  -- text at the wrong width and the next block overlapped it.
  return ui.scroll({
    key = "preview-scroll-" .. current,
    flexGrow = 1,
    gap = 6,
    align = "stretch",
  }, children)
end

-- Notes whose name contains the typed text (case-insensitive), at most 6.
local function suggestions(partial)
  local wanted = partial:lower()
  local found = {}
  local candidates = { scratchName() }
  for _, file in ipairs(files) do
    table.insert(candidates, file)
  end
  for _, file in ipairs(candidates) do
    local name = displayName(file)
    if file ~= current and name:lower():find(wanted, 1, true) then
      table.insert(found, name)
      if #found >= 6 then
        break
      end
    end
  end
  return found
end

local function completeNoteLink(name)
  if suggestFor == nil then
    return
  end
  buffer = buffer:sub(1, #buffer - #suggestFor) .. name .. "]] "
  suggestFor = nil
  dirty = true
  idleTicks = 0
  editorRev += 1 -- reseed the editor with the completed text
  render()
end

local function suggestionRow()
  local names = suggestions(suggestFor)
  if #names == 0 then
    return ui.label({
      text = tx("no_matching_notes", "No matching notes"),
      fontSize = 11,
      color = "on_surface_variant",
    })
  end
  local chips = {}
  for _, name in ipairs(names) do
    table.insert(chips, ui.row({
      key = "suggest-" .. name,
      gap = 6,
      align = "center",
      paddingV = 3,
      paddingH = 8,
      radius = 6,
      fill = "surface_container",
      onClick = function()
        completeNoteLink(name)
      end,
    }, {
      ui.glyph({ name = "notes", size = 13, color = "primary" }),
      ui.label({ text = name, maxLines = 1, flexGrow = 1, fontSize = 12, color = "primary" }),
    }))
  end
  return ui.column({ key = "suggestions", gap = 4, align = "stretch" }, chips)
end

local function editorView()
  local content
  if editorMode == "preview" then
    content = previewView()
  else
    content = ui.input({
      -- The rev reseeds the (uncontrolled) editor when the file changed under us.
      key = "editor-" .. current .. "-" .. editorRev,
      value = buffer,
      multiline = true,
      focus = true,
      flexGrow = 1,
      placeholder = tr("editor_placeholder"),
      onChange = "onEdited",
      onSubmit = "onFlushNow",
    })
  end
  local children = { editorHeader(), content }
  if editorMode == "edit" and suggestFor ~= nil then
    table.insert(children, suggestionRow())
  end
  table.insert(children, ui.label({
    text = editorStatusLine(),
    fontSize = 11,
    color = "on_surface_variant",
  }))
  return ui.column({ flexGrow = 1, gap = 8, align = "stretch" }, children)
end

render = function()
  local isEditor = view == "editor" and current ~= nil
  local header = {
    ui.label({ text = tr("title"), fontSize = 16, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
  }
  if not isEditor then
    local sortGlyph = { custom = "list-numbers", name = "sort-ascending-letters", date = "history" }
    local sortTip = {
      custom = tx("sort_custom", "Your order (drag notes)"),
      name = tx("sort_name", "By name"),
      date = tx("sort_date", "By last change"),
    }
    table.insert(header, ui.button({
      key = "header-sort-" .. sortMode,
      glyph = sortGlyph[sortMode],
      variant = "ghost",
      tooltip = sortTip[sortMode],
      onClick = "onToggleSort",
    }))
  end
  table.insert(header, ui.button({ key = "header-new", glyph = "plus", variant = "primary", onClick = "onNewNote" }))
  if closeButton then
    table.insert(header, ui.button({ key = "header-close", glyph = "close", variant = "ghost", onClick = "onClosePanel" }))
  end
  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, {
    ui.row({ align = "center", gap = 8 }, header),
    isEditor and editorView() or listView(),
  }))
end

function onOpen(_context)
  notesDir = dirs.resolveNotesDir()
  cornerRadiusScale = noctalia.getSetting("shell.corner_radius_scale")
  closeButton = noctalia.getSetting("shell.show_close_buttons") ~= false
  local extension = noctalia.string.trim(noctalia.getConfig("extension")):gsub("^%.", "")
  if extension == "" then
    noctalia.notifyError(tr("title"), tr("bad_extension"))
    extension = "md"
  end
  suffix = "." .. extension
  -- A note left open under a different extension setting no longer matches.
  if current ~= nil and not hasSuffix(current) then
    current = nil
    buffer = ""
    dirty = false
    view = "list"
  end
  local ok, err = noctalia.mkdirAll(notesDir)
  if not ok then
    noctalia.notifyError(tr("title"), err or "")
  end
  loadPins()
  loadOrder()
  refreshFiles()
  pendingDelete = nil
  panel.setWantsSecondTicks(true)
  -- The launcher entry hands over a target through the shared state: either
  -- the note list ("open_home") or a specific note ("open_note").
  if noctalia.state.get("open_home") == true then
    noctalia.state.set("open_home", false)
    flush()
    view = "list"
    current = nil
    buffer = ""
    dirty = false
    render()
    return
  end
  local target = noctalia.state.get("open_note")
  if type(target) == "string" and target ~= "" then
    noctalia.state.set("open_note", "")
    openNote(target)
    return
  end
  render()
end

function onOpenScratchpad()
  openNote(scratchName())
end

function onClose()
  flush()
end

function update()
  if copiedTicks > 0 then
    copiedTicks -= 1
    if copiedTicks == 0 then
      copiedKey = nil
      render()
    end
  end
  if dirty then
    idleTicks += 1
    if idleTicks >= AUTOSAVE_IDLE_TICKS then
      flush()
      render()
    end
  end
end

-- Pressing Enter at the end of a list item starts the next item; Enter on an
-- empty item ends the list. Only at the very end of the note: the editor does
-- not tell plugins where the cursor is, and reseeding it mid-text would move
-- the cursor.
local function continueList(oldText, newText)
  if newText ~= oldText .. "\n" then
    return nil
  end
  -- Not inside an open code fence.
  local fences = 0
  for _ in ("\n" .. oldText):gmatch("\n%s*```") do
    fences += 1
  end
  if fences % 2 == 1 then
    return nil
  end
  local last = oldText:match("([^\n]*)$") or ""
  local indent, marker, rest = last:match("^(%s*)([%-%*%+]%s+%[[ xX]%])%s*(.*)$")
  local nextMarker
  if indent ~= nil then
    nextMarker = marker:gsub("%[[xX]%]", "[ ]")
  else
    local num, sep
    indent, num, sep, rest = last:match("^(%s*)(%d+)([%.%)])%s+(.*)$")
    if indent ~= nil then
      local box = rest:match("^%[[ xX]%]%s*")
      nextMarker = tostring(tonumber(num) + 1) .. sep .. (box and " [ ]" or "")
      if box then
        rest = rest:sub(#box + 1)
      end
    else
      indent, marker, rest = last:match("^(%s*)([%-%*%+])%s+(.*)$")
      nextMarker = marker
    end
  end
  if indent == nil then
    return nil
  end
  if not rest:match("%S") then
    -- Enter on an empty item: drop the marker and end the list.
    return oldText:sub(1, #oldText - #last) .. "\n"
  end
  return newText .. indent .. nextMarker .. " "
end

function onEdited(value)
  local continued = continueList(buffer, value)
  buffer = continued or value
  idleTicks = 0
  dirty = true
  -- Typing "[[" at the end of the note lists matching notes under the editor.
  local partial = buffer:match("%[%[([^%[%]\n]*)$")
  local suggestChanged = partial ~= suggestFor
  suggestFor = partial
  if continued then
    -- Reseed the editor so it shows the inserted marker.
    editorRev += 1
    render()
  elseif suggestChanged then
    render()
  end
  -- Otherwise no re-render per keystroke: it keeps typing and scrolling smooth.
  -- The status line's counts catch up on the autosave render.
end

function onToggleEditorMode()
  if editorMode == "preview" then
    editorMode = "edit"
  else
    flush()
    editorMode = "preview"
  end
  render()
end

-- custom -> name -> date -> custom
function onToggleSort()
  if sortMode == "custom" then
    sortMode = "name"
  elseif sortMode == "name" then
    sortMode = "date"
  else
    sortMode = "custom"
  end
  refreshFiles()
  render()
end

-- payload: the dragged filename; value: the position it was dropped at.
function onNoteDropped(payload, value)
  local insertAt = tonumber(value)
  if type(payload) ~= "string" or insertAt == nil or pins[payload] == true then
    return
  end
  -- Start from what is on screen, so the drop lands where it was seen.
  local order = {}
  local fromIdx = nil
  for i, file in ipairs(files) do
    table.insert(order, file)
    if file == payload then
      fromIdx = i
    end
  end
  if fromIdx == nil then
    return
  end
  table.remove(order, fromIdx)
  if fromIdx < insertAt then
    insertAt -= 1
  end
  local firstUnpinned = 1
  while order[firstUnpinned] ~= nil and pins[order[firstUnpinned]] == true do
    firstUnpinned += 1
  end
  insertAt = math.max(firstUnpinned, math.min(insertAt, #order + 1))
  table.insert(order, insertAt, payload)
  customOrder = order
  saveOrder()
  sortMode = "custom"
  refreshFiles()
  render()
end

-- noctalia msg plugin augussst/notes-md:panel all open "Note name"
-- (the panel must be open). "list" goes back to the note list.
function onIpc(event, payload)
  if event == "open" and type(payload) == "string" and payload ~= "" then
    openNoteByName(payload)
  elseif event == "list" then
    onBack()
  end
end

function onFlushNow(value)
  buffer = value
  dirty = true
  flush()
  render()
end

function onNewNote()
  flush()
  local name = uniqueNoteName()
  local ok, err = noctalia.writeFile(notePath(name), "")
  if not ok then
    noctalia.notifyError(tr("title"), err or tr("save_failed"))
    return
  end
  refreshFiles()
  openNote(name)
end

function onRename(value)
  if current == nil then
    return
  end
  local name = noctalia.string.trim(value):gsub("/", "")
  if name == "" or name == displayName(current) then
    render()
    return
  end
  local target = name .. suffix
  if noctalia.fileExists(notePath(target)) then
    noctalia.notifyError(tr("title"), tr("rename_exists"))
    render()
    return
  end
  flush()
  local ok, err = noctalia.renameFile(notePath(current), notePath(target))
  if not ok then
    noctalia.notifyError(tr("title"), err or "")
    render()
    return
  end
  if pins[current] ~= nil then
    pins[current] = nil
    pins[target] = true
    savePins()
  end
  renameInOrder(current, target)
  current = target
  refreshFiles()
  render()
end

function onEditorDelete()
  pendingDelete = current
  render()
end

function onBack()
  flush()
  view = "list"
  current = nil
  buffer = ""
  pendingDelete = nil
  refreshFiles()
  render()
end

function onClosePanel()
  panel.close()
end

function onRowHover(state, key)
  hoveredKey = (state == "true") and key or nil
  render()
end

-- The launcher entry bumps "notes_bump" after writing note files (quick-capture
-- appends, new notes). Fold external changes into the open editor: an appended
-- tail is grafted onto whatever is being typed; other divergence only replaces
-- the buffer when there are no unsaved edits.
local function onExternalChange()
  if notesDir == "" then
    return -- never opened; nothing resolved yet
  end
  refreshFiles()
  if current ~= nil then
    local contents = noctalia.readFile(notePath(current)) or ""
    if contents ~= loadedContent then
      if contents:sub(1, #loadedContent) == loadedContent then
        buffer = buffer .. contents:sub(#loadedContent + 1)
      elseif not dirty then
        buffer = contents
      end
      loadedContent = contents
      dirty = buffer ~= loadedContent
      idleTicks = 0
      editorRev += 1
    end
  end
  render()
end

noctalia.state.watch("notes_bump", function(_value)
  onExternalChange()
end)
