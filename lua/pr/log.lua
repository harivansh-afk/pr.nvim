local buf = require "pr.buf"
local forge = require "pr.forge"
local git = require "pr.git"

local M = { count = 50 }

function M.draw(bufnr, s)
  local rows, width = {}, 0
  for _, commit in ipairs(s.commits) do
    width = math.max(width, vim.fn.strdisplaywidth(commit.author))
  end
  for _, commit in ipairs(s.commits) do
    rows[#rows + 1] = {
      { " " },
      buf.status(commit.status),
      { " " },
      { commit.sha, "PrHash" },
      { " " },
      { commit.author .. (" "):rep(width - vim.fn.strdisplaywidth(commit.author) + 2), "PrAuthor" },
      { commit.subject },
      virt = { { buf.age(commit.time), "PrMuted" } },
      commit = commit,
      sha = commit.full,
    }
  end
  if not rows[1] then rows[1] = { { "No commits", "PrMuted" } } end
  buf.render(bufnr, rows)
end

function M.read(bufnr, s)
  local alive, fresh = buf.guard(bufnr, s), s.commits ~= nil
  s.commits = git.log(s.root, { "-n", tostring(M.count), "HEAD" })
  M.draw(bufnr, s)
  local shas, by_sha = {}, {}
  for _, commit in ipairs(s.commits) do
    shas[#shas + 1], by_sha[commit.full] = commit.full, commit
  end
  forge.statuses(s.root, shas, function(sha, status)
    if not alive() then return end
    by_sha[sha].status = status or nil
    M.draw(bufnr, s)
  end, fresh)
end

local function enter()
  local _, row = buf.current()
  if row and row.commit then buf.open("pr://commit/" .. row.commit.sha) end
end

local function diff(layout)
  return function()
    local s, row = buf.current()
    if not (row and row.commit) then return end
    local review = { repo = s.root, base = row.sha .. "^", target = row.sha, mode = "direct" }
    require("pr.review").diff(review, nil, nil, layout)
  end
end

M.maps = {
  ["<CR>"] = { enter, "Review the commit" },
  dd = { diff(), "Review the diff" },
  dv = { diff "split", "Review the diff side by side" },
}

return M
