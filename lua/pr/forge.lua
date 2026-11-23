local git = require "pr.git"

local M = {}

local STATUS = {
  success = "pass",
  failure = "fail",
  startup_failure = "fail",
  timed_out = "fail",
  error = "fail",
  in_progress = "running",
  running = "running",
  skipped = "skipped",
  neutral = "skipped",
  stale = "skipped",
  cancelled = "skipped",
}

local RANK = { fail = 1, running = 2, pending = 3, pass = 4, skipped = 5 }

local VERDICT = {
  APPROVED = "approved",
  CHANGES_REQUESTED = "changes",
  REQUEST_CHANGES = "changes",
  COMMENTED = "commented",
  COMMENT = "commented",
  DISMISSED = "dismissed",
}

local PR_FIELDS = "number,title,author,isDraft,isCrossRepository,baseRefName,baseRefOid,headRefName,headRefOid,"
  .. "updatedAt,url"

local CHECKS = [[
query($owner: String!, $repo: String!, $sha: String!) {
  repository(owner: $owner, name: $repo) {
    object(expression: $sha) {
      ... on Commit {
        statusCheckRollup {
          contexts(first: 100) {
            nodes {
              __typename
              ... on CheckRun {
                name status conclusion detailsUrl startedAt completedAt
                checkSuite { workflowRun { workflow { name } } }
              }
              ... on StatusContext { context state targetUrl createdAt }
            }
          }
        }
      }
    }
  }
}]]

local THREADS = [[
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      comments(first: 100) { nodes { author { login } body createdAt url } }
      reviews(first: 100) { nodes { author { login } state body submittedAt url } }
      reviewThreads(first: 100) {
        nodes {
          isResolved isOutdated path line originalLine
          comments(first: 100) { nodes { author { login } body createdAt url } }
        }
      }
    }
  }
}]]

local function github(root) return git.origin(root):find("github.com", 1, true) ~= nil end

local function status(value) return STATUS[tostring(value or ""):lower()] or "pending" end

local function epoch(iso)
  local y, mo, d, h, mi, s, zone = (iso or ""):match "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)[.%d]*(.*)$"
  if not y or tonumber(y) < 1970 then return nil end
  local utc = os.time { year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false }
  local sign, zh, zm = zone:match "^([+-])(%d%d):?(%d%d)$"
  local offset = sign and (sign == "-" and -1 or 1) * (zh * 3600 + zm * 60) or 0
  return utc + os.time() - os.time(os.date "!*t") - offset
end

local function failure(result, http)
  local text = vim.trim(http and result.stdout or (result.stderr ~= "" and result.stderr or result.stdout))
  local ok, body = pcall(vim.json.decode, text)
  if ok and type(body) == "table" and type(body.message) == "string" then text = body.message end
  if text ~= "" then return text end
  return http and ("HTTP " .. http) or ("exit code " .. result.code)
end

local function run(root, cmd, cb)
  if vim.fn.executable(cmd[1]) == 0 then return cb(nil, cmd[1] .. " is not installed") end
  vim.system(
    cmd,
    { cwd = root, text = true },
    vim.schedule_wrap(function(result)
      local http = tonumber(result.stderr:match ".*HTTP/[%d.]+ (%d%d%d)")
      if result.code == 0 and (not http or http < 300) then return cb(result.stdout) end
      cb(nil, failure(result, http))
    end)
  )
end

local function json(root, cmd, cb)
  run(root, cmd, function(out, err)
    if not out then return cb(nil, err) end
    local ok, data = pcall(vim.json.decode, out, { luanil = { object = true, array = true } })
    if not ok or type(data) ~= "table" then return cb(nil, "unreadable response from " .. cmd[1]) end
    cb(data)
  end)
end

local function endpoint(root)
  local slug = git.origin(root):gsub("%.git$", ""):match "[^/:]+/[^/:]+$"
  return "/repos/" .. (slug or "{owner}/{repo}")
end

local function api(root, path, ...)
  local cmd = github(root) and { "gh", "api", "repos/{owner}/{repo}/" .. path }
    or { "tea", "api", "-i", endpoint(root) .. "/" .. path }
  return vim.list_extend(cmd, { ... })
end

