local buf = require "pr.buf"
local forge = require "pr.forge"
local git = require "pr.git"
local list = require "pr.list"

local M = {}

local LETTER = { A = "PrAdded", D = "PrDeleted" }
local DIFF = { ["+"] = "PrAdded", ["-"] = "PrDeleted", ["@"] = "PrHunk" }

local function spec(s)
  local commit = s.commits[s.at]
  if commit then return { repo = s.root, base = commit.full .. "^", target = commit.full, mode = "direct" } end
  return { repo = s.root, base = s.pr.base, target = s.head, mode = "merge-base" }
end

local function range(s)
  local review = spec(s)
  return review.base .. (review.mode == "direct" and ".." or "...") .. review.target
end

local function stat(file)
  if file.binary then return { { "binary", "PrMuted" } } end
  local virt = {}
  if file.add > 0 then virt[#virt + 1] = { "+" .. file.add, "PrAdded" } end
  if file.del > 0 then virt[#virt + 1] = { (virt[1] and " -" or "-") .. file.del, "PrDeleted" } end
  return virt
end

local function hunks(s, file, rows, plain)
  local lnum = 1
  for _, line in ipairs(git.diff(s.root, range(s), file)) do
    local start = line:match "^@@ %-%d+,?%d* %+(%d+)"
    lnum = tonumber(start) or lnum
    local sign = line:sub(1, 1)
    rows[#rows + 1] = { { start and line:match "^@@.-@@" or line, plain and DIFF[sign] }, file = file, lnum = lnum }
    if not start and sign ~= "-" then lnum = lnum + 1 end
  end
  rows[#rows + 1] = {}
end

function M.draw(bufnr, s)
  local rows, pr, commit = {}, s.pr, s.commits[s.at]
  local attach, diffs = pcall(require, "diffs")
  local function field(name, ...) rows[#rows + 1] = { { ("%-8s"):format(name .. ":"), "PrHeader" }, ... } end
  if pr then
    field("PR", { "#" .. pr.number, pr.draft and "PrDraft" or "PrNumber" }, { " " .. pr.title })
    field("Author", { pr.author, "PrAuthor" })
    field("Head", { pr.head_ref, "PrRef" })
    field("Base", { pr.base_ref, "PrRef" }, pr.parent and { " #" .. pr.parent.number, "PrStack" })
  else
    field("Commit", { commit.sha, "PrHash" }, { " " .. commit.subject })
    field("Author", { commit.author, "PrAuthor" })
  end
  field("Help", { "g?", "PrRef" })
  rows[#rows + 1] = {}
  if pr then
    rows[#rows + 1] = { { "Commits", "PrHeading" }, { (" (%d)"):format(#s.commits) } }
    for at, item in ipairs(s.commits) do
      rows[#rows + 1] = {
        { item.sha, "PrHash" },
        { " " .. item.subject },
        at = at,
        sha = item.full,
        hl = at == s.at and "PrSelected" or nil,
      }
    end
    rows[#rows + 1] = {}
  end
  local files = git.files(s.root, range(s))
  local title = { { "Files", "PrHeading" }, { (" (%d)"):format(#files) } }
  if pr and commit then title[3] = { " " .. commit.sha, "PrHash" } end
  rows[#rows + 1] = title
  for _, file in ipairs(files) do
    local name = file.old and (file.old .. " -> " .. file.path) or file.path
    rows[#rows + 1] =
      { { file.status, LETTER[file.status] or "PrChanged" }, { " " .. name }, file = file, virt = stat(file) }
    if s.expanded[file.path] then hunks(s, file, rows, not attach) end
  end
  buf.render(bufnr, rows)
  if attach then
    vim.b[bufnr].diffs_repo_root = s.root
    diffs[s.attached and "refresh" or "attach"](bufnr)
    s.attached = true
  end
end

function M.read(bufnr, s)
  local alive, number = buf.guard(bufnr, s), tonumber(s.id)
  s.expanded = s.expanded or {}
  if not number then
    s.commits, s.at = git.log(s.root, { "-1", s.id:match "%x+$" }), 1
    if not s.commits[1] then return buf.message(bufnr, "no such commit", "ErrorMsg") end
    s.sha = s.commits[1].full
    return M.draw(bufnr, s)
  end
  local selected = s.at and s.commits[s.at].full
  local function load(pr, err)
    if not alive() then return end
    if not pr then return buf.message(bufnr, err, "ErrorMsg") end
    git.sync(s.root, pr, function(ok, sync_err)
      if not alive() then return end
      if not ok then return buf.message(bufnr, sync_err, "ErrorMsg") end
      s.pr, s.url, s.at = pr, pr.url, nil
      s.head = git.rev(s.root, "refs/pr/" .. number)
      s.commits = git.log(s.root, { "--reverse", pr.base .. ".." .. s.head })
      for at, commit in ipairs(s.commits) do
        if commit.full == selected then s.at = at end
      end
      buf.last = { root = s.root, pr = pr }
      M.draw(bufnr, s)
    end)
  end
  if not s.pr then buf.message(bufnr, ("Loading #%d…"):format(number), "PrMuted") end
  list.get(s.root, number, load, s.pr ~= nil)
end

function M.open(root, sha, path, lnum, cmd)
  local busy = git.worktree(root, sha, function(dir, err)
    if not dir then return buf.notify(err, vim.log.levels.ERROR) end
    local file = vim.fs.joinpath(dir, path)
    if not vim.uv.fs_stat(file) then
      return buf.notify(path .. " does not exist at " .. sha:sub(1, 7), vim.log.levels.WARN)
    end
    vim.cmd[cmd or "edit"](vim.fn.fnameescape(file))
    if lnum then
      vim.api.nvim_win_set_cursor(0, { math.min(lnum, vim.api.nvim_buf_line_count(0)), 0 })
      vim.cmd "normal! zvzz"
    end
  end)
  if busy then buf.notify("checking out " .. sha:sub(1, 7) .. "…") end
end

function M.diff(review, path, lnum, layout)
  local ok, diffs = pcall(require, "diffs")
  if not ok then return buf.notify("the diff review needs diffs.nvim", vim.log.levels.WARN) end
  diffs.open_review(review, { layout = layout, replace_win = vim.api.nvim_get_current_win() })
  if not path then return end
  if not diffs.review_goto(path) then return vim.fn.search("\\V" .. vim.fn.escape(path, "\\"), "cw") end
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
    vim.cmd "normal! zvzz"
  end
end

local function enter(cmd)
  return function()
    local s, row = buf.current()
    if row and row.at then
      s.at = row.at ~= s.at and row.at or nil
      return M.draw(vim.api.nvim_get_current_buf(), s)
    end
    if row and row.file then M.open(s.root, spec(s).target, row.file.path, row.lnum, cmd) end
  end
end

local function toggle()
  local s, row = buf.current()
  if not (row and row.file) then return end
  local path = row.file.path
  s.expanded[path] = not s.expanded[path] or nil
  M.draw(vim.api.nvim_get_current_buf(), s)
  for lnum, item in ipairs(s.rows) do
    if item.file and item.file.path == path then return vim.api.nvim_win_set_cursor(0, { lnum, 0 }) end
  end
end

local function diff(layout)
  return function()
    local s, row = buf.current()
    if s.commits then M.diff(spec(s), row and row.file and row.file.path, row and row.lnum, layout) end
  end
end

local function step(delta)
  return function()
    local s = buf.current()
    if not s.pr then return end
    local at = ((s.at or 0) + delta) % (#s.commits + 1)
    s.at = at > 0 and at or nil
    M.draw(vim.api.nvim_get_current_buf(), s)
  end
end

local function file(flags)
  return function() vim.fn.search("^\\u ", flags) end
end

M.maps = vim.tbl_extend("error", {
  ["<CR>"] = { enter(), "Open the file, or select the commit" },
  o = { enter "split", "Open the file in a split" },
  gO = { enter "vsplit", "Open the file in a vertical split" },
  O = { enter "tabedit", "Open the file in a tab" },
  ["="] = { toggle, "Toggle the inline diff" },
  dd = { diff(), "Review the diff" },
  dv = { diff "split", "Review the diff side by side" },
  ["]c"] = { step(1), "Next commit" },
  ["[c"] = { step(-1), "Previous commit" },
  ["]f"] = { file "W", "Next file" },
  ["[f"] = { file "bW", "Previous file" },
  ["]p"] = { "<Cmd>PR next<CR>", "Next pull request" },
  ["[p"] = { "<Cmd>PR prev<CR>", "Previous pull request" },
  ["]m"] = { "<Cmd>PR marks next<CR>", "Next marked pull request" },
  ["[m"] = { "<Cmd>PR marks prev<CR>", "Previous marked pull request" },
}, buf.verbs)

return M
