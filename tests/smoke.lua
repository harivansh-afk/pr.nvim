local failures = 0

local function check(name, ok, detail)
  if not ok then failures = failures + 1 end
  print(
    ("%-58s %s%s"):format(name, ok and "ok" or "FAIL", not ok and detail ~= nil and ("  " .. vim.inspect(detail)) or "")
  )
end

local function git(dir, ...)
  local result = vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end

local function repo(origin)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  git(dir, "init", "-q", "-b", "main")
  git(dir, "config", "user.name", "Test")
  git(dir, "config", "user.email", "test@example.com")
  git(dir, "remote", "add", "origin", origin)
  vim.fn.writefile({ "one", "two", "three" }, dir .. "/a.txt")
  git(dir, "add", ".")
  git(dir, "commit", "-q", "-m", "first")
  git(dir, "checkout", "-q", "-b", "feature")
  vim.fn.writefile({ "one", "TWO", "three", "four" }, dir .. "/a.txt")
  git(dir, "commit", "-q", "-am", "change a")
  vim.fn.writefile({ "return 1" }, dir .. "/b.lua")
  git(dir, "add", ".")
  git(dir, "commit", "-q", "-m", "add b")
  git(dir, "update-ref", "refs/pr/7", "HEAD")
  git(dir, "checkout", "-q", "main")
  return vim.uv.fs_realpath(dir), git(dir, "rev-parse", "main"), git(dir, "rev-parse", "feature")
end

local root, base, head = repo "https://git.example.com/o/r.git"
local hub = repo "git@github.com:o/r.git"

local LOG = table.concat({
  "2026-01-01T00:00:00.0000000Z ##[group]Build",
  "2026-01-01T00:00:01.0000000Z \27[1;32mcompiled\27[0m ok",
  "2026-01-01T00:00:02.0000000Z ##[endgroup]",
  "2026-01-01T00:00:03.0000000Z ##[error]it broke",
}, "\n")

local function pull(number, title, head_ref, base_ref, sha, draft)
  return {
    number = number,
    title = title,
    draft = draft,
    state = "open",
    user = { login = "hari" },
    updated_at = "2026-01-01T02:00:00+02:00",
    html_url = "https://git.example.com/o/r/pulls/" .. number,
    merge_base = base,
    base = { ref = base_ref, sha = base, repo_id = 1 },
    head = { ref = head_ref, sha = sha, repo_id = 1 },
  }
end

local ROUTES = {
  {
    "pulls%?state=open",
    { pull(9, "child", "child", "feature", base), pull(7, "WIP: parent", "feature", "main", head, true) },
  },
  { "pulls/7/merge", "" },
  { "PATCH", "{}" },
  { "pulls/7$", pull(7, "WIP: parent", "feature", "main", head, true) },
  { "/user$", { login = "hari" } },
  { "actions/runs%?head_sha=" .. head, { workflow_runs = { { id = 3, workflow_id = "ci.yml", status = "failure" } } } },
  { "actions/runs%?head_sha=", { workflow_runs = {} } },
  {
    "actions/runs/3/jobs",
    { { id = 4, name = "lint", status = "success" }, { id = 5, name = "test", status = "failure" } },
  },
  { "actions/jobs/5/logs", LOG },
  { "issues/7/comments", { { user = { login = "ann" }, body = "looks fine", created_at = "2026-01-01T00:00:00Z" } } },
  { "pulls/7/reviews$", { { id = 2, state = "APPROVED", user = { login = "bob" }, body = "", comments_count = 1 } } },
  {
    "pulls/7/reviews/2/comments",
    { { path = "a.txt", diff_hunk = "@@ -1,3 +1,4 @@\n one\n-two\n+TWO", body = "why?", user = { login = "bob" } } },
  },
  {
    "/repos/o/r$",
    {
      html_url = "https://git.example.com/o/r",
      default_merge_style = "squash",
      allow_squash_merge = true,
      allow_rebase = true,
    },
  },
  {
    "gh pr list",
    {
      {
        number = 3,
        title = "hub",
        author = { login = "octo" },
        isDraft = false,
        state = "OPEN",
        baseRefName = "main",
        baseRefOid = base,
        headRefName = "x",
        headRefOid = head,
        updatedAt = "2026-01-01T00:00:00Z",
        url = "https://github.com/o/r/pull/3",
      },
    },
  },
  {
    "statusCheckRollup",
    {
      data = {
        repository = {
          object = {
            statusCheckRollup = {
              contexts = {
                nodes = {
                  {
                    __typename = "CheckRun",
                    name = "build",
                    status = "COMPLETED",
                    conclusion = "SUCCESS",
                    detailsUrl = "https://github.com/o/r/actions/runs/1/job/22",
                    startedAt = "2026-01-01T00:00:00Z",
                    completedAt = "2026-01-01T00:01:05Z",
                  },
                  { __typename = "StatusContext", context = "deploy", state = "PENDING" },
                },
              },
            },
          },
        },
      },
    },
  },
}