local function graphql(root, query, variable, cb)
  local cmd = { "gh", "api", "graphql", "-F", "owner={owner}", "-F", "repo={repo}", "-f", "query=" .. query }
  json(root, vim.list_extend(cmd, variable), function(data, err)
    if not data then return cb(nil, err) end
    if data.errors then return cb(nil, data.errors[1].message) end
    cb(data.data.repository)
  end)
end

local function login(user) return user and user.login or "?" end

local function from_github(pr)
  return {
    number = pr.number,
    title = pr.title,
    author = login(pr.author),
    draft = pr.isDraft,
    fork = pr.isCrossRepository,
    base = pr.baseRefOid,
    base_ref = pr.baseRefName,
    head = pr.headRefOid,
    head_ref = pr.headRefName,
    updated = epoch(pr.updatedAt),
    url = pr.url,
  }
end

local function from_gitea(pr)
  return {
    number = pr.number,
    title = pr.title,
    author = login(pr.user),
    draft = pr.draft,
    fork = pr.head.repo_id ~= pr.base.repo_id,
    base = pr.merge_base ~= "" and pr.merge_base or pr.base.sha,
    base_ref = pr.base.ref,
    head = pr.head.sha,
    head_ref = pr.head.ref,
    updated = epoch(pr.updated_at),
    url = pr.html_url,
  }
end

function M.prs(root, cb)
  if github(root) then
    return json(
      root,
      { "gh", "pr", "list", "--limit", "100", "--json", PR_FIELDS },
      function(prs, err) cb(prs and vim.tbl_map(from_github, prs), err) end
    )
  end
  json(
    root,
    api(root, "pulls?state=open&limit=50"),
    function(prs, err) cb(prs and vim.tbl_map(from_gitea, prs), err) end
  )
end

function M.pr(root, number, cb)
  if github(root) then
    return json(
      root,
      { "gh", "pr", "view", tostring(number), "--json", PR_FIELDS },
      function(pr, err) cb(pr and from_github(pr), err) end
    )
  end
  json(root, api(root, "pulls/" .. number), function(pr, err) cb(pr and from_gitea(pr), err) end)
end

local webs = {}

function M.web(root, cb)
  if webs[root] then return cb(webs[root]) end
  local cmd = github(root) and { "gh", "repo", "view", "--json", "url" } or { "tea", "api", "-i", endpoint(root) }
  json(root, cmd, function(data)
    webs[root] = data and (data.url or data.html_url)
    cb(webs[root])
  end)
end

function M.me(root, cb)
  local cmd = github(root) and { "gh", "api", "user" } or { "tea", "api", "-i", "/user" }
  json(root, cmd, function(user) cb(user and user.login) end)
end

