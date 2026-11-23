local buf = require "pr.buf"
local forge = require "pr.forge"
local git = require "pr.git"
local list = require "pr.list"

local M = {}

local FACE = {
  thread = { "●", "PrRunning", 1 },
  changes = { "✗", "PrFail", 2, " requested changes" },
  commented = { "○", "PrPending", 3, " commented" },
  approved = { "✓", "PrPass", 4, " approved" },
  settled = { "⊘", "PrSkipped", 5, " (dismissed)" },
}

local TAGS = { "details", "summary", "sub", "sup", "br", "p" }

local function face(item)
  if item.path then return item.resolved and "settled" or "thread" end
  return item.verdict == "dismissed" and "settled" or item.verdict or "commented"
end

local function tidy(body)
  body = body
    :gsub("\r\n?", "\n")
    :gsub("<!%-%-.-%-%->", "")
    :gsub("!%[([^%]]-)%]%(%S-%)", "%1")
    :gsub('<a href="([^"]*)"[^>]*>(.-)</a>', "[%2](%1)")
  for _, tag in ipairs(TAGS) do
    body = body:gsub("</?" .. tag .. "%s*/?>", "")
  end
  return vim.trim((body:gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n")))
end

function M.draw(bufnr, s)
  local rows = {}
  for _, item in ipairs(s.items) do
    local mark, last = FACE[item.face], item.comments[#item.comments]
    local head = { { mark[1], mark[2] }, { " " }, item = item, url = item.url, fold = true }
    if item.path then
      head[3] = { ("`%s%s`"):format(item.path, item.line and (":" .. item.line) or ""), "PrRef" }
      head[4] = { "  " .. last.author, "PrAuthor" }
      head[5] = { #item.comments > 1 and (" (%d)"):format(#item.comments) or "", "PrMuted" }
    else
      head[3] = { last.author, "PrAuthor" }
      head[4] = { mark[4] }
    end
    head.virt = { { buf.age(last.time), "PrMuted" } }
    rows[#rows + 1] = head
    for _, comment in ipairs(item.comments) do
      if item.path then
        rows[#rows + 1] =
          { { "  " .. comment.author, "PrAuthor" }, { " · " .. buf.age(comment.time), "PrMuted" }, item = item }
        rows[#rows + 1] = { item = item }
      end
      for line in vim.gsplit(tidy(comment.body), "\n", { plain = true }) do
        rows[#rows + 1] = { { line }, item = item, url = item.url }
      end
      rows[#rows + 1] = { item = item }
    end
  end
  if not rows[1] then rows[1] = { { "No conversation", "PrMuted" } } end
  buf.render(bufnr, rows)
end

function M.read(bufnr, s)
  local alive, number = buf.guard(bufnr, s), tonumber(s.id)
  if not s.items then buf.message(bufnr, "Loading the conversation…", "PrMuted") end
  list.get(s.root, number, function(pr)
    if alive() and pr then
      s.pr, s.url = pr, pr.url
    end
  end)
  forge.threads(s.root, number, function(items, err)
    if not alive() then return end
    if not items then return buf.message(bufnr, err, "ErrorMsg") end
    for order, item in ipairs(items) do
      item.face, item.order, item.time = face(item), order, item.comments[#item.comments].time or 0
    end
    table.sort(items, function(a, b)
      if a.face ~= b.face then return FACE[a.face][3] < FACE[b.face][3] end
      if a.time ~= b.time then return a.time < b.time end
      return a.order < b.order
    end)
    s.items = items
    M.draw(bufnr, s)
  end)
end

function M.setup(bufnr)
  vim.bo[bufnr].bufhidden = "wipe"
  pcall(vim.treesitter.start, bufnr, "markdown")
  buf.wo(bufnr, {
    wrap = true,
    linebreak = true,
    breakindent = true,
    conceallevel = 2,
    concealcursor = "nc",
    foldmethod = "expr",
    foldexpr = "v:lua.require'pr.threads'.foldexpr()",
    foldlevel = 0,
    foldtext = "",
  })
end

function M.foldexpr()
  local s = buf.state[vim.api.nvim_get_current_buf()]
  local row = s and s.rows and s.rows[vim.v.lnum]
  return row and (row.fold and ">1" or row.item and "1") or "0"
end

local function enter()
  local s, row = buf.current()
  local item = row and row.item
  if not item then return end
  if not (item.path and s.pr) then return vim.cmd.PR "browse" end
  git.sync(s.root, s.pr, function(ok, err)
    if not ok then return buf.notify(err, vim.log.levels.ERROR) end
    if vim.wo.previewwindow then vim.cmd.wincmd "p" end
    require("pr.review").open(s.root, git.rev(s.root, "refs/pr/" .. s.pr.number), item.path, item.line)
  end)
end

M.maps = {
  ["<CR>"] = { enter, "Jump to the code, or open the comment in the browser" },
  ["="] = { "za", "Toggle the fold" },
}

return M