local calls = {}
local system = vim.system

vim.fn.executable = function() return 1 end

vim.system = function(cmd, opts, on_exit)
  if cmd[1] == "git" then return system(cmd, opts, on_exit) end
  local line = table.concat(cmd, " ")
  calls[#calls + 1] = line
  local result = { code = 0, stdout = "", stderr = cmd[1] == "tea" and "HTTP/2.0 404 Not Found" or "" }
  for _, route in ipairs(ROUTES) do
    if line:find(route[1]) then
      result.stdout = type(route[2]) == "string" and route[2] or vim.json.encode(route[2])
      result.stderr = cmd[1] == "tea" and "HTTP/2.0 200 OK" or ""
      break
    end
  end
  vim.schedule(function() on_exit(result) end)
end

local function called(pattern)
  for _, line in ipairs(calls) do
    if line:find(pattern) then return line end
  end
end

local function wait(cond) return vim.wait(3000, cond, 5) end
local function keys(lhs) vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "x", false) end
local function lines() return vim.api.nvim_buf_get_lines(0, 0, -1, false) end
local function name() return vim.api.nvim_buf_get_name(0) end
local function state() return require("pr.buf").state[vim.api.nvim_get_current_buf()] end
local function goto_line(pattern)
  for lnum, line in ipairs(lines()) do
    if line:find(pattern) then return vim.api.nvim_win_set_cursor(0, { lnum, 0 }) end
  end
  error("no line matches " .. pattern)
end
local function preview()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.wo[win].previewwindow then return win end
  end
end

