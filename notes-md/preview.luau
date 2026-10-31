--!nonstrict
-- Builds the interactive preview of a note.
--
-- Noctalia's ui.markdown renders headings, emphasis, code, lists, tables and
-- rules, but its links are not clickable and it skips task boxes, quotes and
-- images. So the note is split into blocks here: plain text goes to
-- ui.markdown in as large chunks as possible (so lists and tables stay whole),
-- and the interactive parts are built from rows and buttons:
--
--   - [ ] task        clickable checkbox, toggles the line in the file
--   ```code```        code block with a copy button
--   > quote           indented block with a bar on the left
--   [text](url)       a line with one link becomes clickable text; lines with
--                     several links (or links in tables/quotes) get chips
--   [[Note]]          the same, opening that note (only if it exists; a
--                     missing note stays plain text so typos stand out)
--   ![alt](path)      local image under its paragraph
--
-- Written in the subset shared by Lua 5.4 and Luau (no `+=`, no `continue`)
-- so the parser can be tested outside Noctalia with plain `lua`.

local M = {}

local IMAGE_WIDTH = 360
local IMAGE_HEIGHT = 220

-- ── Text helpers ─────────────────────────────────────────────────────────────

function M.splitLines(text)
  local lines = {}
  local pos = 1
  local len = #text
  while pos <= len do
    local nl = text:find("\n", pos, true)
    local line
    if nl then
      line = text:sub(pos, nl - 1)
      pos = nl + 1
    else
      line = text:sub(pos)
      pos = len + 1
    end
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end
    table.insert(lines, line)
  end
  -- A trailing newline means a final empty line.
  if len > 0 and text:sub(-1) == "\n" then
    table.insert(lines, "")
  end
  return lines
end

local function isDoneBox(box)
  return box == "x" or box == "X"
end

-- Task line: "- [ ] text", "* [x] text", "1. [ ] text" (any indent).
-- Returns indent, done, content; or nil when the line is not a task.
function M.parseTask(line)
  local indent, box, rest = line:match("^(%s*)[%-%*%+]%s+%[([ xX])%]%s?(.*)$")
  if indent == nil then
    indent, box, rest = line:match("^(%s*)%d+[%.%)]%s+%[([ xX])%]%s?(.*)$")
  end
  if indent == nil then
    return nil
  end
  return indent, isDoneBox(box), rest
end

-- Flip the box of a task line; returns the new line (unchanged if no task).
function M.toggleTaskLine(line)
  local head, box, tail = line:match("^(%s*[%-%*%+]%s+%[)([ xX])(%].*)$")
  if head == nil then
    head, box, tail = line:match("^(%s*%d+[%.%)]%s+%[)([ xX])(%].*)$")
  end
  if head == nil then
    return line
  end
  return head .. (isDoneBox(box) and " " or "x") .. tail
end

local function fenceOpen(line)
  local spaces, fence = line:match("^(%s*)(```+)")
  if fence == nil then
    spaces, fence = line:match("^(%s*)(~~~+)")
  end
  if fence == nil or #spaces > 3 then
    return nil
  end
  return fence
end

local function isFenceClose(line, fence)
  local spaces, run = line:match("^(%s*)([`~]+)%s*$")
  return run ~= nil and #spaces <= 3 and run:sub(1, 1) == fence:sub(1, 1) and #run >= #fence
end

local function isTableLine(line)
  return line:match("^%s*|") ~= nil
end

-- Markdown syntax stripped for a clickable line, which is drawn as a plain
-- label in the accent color (the Markdown view in Noctalia 5.4 does not show
-- bold, italic or link underlines, so it cannot mark a link itself).
function M.plainText(text)
  local t = text
  t = t:gsub("%[([^%]]*)%]%b()", "%1")
  t = t:gsub("^(%s*)[%-%*%+]%s+", "%1• ")
  t = t:gsub("^%s*#+%s+", "")
  t = t:gsub("%*%*", ""):gsub("__", ""):gsub("~~", ""):gsub("`", "")
  t = t:gsub("%s+$", "")
  return t
end

-- Splits extras into clickable targets (links, notes) and images.
local function splitExtras(extras)
  local links, images = {}, {}
  for _, item in ipairs(extras) do
    if item.kind == "image" then
      table.insert(images, item)
    else
      table.insert(links, item)
    end
  end
  return links, images
