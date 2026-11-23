local buf = require "pr.buf"
local forge = require "pr.forge"
local git = require "pr.git"
local list = require "pr.list"
local marks = require "pr.marks"

local M = {}

local WARN, ERROR = vim.log.levels.WARN, vim.log.levels.ERROR

local function subject(run)
  local root, pr = buf.subject()
  if not pr then return buf.notify("no pull request here", WARN) end
  run(root, pr)
end

local function report(message, after)
  return function(ok, err)
    if not ok then return buf.notify(err, ERROR) end
    buf.notify(message)
    if after then after() end
  end
end

local function reload(pr)
  buf.refresh("pr://list", true)
  buf.refresh("pr://" .. pr.number, true)
end

local function settle(pr)
  return function()
    buf.refresh("pr://list", true)
    if vim.api.nvim_get_current_buf() == buf.find("pr://" .. pr.number) then M.list() end
  end
end

function M.list()
  local s = buf.open "pr://list"
  local last = buf.last.pr
  for lnum, row in ipairs(s and last and s.rows or {}) do
    if row.pr and row.pr.number == last.number then vim.api.nvim_win_set_cursor(0, { lnum, 0 }) end
  end
end

function M.open(number) buf.open("pr://" .. number) end

function M.log(count)
  local log = require "pr.log"
  local loaded = buf.state[buf.find "pr://log"] and tonumber(count)
  log.count = tonumber(count) or log.count
  buf.open "pr://log"
  if loaded then buf.refresh("pr://log", true) end
end

function M.checks() buf.pane "checks" end

function M.threads() buf.pane "threads" end

function M.step(delta, marked)
  local root, pr = buf.subject()
  local order = marked and marks.list(root) or list.shown[root] or {}
  if not order[1] then return buf.notify(marked and "no marked pull requests" or "open the list first", WARN) end
  local at = 0
  for i, number in ipairs(order) do
    if pr and number == pr.number then at = i end
  end
  M.open(order[at == 0 and (delta > 0 and 1 or #order) or (at - 1 + delta) % #order + 1])
end

function M.mark()
  subject(function(root, pr)
    marks.toggle(root, pr.number)
    buf.refresh "pr://list"
  end)
end

function M.marks(arg)
  local root = buf.subject()
  local numbers = marks.list(root)
  if arg == "next" or arg == "prev" then return M.step(arg == "next" and 1 or -1, true) end
  if arg then
    if not numbers[tonumber(arg)] then return buf.notify("no pull request in slot " .. arg, WARN) end
    return M.open(numbers[tonumber(arg)])
  end
  if not numbers[1] then return buf.notify("no marked pull requests", WARN) end
  vim.ui.select(numbers, {
    prompt = "Marked pull requests",
    format_item = function(number)
      local pr = list.find(root, number)
      return ("#%d %s"):format(number, pr and pr.title or "")
    end,
  }, function(number)
    if number then M.open(number) end
  end)
end

function M.draft()
  subject(function(root, pr)
    local message = ("#%d is %s"):format(pr.number, pr.draft and "ready" or "a draft")
    forge.draft(root, pr, not pr.draft, report(message, function() reload(pr) end))
  end)
end

function M.merge()
  subject(function(root, pr)
    forge.merge_styles(root, function(styles)
      local choices = {}
      for _, auto in ipairs { false, true } do
        for _, style in ipairs(styles) do
          choices[#choices + 1] = { style = style, auto = auto }
        end
      end
      vim.ui.select(choices, {
        prompt = ("Merge #%d %s"):format(pr.number, pr.title),
        format_item = function(choice) return choice.style .. (choice.auto and " when checks pass" or "") end,
      }, function(choice)
        if not choice then return end
        local message = ("#%d %s"):format(pr.number, choice.auto and "merges when its checks pass" or "merged")
        forge.merge(root, pr, choice.style, choice.auto, report(message, settle(pr)))
      end)
    end)
  end)
end

function M.close()
  subject(function(root, pr)
    if vim.fn.confirm(("Close #%d without merging?"):format(pr.number), "&Yes\n&No", 2) ~= 1 then return end
    forge.close(root, pr, report(("#%d closed"):format(pr.number), settle(pr)))
  end)
end

function M.checkout()
  subject(function(root, pr)
    git.sync(root, pr, function(ok, err)
      if not ok then return buf.notify(err, ERROR) end
      git.checkout(
        root,
        pr,
        report("checked out " .. pr.head_ref, function()
          vim.cmd.checktime()
          vim.api.nvim_exec_autocmds("User", { pattern = "FugitiveChanged", modeline = false })
        end)
      )
    end)
  end)
end

function M.browse()
  local s, row = buf.current()
  local root, pr = buf.subject()
  local url = row and row.url or not (row and row.sha) and (s and s.url or pr and pr.url)
  local sha = row and row.sha or s and s.sha
  if url then return vim.ui.open(url) end
  if not sha then return buf.notify("nothing to open here", WARN) end
  forge.web(root, function(web)
    if web then vim.ui.open(web .. "/commit/" .. sha) end
  end)
end

function M.clean(_, force)
  local root = buf.subject()
  if not root then return buf.notify("not in a git repository", ERROR) end
  git.clean(root, force, report "removed the review worktree")
end

local COMMANDS = {
  list = M.list,
  log = M.log,
  checks = M.checks,
  threads = M.threads,
  next = function() M.step(1) end,
  prev = function() M.step(-1) end,
  mark = M.mark,
  marks = M.marks,
  draft = M.draft,
  merge = M.merge,
  close = M.close,
  checkout = M.checkout,
  browse = M.browse,
  clean = M.clean,
}

function M.command(opts)
  local name = opts.fargs[1] or "list"
  if tonumber(name) then return M.open(tonumber(name)) end
  if not COMMANDS[name] then return buf.notify("no such command: " .. name, ERROR) end
  COMMANDS[name](opts.fargs[2], opts.bang)
end

function M.complete(lead, line)
  local words = vim.split(line, "%s+")
  local pool = #words < 3 and vim.tbl_keys(COMMANDS) or words[2] == "marks" and { "next", "prev" } or {}
  table.sort(pool)
  return vim.tbl_filter(function(word) return vim.startswith(word, lead) end, pool)
end

return M