check("startup has no errors", vim.v.errmsg == "", vim.v.errmsg)
check(":PR exists", vim.fn.exists ":PR" == 2)
check(
  "no global mappings",
  #vim.tbl_filter(function(map) return (map.rhs or ""):find "PR" end, vim.api.nvim_get_keymap "n") == 0
)
vim.cmd "runtime plugin/pr.lua"
check("one autocmd per event", #vim.api.nvim_get_autocmds { group = "pr" } == 2)
check("highlights are default links", vim.api.nvim_get_hl(0, { name = "PrPass" }).link == "DiagnosticOk")

local forge = require "pr.forge"
local seen
forge.prs(hub, function(prs) seen = prs end)
wait(function() return seen end)
check("github pull requests normalise", seen[1].number == 3 and seen[1].author == "octo" and seen[1].head == head, seen)
check("timestamps are true epochs", seen[1].updated == 1767225600, seen[1].updated)
seen = nil
forge.checks(hub, head, function(jobs) seen = jobs end)
wait(function() return seen end)
check("github checks normalise", seen[1].id == 22 and seen[1].status == "pass" and seen[2].status == "pending", seen)
check("check durations come from the forge", seen[1].finished - seen[1].started == 65)
check("the worst status wins", forge.rollup(seen) == "pending")
seen = nil
forge.pr(root, 404, function(pr, err) seen = { pr, err } end)
wait(function() return seen end)
check("a tea 404 is an error despite exit 0", seen[1] == nil and seen[2] == "HTTP 404", seen)

vim.cmd.cd(root)
vim.cmd.PR()
wait(function() return state().prs and state().rows[2].pr and state().rows[1].pr.status end)
check("the list is pr://list", name() == "pr://list" and vim.bo.buftype == "nofile" and vim.bo.filetype == "pr")
check("stacks render parent first", lines()[1]:find "#7" and lines()[2]:find "└ child", lines())
check("the list shows the commit status", lines()[1]:find "✗" ~= nil, lines()[1])
check("timezone offsets are honoured", state().rows[1].pr.updated == 1767225600, state().rows[1].pr.updated)

keys "A"
check("A marks the pull request", lines()[1]:find "#7    1 hari" ~= nil, lines()[1])
check("marks persist", vim.json.decode(vim.fn.readfile(vim.fn.stdpath "state" .. "/pr-marks.json")[1])[root][1] == 7)
vim.cmd "PR marks 1"
wait(function() return name() == "pr://7" and state().commits end)
check("a mark slot opens its pull request", name() == "pr://7")
check("the header names the pull request", lines()[1] == "PR:     #7 WIP: parent", lines()[1])
check("commits are listed oldest first", lines()[8]:find "change a" and lines()[9]:find "add b", lines())
check("files carry their status", lines()[12] == "M a.txt" and lines()[13] == "A b.lua", lines())

goto_line "^M a.txt"
keys "="
check("= expands the inline diff", lines()[13] == "@@ -1,3 +1,4 @@" and lines()[15] == "-two", lines())
keys "="
check("= collapses it again", lines()[13] == "A b.lua")
keys "]c"
check("]c selects the first commit", state().at == 1 and lines()[11]:find "^Files %(1%) %x+$" ~= nil, lines()[11])
keys "[c"
check("[c returns to the whole pull request", state().at == nil and lines()[11] == "Files (2)")
vim.cmd.edit()
wait(function() return state().tick == 2 and #lines() == 13 end)
check(":edit reloads in place", #lines() == 13, lines())

goto_line "^M a.txt"
keys "="
goto_line "^%+four"
keys "<CR>"
wait(function() return name():find "a.txt$" end)
check("<CR> opens the file from a worktree", name():find(vim.fn.stdpath "cache", 1, true) == 1, name())
check("on the line under the cursor", vim.fn.line "." == 4 and vim.fn.getline "." == "four", vim.fn.line ".")
check("the checkout was left alone", git(root, "rev-parse", "--abbrev-ref", "HEAD") == "main")
keys "<C-^>"

vim.cmd "PR checks"
wait(function() return preview() and require("pr.buf").state[vim.api.nvim_win_get_buf(preview())].jobs end)
local pane = vim.api.nvim_win_get_buf(preview())
local rows = vim.api.nvim_buf_get_lines(pane, 0, -1, false)
check("checks open in the preview window", vim.api.nvim_buf_get_name(pane) == "pr://7/checks")
check("the cursor stays in the review", name() == "pr://7")
check(
  "failures sort first",
  rows[1]:find "1 failing, 1/2 passing" and rows[2]:find "✗ test" and rows[3]:find "✓ lint",
  rows
)
check("the pane fits its content", vim.api.nvim_win_get_height(preview()) == 3)
vim.cmd.wincmd "P"
vim.api.nvim_win_set_cursor(0, { 2, 0 })
keys "="
wait(function() return #lines() > 4 end)
check("= shows the log tail", lines()[4] == "     compiled ok" and lines()[5] == "     it broke", lines())
keys "<CR>"
wait(function() return name() == "pr://job/5" and state().text end)
check("<CR> opens the job log beside the pane", name() == "pr://job/5" and not vim.wo.previewwindow)
check("escape sequences are stripped", lines()[2]:find "Z compiled ok$" ~= nil, lines()[2])
check("groups fold", vim.fn.foldclosed(1) == 1 and vim.fn.foldclosedend(1) == 3)
check("the cursor lands on the first error", vim.fn.line "." == 4)
keys "q"
check("q returns to the review", name() == "pr://7")
vim.cmd "PR checks"
check("the command toggles the pane", preview() == nil)

vim.cmd "PR threads"
wait(function() return preview() and require("pr.buf").state[vim.api.nvim_win_get_buf(preview())].items end)
vim.cmd.wincmd "P"
check("unresolved threads sort first", lines()[1]:find "● `a.txt:2`  bob" ~= nil, lines())
check("reviews and comments follow", table.concat(lines(), "\n"):find "ann commented.*bob approved" ~= nil, lines())
check("threads start folded", vim.fn.foldclosed(1) == 1)
keys "<CR>"
wait(function() return name():find "a.txt$" end)
check("<CR> on a thread jumps to its line", vim.fn.line "." == 2 and vim.fn.getline "." == "TWO")
vim.cmd.pclose()

local picked
vim.ui.select = function(items, opts, on_choice)
  picked = vim.tbl_map(opts.format_item, items)
  on_choice(items[3])
end
vim.cmd "PR merge"
wait(function() return called "pulls/7/merge" end)
check(
  "merge offers the allowed styles",
  vim.deep_equal(picked, { "squash", "rebase", "squash when checks pass", "rebase when checks pass" }),
  picked
)
check(
  "and sends the choice to the forge",
  called "Do=squash %-F merge_when_checks_succeed=true" ~= nil,
  called "pulls/7/merge"
)

vim.cmd "PR 7"
vim.cmd "PR draft"
wait(function() return called "PATCH" end)
check("a draft becomes ready by losing its prefix", called "PATCH %-f title=parent$" ~= nil, called "PATCH")

vim.cmd "PR log"
check("the log lists commits", name() == "pr://log" and lines()[1]:find "Test  first" ~= nil, lines())
local opened
vim.ui.open = function(url) opened = url end
keys "gx"
wait(function() return opened end)
check("gx opens the commit on the forge", opened == "https://git.example.com/o/r/commit/" .. base, opened)
keys "<CR>"
check(
  "<CR> reviews a commit",
  name():find "^pr://commit/%x+$" ~= nil and lines()[1]:find "^Commit: %x+ first$" ~= nil,
  lines()
)

vim.cmd "PR! clean"
wait(function() return not git(root, "worktree", "list"):find "\n" end)
check("clean removes the worktree", not git(root, "worktree", "list"):find "\n")

print(failures == 0 and "\npr smoke: ok" or ("\npr smoke: " .. failures .. " failures"))
vim.cmd(failures == 0 and "qall!" or "cquit")