end

local function isQuote(line)
  return line:match("^%s*>") ~= nil
end

-- ── Inline extraction ────────────────────────────────────────────────────────

-- Scans one line (outside code) for images, note links and links.
-- Returns the text to hand to ui.markdown, and the extras found, in order.
-- Images are removed from the text (ui.markdown would show bare alt text);
-- links to existing notes become "[Name](#)" so they render underlined like
-- links. Links to missing notes stay as plain text.
function M.extractInline(line, noteExists)
  local extras = {}
  local text = line

  -- Images first, so "![a](b)" is not also read as a link.
  text = text:gsub("!%[([^%]]*)%]%(%s*<?([^%s%)>]+)>?[^%)]*%)", function(alt, src)
    table.insert(extras, { kind = "image", alt = alt, target = src })
    return ""
  end)

  -- Note links: [[Name]] or [[Name|Shown text]].
  text = text:gsub("%[%[([^%]]+)%]%]", function(inner)
    local name, alias = inner:match("^([^|]*)|(.*)$")
    if name == nil then
      name = inner
      alias = inner
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    alias = alias:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or (noteExists ~= nil and not noteExists(name)) then
      return "[[" .. inner .. "]]"
    end
    table.insert(extras, { kind = "note", label = alias ~= "" and alias or name, target = name })
    return "[" .. (alias ~= "" and alias or name) .. "](#)"
  end)

  -- Markdown links: [text](target). The "(#)" placeholders from note links
  -- are skipped. Scanned on a copy so the text keeps its link syntax.
  local seen = {}
  local scan = text:gsub("%[([^%]]*)%]%(%s*<?([^%s%)>]+)>?[^%)]*%)", function(label, target)
    if target ~= "#" and not seen[target] then
      seen[target] = true
      table.insert(extras, { kind = "link", label = label ~= "" and label or target, target = target })
    end
    return " "
  end)

  -- Bare and <angle-bracket> web addresses in what is left.
  for url in scan:gmatch("https?://[^%s<>%)%]\"']+") do
    url = url:gsub("[%.,;:!%?]+$", "")
    if not seen[url] then
      seen[url] = true
      table.insert(extras, { kind = "link", label = url, target = url })
    end
  end

  return text, extras
end

-- ── Block parsing ────────────────────────────────────────────────────────────

-- Splits a note into blocks:
--   { kind = "md", text = ... }
--   { kind = "task", line = n, indent = ..., done = bool, text = ..., link = item|nil }
--   { kind = "linkline", text = ..., item = item }   one line, clickable
--   { kind = "code", text = "```...```", code = body }
--   { kind = "quote", text = ... }
--   { kind = "extra", item = { kind = "link"|"note"|"image", ... } }
--   { kind = "blank" }                              one empty line
-- Extras are placed after the paragraph (run of non-blank lines) they came
-- from, so ui.markdown never gets a list or table cut in half.
--
-- Every text line gets two trailing spaces, Markdown's "hard line break": a
-- single newline in the note then shows as a new line in the preview instead
-- of being joined into the paragraph. (At the end of a block they are ignored.)
--
-- Every blank line shows as an empty line, like in a notes app (standard
-- Markdown would collapse them into one paragraph break). Blank lines right
-- after a heading, and at the start or end of the note, are skipped: headings
-- already have space around them.
local function hardBreak(text)
  if text:match("%S") then
    return text .. "  "
  end
  return text
end

