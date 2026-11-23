local git = require "pr.git"

local M = { state = {}, last = {} }

local ns = vim.api.nvim_create_namespace "pr"
local pending

local ROUTES = {
  { "^pr://list$", "list" },
  { "^pr://log$", "log" },
  { "^pr://job/(%d+)$", "job" },
  { "^pr://(.+)/checks$", "checks", true },
  { "^pr://(%d+)/threads$", "threads", true },
  { "^pr://(%d+)$", "review", true },
  { "^pr://(commit/%x+)$", "review", true },
}

local STATUS = {
  pass = { "✓", "PrPass" },
  fail = { "✗", "PrFail" },
  running = { "●", "PrRunning" },
  pending = { "○", "PrPending" },
  skipped = { "⊘", "PrSkipped" },
}

local AGES = { { 31536000, "y" }, { 2592000, "mo" }, { 604800, "w" }, { 86400, "d" }, { 3600, "h" }, { 60, "m" } }

local function close()
  if vim.wo.previewwindow then return vim.cmd.pclose() end
  if vim.fn.bufnr "#" > 0 then vim.cmd.buffer "#" end
end

local MAPS = {
  ["g?"] = { "<Cmd>help pr-maps<CR>", "Help" },
  ["gx"] = { "<Cmd>PR browse<CR>", "Open in the browser" },
  ["R"] = { "<Cmd>edit<CR>", "Reload" },
  ["<C-r>"] = { "<Cmd>edit<CR>", "Reload" },
  ["-"] = { "<Cmd>PR<CR>", "Pull request list" },
  ["q"] = { close, "Close" },
}

M.verbs = {
  D = { "<Cmd>PR draft<CR>", "Toggle draft" },
  M = { "<Cmd>PR merge<CR>", "Merge" },
  C = { "<Cmd>PR checkout<CR>", "Check out the branch" },
  X = { "<Cmd>PR close<CR>", "Close without merging" },
  A = { "<Cmd>PR mark<CR>", "Toggle mark" },
}

function M.notify(message, level) vim.notify("pr: " .. message, level or vim.log.levels.INFO) end

function M.status(value) return STATUS[value] or { " " } end

function M.age(time)
  if not time then return "" end
  local seconds = math.max(0, os.time() - time)
  for _, unit in ipairs(AGES) do
    if seconds >= unit[1] then return math.floor(seconds / unit[1]) .. unit[2] end
  end
  return seconds .. "s"
end

function M.wo(buf, options)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    for name, value in pairs(options) do
      vim.wo[win][0][name] = value
    end
  end
end

function M.render(buf, rows)
  local lines, views = {}, {}
  for i, row in ipairs(rows) do
    local text = {}
    for j, chunk in ipairs(row) do
      text[j] = chunk[1]
    end
    lines[i] = table.concat(text)
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    views[win] = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  end
  M.state[buf].rows = rows
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, row in ipairs(rows) do
    local col = 0
    for _, chunk in ipairs(row) do
      local stop = col + #chunk[1]
      if chunk[2] and stop > col then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col, { end_col = stop, hl_group = chunk[2] })
      end
      col = stop
    end
    if row.virt or row.hl then
      local mark = { virt_text = row.virt, virt_text_pos = "right_align", line_hl_group = row.hl }
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, mark)
    end
  end
  for win, view in pairs(views) do
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview(view)
      if vim.wo.previewwindow then
        vim.cmd.resize(math.min(vim.o.previewheight, vim.api.nvim_win_text_height(win, {}).all))
      end
    end)
  end
end

function M.message(buf, text, hl)
  local rows = {}
  for line in vim.gsplit(text or "unknown error", "\n", { plain = true }) do
    rows[#rows + 1] = { { line, hl } }
  end
  M.render(buf, rows)
end

function M.guard(buf, s)
  local tick = s.tick
  return function() return s.tick == tick and vim.api.nvim_buf_is_valid(buf) end
end

function M.current()
  local s = M.state[vim.api.nvim_get_current_buf()]
  return s, s and s.rows and s.rows[vim.fn.line "."]
end

function M.subject()
  local s, row = M.current()
  if s then return s.root, row and row.pr or s.pr end
  return M.last.root or git.root(), M.last.pr
end

function M.find(name) return vim.fn.bufnr("^" .. name .. "$") end

local function setup(buf, view)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  for lhs, map in pairs(vim.tbl_extend("keep", view.maps or {}, MAPS)) do
    vim.keymap.set("n", lhs, map[1], { buffer = buf, desc = map[2] })
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function() M.state[buf] = nil end,
  })
  M.wo(buf, { wrap = false })
  if view.setup then view.setup(buf) end
  vim.bo[buf].filetype = view.filetype or "pr"
end

function M.read(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  for _, route in ipairs(ROUTES) do
    local id = name:match(route[1])
    if id then
      local s = M.state[buf]
      if not s then
        local view = require("pr." .. route[2])
        s = { root = pending or git.root(), kind = route[2], id = id, subject = route[3] and id, view = view, tick = 0 }
        M.state[buf] = s
        setup(buf, view)
      end
      s.tick = s.tick + 1
      if s.rows then M.render(buf, s.rows) end
      if not s.root then return M.message(buf, "not in a git repository", "ErrorMsg") end
      return s.view.read(buf, s)
    end
  end
  M.notify("no such buffer: " .. name, vim.log.levels.ERROR)
end

function M.refresh(name, reload)
  local buf = M.find(name)
  local s = M.state[buf]
  if not s then return end
  if reload then return M.read(buf) end
  s.view.draw(buf, s)
end

local function edit(name, root, pedit)
  pending = root
  if pedit then
    vim.cmd { cmd = "pedit", args = { vim.fn.fnameescape(name) }, mods = { split = "botright" } }
  else
    vim.cmd.edit(vim.fn.fnameescape(name))
  end
  pending = nil
end

function M.open(name)
  local current = M.current()
  local root = current and current.root or git.root()
  if not root then return M.notify("not in a git repository", vim.log.levels.ERROR) end
  local s = M.state[M.find(name)]
  local moved = s and s.root ~= root
  if moved then s.root = root end
  edit(name, root)
  if moved then M.read(vim.api.nvim_get_current_buf()) end
  return M.current()
end

function M.pane(kind)
  local s, row = M.current()
  local root = s and s.root or M.last.root
  local id = row and (row.pr and row.pr.number or row.sha and "commit/" .. row.sha)
    or s and s.subject
    or M.last.pr and M.last.pr.number
  if not id then return M.notify("no pull request here", vim.log.levels.WARN) end
  if kind == "threads" and not tonumber(id) then
    return M.notify("a commit has no conversation", vim.log.levels.WARN)
  end
  local name = ("pr://%s/%s"):format(id, kind)
  if vim.fn.bufwinid(M.find(name)) ~= -1 then return vim.cmd.pclose() end
  edit(name, root, true)
end

function M.enter(buf)
  local s = M.state[buf]
  if not s or s.kind ~= "review" then return end
  if s.pr then M.last = { root = s.root, pr = s.pr } end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    local kind = vim.wo[win].previewwindow and (name:match "^pr://.+/(checks)$" or name:match "^pr://.+/(threads)$")
    local target = kind and ("pr://%s/%s"):format(s.id, kind)
    if kind == "threads" and not tonumber(s.id) then
      vim.cmd.pclose()
    elseif target and target ~= name then
      vim.api.nvim_win_call(win, function() edit(target, s.root) end)
    end
  end
end

return M
