if vim.g.loaded_pr then return end
vim.g.loaded_pr = true

local HIGHLIGHTS = {
  PrHeader = "Label",
  PrHeading = "PreProc",
  PrNumber = "Number",
  PrDraft = "Comment",
  PrAuthor = "Identifier",
  PrRef = "Function",
  PrHash = "Identifier",
  PrStack = "Constant",
  PrMark = "Constant",
  PrMuted = "Comment",
  PrSelected = "Visual",
  PrAdded = "Added",
  PrDeleted = "Removed",
  PrChanged = "Changed",
  PrHunk = "Statement",
  PrPass = "DiagnosticOk",
  PrFail = "DiagnosticError",
  PrRunning = "DiagnosticWarn",
  PrPending = "Comment",
  PrSkipped = "Comment",
  PrAnsiRed = "DiagnosticError",
  PrAnsiGreen = "DiagnosticOk",
  PrAnsiYellow = "DiagnosticWarn",
  PrAnsiBlue = "DiagnosticInfo",
  PrAnsiMagenta = "Constant",
  PrAnsiCyan = "DiagnosticHint",
  PrAnsiBold = "Bold",
}

for name, link in pairs(HIGHLIGHTS) do
  vim.api.nvim_set_hl(0, name, { link = link, default = true })
end

vim.api.nvim_create_user_command("PR", function(opts) require("pr").command(opts) end, {
  nargs = "*",
  bang = true,
  complete = function(...) return require("pr").complete(...) end,
  desc = "Review pull requests",
})

local group = vim.api.nvim_create_augroup("pr", {})

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = group,
  pattern = "pr://*",
  nested = true,
  callback = function(args) require("pr.buf").read(args.buf) end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  pattern = "pr://*",
  nested = true,
  callback = function(args) require("pr.buf").enter(args.buf) end,
})
