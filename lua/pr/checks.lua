local buf = require "pr.buf"
local forge = require "pr.forge"
local git = require "pr.git"
local job_log = require "pr.job"
local list = require "pr.list"

local M = {}

local POLL = 5000
local TAIL = 8
local WORD = { fail = "failing", running = "running", pending = "pending" }

local function live(job) return job.status == "running" or job.status == "pending" end

local function duration(job)
  local stop = job.finished or (job.status == "running" and os.time())
  if not (job.started and stop) then return "" end
  local seconds = math.max(0, stop - job.started)
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return ("%dm%02ds"):format(math.floor(seconds / 60), seconds % 60) end
  return ("%dh%02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

function M.draw(bufnr, s)
  local counts, head = {}, {}
  for _, job in ipairs(s.jobs) do
    counts[job.status] = (counts[job.status] or 0) + 1
  end
  if s.pr then head[1] = { "#" .. s.pr.number .. " ", "PrNumber" } end
  head[#head + 1] = { s.sha:sub(1, 7) .. "  ", "PrHash" }
  for _, status in ipairs { "fail", "running", "pending" } do
    if counts[status] then
      head[#head + 1] = { ("%d %s"):format(counts[status], WORD[status]), buf.status(status)[2] }
      head[#head + 1] = { ", " }
    end
  end
  head[#head + 1] = s.jobs[1] and { ("%d/%d passing"):format(counts.pass or 0, #s.jobs), "PrPass" }
    or { "no checks", "PrMuted" }
  local rows = { head }
  for _, job in ipairs(s.jobs) do
    rows[#rows + 1] = {
      { " " },
      buf.status(job.status),
      { " " .. job.name },
      virt = { { vim.trim((job.workflow or "") .. "  " .. duration(job)), "PrMuted" } },
      job = job,
      url = job.url,
    }
    for _, detail in ipairs(job.id and s.expanded[job.id] and (s.detail[job.id] or { { { "…", "PrMuted" } } }) or {}) do
      rows[#rows + 1] = vim.list_extend({ { "     " }, job = job, url = job.url }, detail)
    end
  end
  buf.render(bufnr, rows)
end

local function detail(bufnr, s, job)
  local function show(rows)
    s.detail[job.id] = rows
    if vim.api.nvim_buf_is_valid(bufnr) then M.draw(bufnr, s) end
  end
  forge.steps(s.root, job.id, function(steps)
    if steps and steps[1] then
      return show(vim.tbl_map(function(step) return { buf.status(step.status), { " " .. step.name } } end, steps))
    end
    forge.job_log(s.root, job.id, function(text, err)
      local rows = {}
      for line in vim.gsplit(text or err or "", "\n", { plain = true }) do
        line = job_log.plain(line)
        if line:find("Run Post ", 1, true) then break end
        if line ~= "" then rows[#rows + 1] = { { line, "PrMuted" } } end
      end
      show(vim.list_slice(rows, math.max(1, #rows - TAIL + 1)))
    end)
  end)
end

local function load(bufnr, s)
  local alive = buf.guard(bufnr, s)
  forge.checks(s.root, s.sha, function(jobs, err)
    if not alive() then return end
    if not jobs then return buf.message(bufnr, err, "ErrorMsg") end
    forge.sort(jobs)
    s.jobs = jobs
    M.draw(bufnr, s)
    local busy = false
    for _, job in ipairs(jobs) do
      busy = busy or live(job)
      if job.id and s.expanded[job.id] and (live(job) or not s.detail[job.id]) then detail(bufnr, s, job) end
    end
    if busy then vim.defer_fn(function()
      if alive() then load(bufnr, s) end
    end, POLL) end
  end)
end

function M.read(bufnr, s)
  local alive, number = buf.guard(bufnr, s), tonumber(s.id)
  s.expanded, s.detail = s.expanded or {}, s.detail or {}
  if not s.jobs then buf.message(bufnr, "Loading checks…", "PrMuted") end
  if not number then
    s.sha = git.rev(s.root, s.id:match "%x+$")
    if not s.sha then return buf.message(bufnr, "no such commit", "ErrorMsg") end
    return load(bufnr, s)
  end
  list.get(s.root, number, function(pr, err)
    if not alive() then return end
    if not pr then return buf.message(bufnr, err, "ErrorMsg") end
    s.pr, s.sha, s.url = pr, pr.head, pr.url
    load(bufnr, s)
  end, s.jobs ~= nil)
end

function M.setup(bufnr) vim.bo[bufnr].bufhidden = "wipe" end

local function enter()
  local s, row = buf.current()
  local job = row and row.job
  if not job then return end
  if not job.id then return vim.cmd.PR "browse" end
  job_log.context[job.id] = { sha = s.sha, url = job.url }
  if vim.wo.previewwindow then vim.cmd.wincmd "p" end
  buf.open("pr://job/" .. job.id)
end

local function toggle()
  local s, row = buf.current()
  local job = row and row.job
  if not (job and job.id) then return end
  local bufnr = vim.api.nvim_get_current_buf()
  s.expanded[job.id] = not s.expanded[job.id] or nil
  M.draw(bufnr, s)
  if s.expanded[job.id] then detail(bufnr, s, job) end
  for lnum, item in ipairs(s.rows) do
    if item.job == job then return vim.api.nvim_win_set_cursor(0, { lnum, 0 }) end
  end
end

M.maps = {
  ["<CR>"] = { enter, "Open the job log" },
  ["="] = { toggle, "Toggle the steps or the log tail" },
}

return M
