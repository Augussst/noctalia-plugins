-- Tests for notes-md/preview.luau, run with plain Lua (no Noctalia needed):
--   lua tests/notes_md_preview.lua
-- preview.luau sticks to the Lua/Luau common subset, so lua 5.4 can load it;
-- `ui` is replaced by a stand-in that records the nodes it is asked to build.

local PREVIEW = arg[1] or "notes-md/preview.luau"

local P = dofile(PREVIEW)
local fails = 0
local function eq(name, got, want)
  if got ~= want then fails = fails + 1; print("FAIL " .. name .. "\n  got:  " .. tostring(got) .. "\n  want: " .. tostring(want)) end
end
local function kinds(blocks) local t = {} for _, b in ipairs(blocks) do t[#t+1] = b.kind .. (b.item and (":" .. b.item.kind) or "") end return table.concat(t, ",") end

-- tasks
eq("task parse", select(3, P.parseTask("  - [x] done thing")), "done thing")
eq("task done", select(2, P.parseTask("- [X] a")), true)
eq("task ordered", select(3, P.parseTask("2. [ ] b")), "b")
eq("not task", P.parseTask("- plain"), nil)
eq("toggle on", P.toggleTaskLine("- [ ] a"), "- [x] a")
eq("toggle off", P.toggleTaskLine("  * [x] a b"), "  * [ ] a b")
eq("toggle num", P.toggleTaskLine("3) [ ] z"), "3) [x] z")
eq("toggle none", P.toggleTaskLine("**bold**"), "**bold**")

-- inline
local t, ex = P.extractInline("see [docs](https://a.b/c) and [[My Note|alias]] ![pic](~/x.png) https://bare.io/p.")
eq("inline text", t, "see [docs](https://a.b/c) and [alias](#)  https://bare.io/p.")
eq("inline n", #ex, 4)
eq("ex1 image", ex[1].kind .. " " .. ex[1].target, "image ~/x.png")
eq("ex2 note", ex[2].kind .. " " .. ex[2].target .. " " .. ex[2].label, "note My Note alias")
eq("ex3 link", ex[3].target, "https://a.b/c")
eq("ex4 bare", ex[4].target, "https://bare.io/p")
local _, ex2 = P.extractInline("<https://x.y> twice https://x.y")
eq("dedupe", #ex2, 1)

-- blocks
local doc = table.concat({
  "# Title", "", "Para with [l](https://l.ink)", "still para", "", "- [ ] task one", "- [x] task two",
  "", "```lua", "- [ ] not a task", "print(1)", "```", "", "> quote [q](https://q.q)", "> more",
  "", "| a | b |", "|---|---|", "| [t](https://t.t) | 2 |", "", "![only](img.png)", "end"
}, "\n")
local b = P.parse(doc)
eq("block kinds", kinds(b), "md,linkline:link,md,blank,task,task,blank,code,blank,quote,extra:link,blank,md,extra:link,blank,md,extra:image")
eq("code body", b[8].code, "- [ ] not a task\nprint(1)")
eq("task line idx", b[5].line, 6)
eq("quote text", b[10].text, "quote [q](https://q.q)  \nmore  ")
eq("table kept whole", b[13].text:find("|---|---|", 1, true) ~= nil, true)

-- unclosed fence swallows the rest
eq("unclosed", kinds(P.parse("```\na\n- [ ] b")), "code")

-- render with mock ui
ui = setmetatable({}, { __index = function(_, k) return function(props, children) return { type = k, props = props, children = children } end end })
local ctx = { keyPrefix = "n", tr = function(_, f) return f end, onToggleTask = function() end, onOpenLink = function() end,
  onOpenNote = function() end, onCopy = function() end,
  resolveImage = function(t) if t:match("^https?:") then return nil, "remote" end return "/abs/" .. t end }
local out = P.render(doc, ctx)
local seenKeys, dup = {}, false
local function walk(n) if n.props and n.props.key then if seenKeys[n.props.key] then dup = n.props.key end seenKeys[n.props.key] = true end for _, c in ipairs(n.children or {}) do walk(c) end end
for _, n in ipairs(out) do walk(n) end
eq("render count", #out, 17)
eq("unique keys", dup, false)
eq("image path", out[17].props.path, "/abs/img.png")
eq("empty note", #P.render("", ctx), 0)
-- missing notes stay plain text, existing ones become links
local exists = function(n) return n == "Real" end
local mt, mex = P.extractInline("[[Real]] and [[Typo]]", exists)
eq("missing note text", mt, "[Real](#) and [[Typo]]")
eq("missing note extras", #mex, 1)
-- hard breaks inside a paragraph
local hb = P.parse("line one\nline two")
eq("hard breaks", hb[1].text, "line one  \nline two  ")
-- clicks reach the right handler
local opened = {}
local cctx = { keyPrefix = "c", tr = function(_, f) return f end, onToggleTask = function() end,
  onOpenLink = function(t) opened[#opened+1] = "link:" .. t end, onOpenNote = function(n) opened[#opened+1] = "note:" .. n end,
  onCopy = function() end, noteExists = function() return true end, resolveImage = function() return "/x" end }
local c = P.render("Go to [site](https://s.s)\n\n[[Home]]\n\nTwo [a](https://a.a) and [b](https://b.b)\n\n- [ ] read [doc](https://d.d)", cctx)
local function clickAll(n) if n.props and type(n.props.onClick) == "function" and n.type ~= "button" then n.props.onClick() end for _, ch in ipairs(n.children or {}) do clickAll(ch) end end
for _, n in ipairs(c) do clickAll(n) end
eq("clicks", table.concat(opened, ","), "link:https://s.s,note:Home,link:https://a.a,link:https://b.b,link:https://d.d")
eq("multi-link line kinds", kinds(P.parse("Two [a](https://a.a) and [b](https://b.b)")), "md,extra:link,extra:link")
-- the user's example: Enter, Enter between sentences = one empty line
eq("one blank", kinds(P.parse("Sentence 1\n\nSentence 2")), "md,blank,md")
eq("two blanks", kinds(P.parse("Sentence 1\n\n\nSentence 2")), "md,blank,blank,md")
eq("edges trimmed", kinds(P.parse("\n\nHi\n\n")), "md")
eq("after heading", kinds(P.parse("# H\n\n\nText")), "md,md")
print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
local P2 = dofile(PREVIEW)
local f2 = 0
local function eq2(n, g, w) if g ~= w then f2 = f2 + 1 print("FAIL " .. n .. "\n  got:  " .. tostring(g) .. "\n  want: " .. tostring(w)) end end
eq2("plain link", P2.plainText("- Go to [**site**](https://s.s) `now`"), "• Go to site now")
eq2("plain note", P2.plainText("Open [Linux Todo](#) or [[Typo]]"), "Open Linux Todo or [[Typo]]")
print(f2 == 0 and "PLAIN PASS" or "PLAIN FAILED")