local function github_checks(root, sha, cb)
  graphql(root, CHECKS, { "-f", "sha=" .. sha }, function(repo, err)
    if not repo then return cb(nil, err) end
    local jobs, seen = {}, {}
    for _, node in ipairs(vim.tbl_get(repo, "object", "statusCheckRollup", "contexts", "nodes") or {}) do
      local job
      if node.__typename == "CheckRun" then
        job = {
          id = tonumber((node.detailsUrl or ""):match "/job/(%d+)"),
          name = node.name,
          workflow = vim.tbl_get(node, "checkSuite", "workflowRun", "workflow", "name"),
          url = node.detailsUrl,
          status = status(node.conclusion or node.status),
          started = epoch(node.startedAt),
          finished = epoch(node.completedAt),
        }
      else
        job =
          { name = node.context, url = node.targetUrl, status = status(node.state), started = epoch(node.createdAt) }
      end
      local key = (job.workflow or "") .. "\n" .. job.name
      local at = seen[key]
      if not at then
        jobs[#jobs + 1] = job
        seen[key] = #jobs
      elseif (job.started or 0) >= (jobs[at].started or 0) then
        jobs[at] = job
      end
    end
    cb(jobs)
  end)
end

local function gitea_checks(root, sha, cb, runs_only)
  json(root, api(root, "actions/runs?head_sha=" .. sha), function(data, err)
    if not data then return cb(nil, err) end
    local runs, jobs = data.workflow_runs or {}, {}
    local left = #runs
    if runs_only or left == 0 then
      for _, run in ipairs(runs) do
        jobs[#jobs + 1] = { name = run.workflow_id, url = run.html_url, status = status(run.status) }
      end
      return cb(jobs)
    end
    for _, run in ipairs(runs) do
      json(root, api(root, ("actions/runs/%d/jobs"):format(run.id)), function(rows)
        for _, job in ipairs(rows or {}) do
          jobs[#jobs + 1] = {
            id = job.id,
            name = job.name,
            workflow = run.workflow_id:gsub("%.ya?ml$", ""),
            url = job.html_url,
            status = status(job.status),
            started = epoch(run.started),
          }
        end
        left = left - 1
        if left == 0 then cb(jobs) end
      end)
    end
  end)
end

function M.checks(root, sha, cb, runs_only)
  if github(root) then return github_checks(root, sha, cb) end
  gitea_checks(root, sha, cb, runs_only)
end

function M.rollup(jobs)
  local worst
  for _, job in ipairs(jobs) do
    if not worst or RANK[job.status] < RANK[worst] then worst = job.status end
  end
  return worst
end

function M.sort(jobs)
  for i, job in ipairs(jobs) do
    job.order = i
  end
  table.sort(jobs, function(a, b)
    if a.status ~= b.status then return RANK[a.status] < RANK[b.status] end
    return a.order < b.order
  end)
end

local settled = {}

function M.statuses(root, shas, each, fresh)
  local queue = {}
  for _, sha in ipairs(shas) do
    if settled[sha] ~= nil and not fresh then
      each(sha, settled[sha])
    else
      queue[#queue + 1] = sha
    end
  end
  local function work()
    local sha = table.remove(queue, 1)
    if not sha then return end
    M.checks(root, sha, function(jobs)
      local rollup = jobs and M.rollup(jobs) or false
      if jobs and rollup ~= "running" and rollup ~= "pending" then settled[sha] = rollup end
      each(sha, rollup)
      work()
    end, true)
  end
  for _ = 1, 6 do
    work()
  end
end

local raw = "--allow-escape-sequences"
local needs_raw = false

function M.job_log(root, id, cb)
  local cmd = api(root, ("actions/jobs/%d/logs"):format(id))
  if needs_raw and github(root) then cmd[#cmd + 1] = raw end
  run(root, cmd, function(out, err)
    if out or needs_raw or not err:find(raw, 1, true) then return cb(out, err) end
    needs_raw = true
    M.job_log(root, id, cb)
  end)
end

function M.steps(root, id, cb)
  if not github(root) then return cb(nil) end
  json(root, api(root, "actions/jobs/" .. id), function(job)
    local steps = {}
    for _, step in ipairs(job and job.steps or {}) do
      steps[#steps + 1] = { name = step.name, status = status(step.conclusion or step.status) }
    end
    cb(job and steps)
  end)
end

local function comment(author, body, time) return { author = login(author), body = body or "", time = epoch(time) } end

local function review(state, author, body, time, url)
  local verdict = VERDICT[state]
  if not verdict or (verdict == "commented" and (body or "") == "") then return nil end
  return { verdict = verdict, url = url, comments = { comment(author, body, time) } }
end

local function github_threads(root, number, cb)
  graphql(root, THREADS, { "-F", "number=" .. number }, function(repo, err)
    local pr = repo and repo.pullRequest
    if not pr then return cb(nil, err or ("no pull request #" .. number)) end
    local items = {}
    for _, node in ipairs(pr.comments.nodes) do
      items[#items + 1] = { url = node.url, comments = { comment(node.author, node.body, node.createdAt) } }
    end
    for _, node in ipairs(pr.reviews.nodes) do
      items[#items + 1] = review(node.state, node.author, node.body, node.submittedAt, node.url)
    end
    for _, node in ipairs(pr.reviewThreads.nodes) do
      local comments = {}
      for _, reply in ipairs(node.comments.nodes) do
        comments[#comments + 1] = comment(reply.author, reply.body, reply.createdAt)
      end
      if comments[1] then
        items[#items + 1] = {
          path = node.path,
          line = node.line or node.originalLine,
          resolved = node.isResolved or node.isOutdated,
          url = node.comments.nodes[1].url,
          comments = comments,
        }
      end
    end
    cb(items)
  end)
end

local function hunk_line(hunk)
  local line = tonumber((hunk or ""):match "^@@ %-%d+[,%d]* %+(%d+)")
  if not line then return nil end
  local last = line
  for body in hunk:gmatch "\n([^\n]+)" do
    if body:sub(1, 1) ~= "-" then
      last = line
      line = line + 1
    end
  end
  return last
end

local function gitea_threads(root, number, cb)
  local items, threads, left, failed = {}, {}, 2, nil
  local function done(err)
    failed = failed or err
    left = left - 1
    if left > 0 then return end
    for _, thread in pairs(threads) do
      table.sort(thread.comments, function(a, b) return (a.time or 0) < (b.time or 0) end)
      thread.resolved = thread.comments[#thread.comments].resolved
      items[#items + 1] = thread
    end
    if failed and not items[1] then return cb(nil, failed) end
    cb(items)
  end
  json(root, api(root, ("issues/%d/comments"):format(number)), function(rows, err)
    for _, row in ipairs(rows or {}) do
      items[#items + 1] = { url = row.html_url, comments = { comment(row.user, row.body, row.created_at) } }
    end
    done(err)
  end)
  json(root, api(root, ("pulls/%d/reviews"):format(number)), function(rows, err)
    for _, row in ipairs(rows or {}) do
      items[#items + 1] = review(row.state, row.user, row.body, row.submitted_at, row.html_url)
      if (row.comments_count or 0) > 0 then
        left = left + 1
        json(root, api(root, ("pulls/%d/reviews/%d/comments"):format(number, row.id)), function(replies, reply_err)
          for _, reply in ipairs(replies or {}) do
            local line = hunk_line(reply.diff_hunk)
            local key = reply.path .. ":" .. (line or reply.position or 0)
            threads[key] = threads[key] or { path = reply.path, line = line, url = reply.html_url, comments = {} }
            local entry = comment(reply.user, reply.body, reply.created_at)
            entry.resolved = reply.resolver ~= nil
            table.insert(threads[key].comments, entry)
          end
          done(reply_err)
        end)
      end
    end
    done(err)
  end)
end

function M.threads(root, number, cb)
  if github(root) then return github_threads(root, number, cb) end
  gitea_threads(root, number, cb)
end

function M.merge_styles(root, cb)
  local function pick(default, allowed)
    local styles = {}
    for _, style in ipairs { default or "", "squash", "merge", "rebase" } do
      if allowed[style] and not vim.list_contains(styles, style) then styles[#styles + 1] = style end
    end
    cb(styles[1] and styles or { "squash", "merge", "rebase" })
  end
  if github(root) then
    local fields = "viewerDefaultMergeMethod,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed"
    return json(root, { "gh", "repo", "view", "--json", fields }, function(settings)
      settings = settings or {}
      pick((settings.viewerDefaultMergeMethod or ""):lower(), {
        squash = settings.squashMergeAllowed,
        merge = settings.mergeCommitAllowed,
        rebase = settings.rebaseMergeAllowed,
      })
    end)
  end
  json(root, { "tea", "api", "-i", endpoint(root) }, function(settings)
    settings = settings or {}
    pick(settings.default_merge_style, {
      squash = settings.allow_squash_merge,
      merge = settings.allow_merge_commits,
      rebase = settings.allow_rebase,
    })
  end)
end

function M.merge(root, pr, style, auto, cb)
  local cmd
  if github(root) then
    cmd = { "gh", "pr", "merge", tostring(pr.number), "--" .. style }
    if auto then cmd[#cmd + 1] = "--auto" end
  else
    cmd = api(root, ("pulls/%d/merge"):format(pr.number), "-X", "POST", "-f", "Do=" .. style)
    if auto then vim.list_extend(cmd, { "-F", "merge_when_checks_succeed=true" }) end
  end
  run(root, cmd, cb)
end

function M.close(root, pr, cb)
  if github(root) then return run(root, { "gh", "pr", "close", tostring(pr.number) }, cb) end
  run(root, api(root, "pulls/" .. pr.number, "-X", "PATCH", "-f", "state=closed"), cb)
end

function M.draft(root, pr, draft, cb)
  if github(root) then
    local cmd = { "gh", "pr", "ready", tostring(pr.number) }
    if draft then cmd[#cmd + 1] = "--undo" end
    return run(root, cmd, cb)
  end
  local title = pr.title:gsub("^WIP:%s*", ""):gsub("^%[WIP%]%s*", "")
  run(root, api(root, "pulls/" .. pr.number, "-X", "PATCH", "-f", "title=" .. (draft and "WIP: " or "") .. title), cb)
end

return M