function M.parse(source, noteExists)
  local lines = M.splitLines(source)
  local blocks = {}
  local md = {}
  local pending = {}

  local function flushMd()
    while #md > 0 and not md[1]:match("%S") do
      table.remove(md, 1)
    end
    while #md > 0 and not md[#md]:match("%S") do
      table.remove(md)
    end
    if #md > 0 then
      local text = table.concat(md, "\n")
      if text:match("%S") then
        table.insert(blocks, { kind = "md", text = text })
      end
      md = {}
    end
  end

  local function flushExtras()
    for _, item in ipairs(pending) do
      table.insert(blocks, { kind = "extra", item = item })
    end
    pending = {}
  end

  local function flushAll()
    flushMd()
    flushExtras()
  end

  local function addExtras(list)
    for _, item in ipairs(list) do
      table.insert(pending, item)
    end
  end

  local afterHeading = false

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local fence = fenceOpen(line)
    local wasAfterHeading = afterHeading
    afterHeading = line:match("^%s*#+%s") ~= nil

    if fence ~= nil then
      flushAll()
      local body = {}
      local raw = { line }
      local j = i + 1
      local closed = false
      while j <= #lines do
        local inner = lines[j]
        table.insert(raw, inner)
        if isFenceClose(inner, fence) then
          closed = true
          break
        end
        table.insert(body, inner)
        j = j + 1
      end
      if not closed then
        table.insert(raw, fence)
      end
      table.insert(blocks, { kind = "code", text = table.concat(raw, "\n"), code = table.concat(body, "\n") })
      i = j + 1

    elseif isQuote(line) then
      flushAll()
      local inner = {}
      local quoteExtras = {}
      while i <= #lines and isQuote(lines[i]) do
        local stripped = lines[i]:gsub("^%s*>%s?", "")
        local text, extras = M.extractInline(stripped, noteExists)
        table.insert(inner, hardBreak(text))
        for _, item in ipairs(extras) do
          table.insert(quoteExtras, item)
        end
        i = i + 1
      end
      table.insert(blocks, { kind = "quote", text = table.concat(inner, "\n") })
      addExtras(quoteExtras)
      flushExtras()

    else
      local indent, done, content = M.parseTask(line)
      if indent ~= nil then
        flushMd()
        local text, extras = M.extractInline(content, noteExists)
        local links, images = splitExtras(extras)
        local link = nil
        if #links == 1 then
          link = links[1]
        else
          addExtras(links)
        end
        table.insert(blocks, { kind = "task", line = i, indent = indent, done = done, text = text, link = link })
        addExtras(images)
        i = i + 1
      elseif line:match("^%s*$") then
        flushAll()
        if #blocks > 0 and not wasAfterHeading then
          table.insert(blocks, { kind = "blank" })
        end
        afterHeading = wasAfterHeading -- a run of blanks after a heading is all skipped
        i = i + 1
      else
        local text, extras = M.extractInline(line, noteExists)
        local links, images = splitExtras(extras)
        if #links == 1 and not isTableLine(line) and text:match("%S") then
          -- One link on the line: the line itself becomes clickable text.
          flushAll()
          table.insert(blocks, { kind = "linkline", text = text, item = links[1] })
          addExtras(images)
        else
          -- A line that only held images disappears from the text entirely.
          if text:match("%S") or #extras == 0 then
            table.insert(md, hardBreak(text))
          end
          addExtras(extras)
        end
        i = i + 1
      end
    end
  end
  flushAll()
  while #blocks > 0 and blocks[#blocks].kind == "blank" do
    table.remove(blocks)
  end
  return blocks
end

-- ── Rendering ────────────────────────────────────────────────────────────────

