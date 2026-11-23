local buf = require "pr.buf"
local forge = require "pr.forge"
local marks = require "pr.marks"

local M = { cache = {}, shown = {} }

local PAGE = 50
local flag = vim.fs.joinpath(vim.fn.stdpath "state", "pr-mine")
local mine = vim.uv.fs_stat(flag) ~= nil
local me = {}

function M.find(root, number)
  for _, pr in ipairs(M.cache[root] or {}) do
    if pr.number == number then return pr end
  end
end

function M.get(root, number, cb, fresh)
  local pr = not fresh and M.find(root, number)
  if pr then return cb(pr) end
  forge.pr(root, number, cb)
end

local function whoami(root, cb)
  if not mine or me[root] ~= nil then return cb() end
  forge.me(root, function(login)
    me[root] = login or false
    cb()
  end)
end

local function stack(prs)
  local heads, children, out = {}, {}, {}
  for _, pr in ipairs(prs) do
    pr.depth = nil
    if not pr.fork then heads[pr.head_ref] = pr end
  end
  for _, pr in ipairs(prs) do
    local parent = heads[pr.base_ref]
    pr.parent = parent ~= pr and parent or nil
    if pr.parent then
      children[parent] = children[parent] or {}
      table.insert(children[parent], pr)
    end
  end
  local function walk(pr, depth)
    if pr.depth then return end
    pr.depth = depth
    out[#out + 1] = pr
    for _, child in ipairs(children[pr] or {}) do
      walk(child, depth + 1)
    end
  end
  for _, pr in ipairs(prs) do
    if not pr.parent then walk(pr, 0) end
  end
  for _, pr in ipairs(prs) do
    walk(pr, 0)
  end
  return out
end

function M.draw(bufnr, s)
  local login = mine and me[s.root]
  local prs = vim.tbl_filter(function(pr) return not login or pr.author == login end, s.prs)
  local slots, rows, shown, width = marks.slots(s.root), {}, {}, 0
  for _, pr in ipairs(prs) do
    width = math.max(width, #pr.author)
  end
  for _, pr in ipairs(stack(prs)) do
    local slot = slots[pr.number]
    shown[#shown + 1] = pr.number
    rows[#rows + 1] = {
      { " " },
      buf.status(pr.status),
      { " " },
      { ("#%-5d"):format(pr.number), pr.draft and "PrDraft" or "PrNumber" },
      { slot and (slot < 10 and tostring(slot) or "+") or " ", "PrMark" },
      { " " },
      { pr.author .. (" "):rep(width - #pr.author + 2), "PrAuthor" },
      { pr.depth > 0 and ("  "):rep(pr.depth - 1) .. "└ " or "", "PrStack" },
      { pr.title },
      virt = { { buf.age(pr.updated), "PrMuted" } },
      pr = pr,
      url = pr.url,
    }
  end
  if not rows[1] then
    rows[1] = { { login and ("No open pull requests by " .. login) or "No open pull requests", "PrMuted" } }
  end
  M.shown[s.root] = shown
  buf.render(bufnr, rows)
end

function M.read(bufnr, s)
  local alive, fresh = buf.guard(bufnr, s), s.prs ~= nil
  if not s.prs then buf.message(bufnr, "Loading pull requests…", "PrMuted") end
  forge.prs(s.root, function(prs, err)
    if not alive() then return end
    if not prs then return buf.message(bufnr, err, "ErrorMsg") end
    s.prs, M.cache[s.root] = prs, prs
    if #prs < PAGE then marks.keep(s.root, prs) end
    whoami(s.root, function()
      if not alive() then return end
      M.draw(bufnr, s)
      local shas, by_sha = {}, {}
      for _, pr in ipairs(prs) do
        shas[#shas + 1], by_sha[pr.head] = pr.head, pr
      end
      forge.statuses(s.root, shas, function(sha, status)
        if not alive() then return end
        by_sha[sha].status = status or nil
        M.draw(bufnr, s)
      end, fresh)
    end)
  end)
end

local function filter()
  local s = buf.current()
  local bufnr = vim.api.nvim_get_current_buf()
  mine = not mine
  if mine then
    vim.fn.mkdir(vim.fs.dirname(flag), "p")
    vim.fn.writefile({}, flag)
  else
    vim.fn.delete(flag)
  end
  whoami(s.root, function()
    if s.prs and vim.api.nvim_buf_is_valid(bufnr) then M.draw(bufnr, s) end
  end)
end

local function enter()
  local _, row = buf.current()
  if row and row.pr then buf.open("pr://" .. row.pr.number) end
end

M.maps = vim.tbl_extend("error", {
  ["<CR>"] = { enter, "Review the pull request" },
  F = { filter, "Toggle only my pull requests" },
}, buf.verbs)

return M
