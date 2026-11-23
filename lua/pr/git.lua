local M = {}

local function git(root, args, cb)
  local cmd = { "git", "--no-optional-locks", "-c", "core.quotePath=false" }
  if root then vim.list_extend(cmd, { "-C", root }) end
  vim.list_extend(cmd, args)
  if not cb then
    local result = vim.system(cmd, { text = true }):wait()
    return result.code == 0 and result.stdout or nil
  end
  vim.system(
    cmd,
    { text = true },
    vim.schedule_wrap(function(result) cb(result.code == 0, vim.trim(result.stderr)) end)
  )
end

local function lines(root, args) return vim.split(git(root, args) or "", "\n", { trimempty = true }) end

function M.root()
  local out = git(nil, { "rev-parse", "--show-toplevel" })
  return out and vim.trim(out)
end

function M.origin(root)
  local out = git(root, { "config", "--get", "remote.origin.url" })
  return out and vim.trim(out) or ""
end

function M.rev(root, ref)
  local out = git(root, { "rev-parse", "--verify", "--quiet", ref .. "^{commit}" })
  return out and vim.trim(out)
end

function M.log(root, args)
  local commits = {}
  for _, line in ipairs(lines(root, vim.list_extend({ "log", "--format=%h%x09%H%x09%an%x09%at%x09%s" }, args))) do
    local sha, full, author, time, subject = line:match "^(%x+)\t(%x+)\t(.-)\t(%d+)\t(.*)$"
    if sha then
      commits[#commits + 1] = { sha = sha, full = full, author = author, time = tonumber(time), subject = subject }
    end
  end
  return commits
end

function M.files(root, range)
  local raw, stat = {}, {}
  for _, line in ipairs(lines(root, { "diff", "--raw", "--numstat", "-M", range })) do
    table.insert(line:sub(1, 1) == ":" and raw or stat, line)
  end
  local files = {}
  for i, line in ipairs(raw) do
    local status, rest = line:match "^:%S+ %S+ %S+ %S+ (%a)%d*\t(.+)$"
    local old, path = rest:match "^(.+)\t(.+)$"
    local add, del = (stat[i] or ""):match "^(%S+)\t(%S+)\t"
    files[i] = {
      status = status,
      path = path or rest,
      old = old,
      add = tonumber(add) or 0,
      del = tonumber(del) or 0,
      binary = add == "-",
    }
  end
  return files
end

function M.diff(root, range, file)
  local out =
    lines(root, { "diff", "--no-color", "--no-ext-diff", "-M", range, "--", file.old or file.path, file.path })
  for i, line in ipairs(out) do
    if line:find "^@@" then return vim.list_slice(out, i) end
  end
  return {}
end

function M.sync(root, pr, cb)
  local ref = "refs/pr/" .. pr.number
  local function base(ok, err)
    if not ok or M.rev(root, pr.base) then return cb(ok, err) end
    git(root, { "fetch", "origin", pr.base_ref }, cb)
  end
  if M.rev(root, ref) == pr.head then return base(true) end
  git(root, { "fetch", "origin", ("+refs/pull/%d/head:%s"):format(pr.number, ref) }, base)
end

function M.checkout(root, pr, cb)
  local branch, ref = pr.head_ref, "refs/pr/" .. pr.number
  if M.rev(root, "refs/heads/" .. branch) and not git(root, { "merge-base", "--is-ancestor", branch, ref }) then
    return cb(false, ("branch %s has commits that are not in #%d"):format(branch, pr.number))
  end
  git(root, { "checkout", "-B", branch, ref }, function(ok, err)
    if ok and M.rev(root, "refs/remotes/origin/" .. branch) then
      git(root, { "branch", "--set-upstream-to=origin/" .. branch, branch })
    end
    cb(ok, err)
  end)
end

local function worktree(root)
  local name = vim.fs.basename(root) .. "-" .. vim.fn.sha256(root):sub(1, 8)
  return vim.fs.joinpath(vim.fn.stdpath "cache", "pr", name)
end

function M.worktree(root, sha, cb)
  local dir = worktree(root)
  if M.rev(dir, "HEAD") == sha then return cb(dir) end
  local function done(ok, err)
    if ok then vim.cmd.checktime() end
    cb(ok and dir or nil, err)
  end
  if vim.uv.fs_stat(dir) then
    git(dir, { "checkout", "--detach", sha }, done)
  else
    git(root, { "worktree", "prune" })
    git(root, { "worktree", "add", "--detach", dir, sha }, done)
  end
  return true
end

function M.clean(root, force, cb)
  local dir = worktree(root)
  if not vim.uv.fs_stat(dir) then return cb(true) end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.startswith(vim.api.nvim_buf_get_name(buf), dir .. "/") then
      pcall(vim.api.nvim_buf_delete, buf, { force = force })
    end
  end
  git(root, vim.list_extend({ "worktree", "remove" }, force and { "--force", dir } or { dir }), cb)
end

return M