-- ctx fields (all provided by panel.luau):
--   keyPrefix                 string, unique per note
--   copiedKey                 key of the code block just copied, or nil
--   tr(key, fallback)         translation helper
--   onToggleTask(lineIndex)
--   onOpenLink(target)
--   onOpenNote(name)
--   noteExists(name)          -> true when that note file exists
--   onCopy(key, text)
--   resolveImage(target)      -> absolute path or nil, and a reason
function M.render(source, ctx)
  local children = {}
  local count = 0
  local function key(kind)
    count = count + 1
    return ctx.keyPrefix .. "-" .. kind .. "-" .. count
  end

  local function activate(item)
    if item.kind == "note" then
      ctx.onOpenNote(item.target)
    else
      ctx.onOpenLink(item.target)
    end
  end

  local function chip(item)
    local glyph = item.kind == "note" and "notes" or "external-link"
    local target = item.target
    return ui.row({
      key = key("chip"),
      gap = 6,
      align = "center",
      paddingV = 3,
      paddingH = 8,
      radius = 6,
      fill = "surface_container",
      tooltip = item.kind == "note" and ctx.tr("open_note_link", "Open note") .. ": " .. target or target,
      onClick = function()
        activate(item)
      end,
    }, {
      ui.glyph({ name = glyph, size = 13, color = "primary" }),
      ui.label({ text = item.label, maxLines = 1, flexGrow = 1, fontSize = 12, color = "primary" }),
    })
  end

  -- A line that opens `item` when clicked: plain text in the accent color with
  -- a small icon in front. Hovering shows the target.
  local function clickableText(k, text, item, muted)
    return ui.row({
      key = k,
      flexGrow = 1,
      gap = 6,
      align = "center",
      tooltip = item.kind == "note" and ctx.tr("open_note_link", "Open note") .. ": " .. item.target or item.target,
      onClick = function()
        activate(item)
      end,
    }, {
      ui.glyph({ name = item.kind == "note" and "notes" or "external-link", size = 13, color = "primary" }),
      ui.label({ text = M.plainText(text), color = muted and "on_surface_variant" or "primary", flexGrow = 1 }),
    })
  end

  local function image(item)
    local path, reason = ctx.resolveImage(item.target)
    if path == nil then
      if reason == "remote" then
        -- Web images would need downloading; open them in the browser instead.
        return chip({ kind = "link", label = (item.alt ~= "" and item.alt or item.target) .. " (" .. ctx.tr("web_image", "web image") .. ")", target = item.target })
      end
      return ui.label({
        key = key("img-missing"),
        text = ctx.tr("image_missing", "Image not found") .. ": " .. item.target,
        fontSize = 12,
        color = "error",
      })
    end
    return ui.image({
      key = key("img") .. "-" .. path,
      path = path,
      width = IMAGE_WIDTH,
      height = IMAGE_HEIGHT,
      fit = "contain",
      radius = 6,
      tooltip = item.alt ~= "" and item.alt or nil,
      onClick = function()
        ctx.onOpenLink(path)
      end,
    })
  end

  for _, block in ipairs(M.parse(source, ctx.noteExists)) do
    if block.kind == "md" then
      -- Inside a row the Markdown view is measured at its real width. Placed
      -- directly in the scroll column it under-counted wrapped lines, and the
      -- next block overlapped its last line.
      table.insert(children, ui.row({ key = key("md") }, {
        ui.markdown({ text = block.text, flexGrow = 1 }),
      }))

    elseif block.kind == "task" then
      local lineIndex = block.line
      local shown = block.text ~= "" and block.text or " "
      local tabs = select(2, block.indent:gsub("\t", ""))
      local depth = (#block.indent - tabs) + tabs * 4
      table.insert(children, ui.row({
        key = key("task") .. (block.done and "-done" or "-open"),
        gap = 8,
        align = "center",
        paddingV = 2,
        paddingH = depth * 6,
      }, {
        ui.button({
          glyph = block.done and "check" or "square",
          glyphSize = 13,
          variant = block.done and "primary" or "outline",
          width = 22,
          height = 22,
          onClick = function()
            ctx.onToggleTask(lineIndex)
          end,
        }),
        block.link ~= nil
            and clickableText(key("task-link"), shown, block.link, block.done)
          or ui.markdown({ text = block.done and ("~~" .. shown .. "~~") or shown, flexGrow = 1 }),
      }))

    elseif block.kind == "linkline" then
      table.insert(children, clickableText(key("linkline"), block.text, block.item))

    elseif block.kind == "code" then
      local k = key("code")
      local copied = ctx.copiedKey == k
      local code = block.code
      table.insert(children, ui.row({ key = k, gap = 4, align = "start" }, {
        ui.markdown({ text = block.text, flexGrow = 1 }),
        ui.button({
          key = k .. (copied and "-copied" or "-copy"),
          glyph = copied and "check" or "copy",
          glyphSize = 13,
          variant = "ghost",
          tooltip = copied and ctx.tr("copied", "Copied") or ctx.tr("copy_code", "Copy code"),
          onClick = function()
            ctx.onCopy(k, code)
          end,
        }),
      }))

    elseif block.kind == "quote" then
      table.insert(children, ui.row({ key = key("quote"), gap = 10, align = "stretch", paddingV = 2 }, {
        ui.box({ width = 3, fill = "primary", radius = 2 }),
        ui.markdown({ text = block.text ~= "" and block.text or " ", flexGrow = 1 }),
      }))

    elseif block.kind == "blank" then
      -- With the column gap on both sides this is about one line of text.
      table.insert(children, ui.box({ key = key("blank"), height = 8, opacity = 0 }))

    elseif block.kind == "extra" then
      if block.item.kind == "image" then
        table.insert(children, image(block.item))
      else
        table.insert(children, chip(block.item))
      end
    end
  end
  return children
end

return M
