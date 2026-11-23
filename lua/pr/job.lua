local buf = require "pr.buf"
local forge = require "pr.forge"

local M = { context = {}, filetype = "prlog", maps = {} }

local ns = vim.api.nvim_create_namespace "pr_job"
local POLL = 5000
local STAMP = "^%d%d%d%d%-%d%d%-%d%dT[%d:.]+Z "
local COLOR = { "PrAnsiRed", "PrAnsiGreen", "PrAnsiYellow", "PrAnsiBlue", "PrAnsiMagenta", "PrAnsiCyan" }

function M.plain(line) return vim.trim((line:gsub(STAMP, ""):gsub("\27%[[%d;:?]*%a", ""):gsub("##%[%a+%]", ""))) end

local function sgr(style, params)
  local codes, i = vim.split(params, "[;:]"), 1
  while i <= #codes do
    local code = tonumber(codes[i]) or 0
    if code == 0 then
      style.color, style.bold = nil, nil
    elseif code == 1 then
      style.bold = true
    elseif code == 22 then
      style.bold = nil
    elseif code == 39 then
      style.color = nil
    elseif (code >= 30 and code <= 37) or (code >= 90 and code <= 97) then
      style.color = COLOR[code % 10]
    elseif code == 38 or code == 48 then
      local indexed = codes[i + 1] == "5"
      if indexed and code == 38 then style.color = COLOR[(tonumber(codes[i + 2]) or 0) % 8] end
      i = i + (indexed and 2 or 4)
    end
    i = i + 1
  end
end

local function strip(line, style, row, marks)
  local out, from, col = {}, 1, 0
  line = line:gsub("\27%][^\7\27]*[\7\27]\\?", "")
  while true do
    local start, stop, params, final = line:find("\27%[([%d;:?]*)(%a)", from)
    local text = line:sub(from, (start or 0) - 1)
    local group = style.color or (style.bold and "PrAnsiBold")
    if group and text ~= "" then marks[#marks + 1] = { row, col, col + #text, group } end
    out[#out + 1], col = text, col + #text
    if not start then return table.concat(out) end
    if final == "m" then sgr(style, params) end
    from = stop + 1
  end
end

local function paint(bufnr, text)
  local lines, marks, style = {}, {}, {}
  for line in vim.gsplit(text:gsub("^\239\187\191", ""):gsub("\n$", ""), "\n", { plain = true }) do
    lines[#lines + 1] = strip(line:gsub("\r$", ""):gsub("^.*\r", ""), style, #lines, marks)
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, mark[1], mark[2], { end_col = mark[3], hl_group = mark[4] })
  end
end

local function load(bufnr, s)
  local alive, id = buf.guard(bufnr, s), tonumber(s.id)
  local context = M.context[id]
  forge.job_log(s.root, id, function(text, err)
    if not alive() then return end
    if not text and not s.text then buf.message(bufnr, err, "ErrorMsg") end
    if text and text ~= s.text then
      local first = not s.text
      s.text, s.rows = text, nil
      paint(bufnr, text)
      if first then
        for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
          vim.api.nvim_win_call(win, function()
            if vim.fn.search("##\\[error\\]", "cw") > 0 then vim.cmd "normal! zv" end
          end)
        end
      end
    end
    if not context then return end
    forge.checks(s.root, context.sha, function(jobs)
      for _, job in ipairs(jobs or {}) do
        if job.id == id and (job.status == "running" or job.status == "pending") then
          vim.defer_fn(function()
            if alive() then load(bufnr, s) end
          end, POLL)
        end
      end
    end)
  end)
end

function M.read(bufnr, s)
  local context = M.context[tonumber(s.id)]
  s.url = context and context.url
  if s.text then
    paint(bufnr, s.text)
  else
    buf.message(bufnr, "Loading the log…", "PrMuted")
  end
  load(bufnr, s)
end

function M.setup(bufnr)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].undolevels = -1
  buf.wo(bufnr, {
    conceallevel = 3,
    concealcursor = "nvic",
    foldmethod = "marker",
    foldmarker = "##[group],##[endgroup]",
    foldlevel = 0,
    foldtext = "",
  })
end

return M
