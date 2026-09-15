if vim.g.loaded_pr then return end
vim.g.loaded_pr = true

local group = vim.api.nvim_create_augroup("pr", { clear = true })

--- `:e` on a pr:// buffer. Without a BufReadCmd nvim treats the name as a
--- file path, finds nothing, and leaves the buffer wiped - so the handler
--- IS the load: pr://list re-fetches the PR list, pr://files re-reads the
--- loaded PR from origin. Both adopt the current buffer (see ensure_buf),
--- which is what makes `:e pr://list` work from a cold session too.
vim.api.nvim_create_autocmd("BufReadCmd", {
  group = group,
  pattern = "pr://list",
  callback = function() require("pr.list").open(true) end,
})
vim.api.nvim_create_autocmd("BufReadCmd", {
  group = group,
  pattern = "pr://log",
  callback = function() require("pr.log").open(nil, true) end,
})
vim.api.nvim_create_autocmd("BufReadCmd", {
  group = group,
  pattern = "pr://files",
  callback = function()
    local mod = require "pr"
    if #mod.state.commits == 0 then return mod.list() end -- nothing loaded: the list is the entry point
    require("pr.view").open()
    mod.reload()
  end,
})
--- `:e` on the CI pane asks the forge again, which is exactly what R does.
vim.api.nvim_create_autocmd("BufReadCmd", {
  group = group,
  pattern = "pr://checks",
  callback = function()
    local pane = require "pr.ci.pane"
    if pane.is_open() then return pane.refresh() end
    pane.open()
  end,
})
--- Same contract for the conversation pane.
vim.api.nvim_create_autocmd("BufReadCmd", {
  group = group,
  pattern = "pr://threads",
  callback = function()
    local pane = require "pr.threads.pane"
    if pane.is_open() then return pane.refresh() end
    pane.open()
  end,
})

local SUBS = {
  list = "list",
  log = "log",
  clean = "clean",
  pick = "pick_pr",
  commit = "pick_commit",
  files = "files",
  checks = "checks",
  threads = "threads",
  mode = "toggle_mode",
  whole = "whole",
  reload = "reload",
  refspec = "refspec",
}

--- Every verb is a subcommand too (:PR merge, :PR draft, ...), resolved out
--- of pr.verbs so the table can never fall behind the keymaps.
local function resolve(sub)
  if SUBS[sub] then return require("pr")[SUBS[sub]] end
  local verbs = require "pr.verbs"
  for _, k in ipairs(verbs.KEYS) do
    if k[2] == sub then return verbs[k[2]] end
  end
end

vim.api.nvim_create_user_command("PR", function(opts)
  local sub = opts.args ~= "" and opts.args or "list"
  local fn = resolve(sub)
  if not fn then return vim.notify("pr: unknown subcommand " .. sub, vim.log.levels.ERROR) end
  fn()
end, {
  nargs = "?",
  complete = function()
    local subs = vim.tbl_keys(SUBS)
    for _, k in ipairs(require("pr.verbs").KEYS) do
      subs[#subs + 1] = k[2]
    end
    table.sort(subs)
    return subs
  end,
  desc = "PR review flow",
})
