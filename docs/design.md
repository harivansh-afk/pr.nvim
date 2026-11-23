# Design

## Buffers

A view is a buffer whose name says what it shows. `plugin/pr.lua` registers one `BufReadCmd` for `pr://*`; `pr.buf` matches the name against its route table, creates the buffer's state on first read and calls the view's `read`. Everything Neovim already does for buffers then works unchanged: `:edit` reloads, the alternate buffer and jumplist navigate, and `:pedit` gives checks and threads a preview window.

State lives in `pr.buf.state[bufnr]` and is dropped on `BufWipeout`. Each read bumps `tick`; `pr.buf.guard` returns a predicate that async callbacks check so a late answer never paints over a newer one. Checks, threads and job logs set `bufhidden=wipe`, so reopening one always asks the forge again and a hidden one stops polling.

A view builds rows. A row is a list of `{ text, highlight }` chunks plus named fields: `virt` for right-aligned virtual text, `hl` for a line highlight, and whatever the view needs to act on the row (`pr`, `file`, `job`, `item`, `url`). `pr.buf.render` writes them and keeps them, so a mapping reads the row under the cursor instead of parsing text.

| Module | Owns |
| --- | --- |
| `pr` | commands and the Lua functions behind them |
| `pr.buf` | routing, state, rendering, shared mappings, the preview pane |
| `pr.git` | every git call, the review worktree |
| `pr.forge` | every `gh` and `tea` call, normalised to one shape |
| `pr.list`, `pr.review`, `pr.log`, `pr.checks`, `pr.job`, `pr.threads` | one view each |
| `pr.marks` | the marks file |

## Git

Diffs come from local objects. Opening pull request N fetches `refs/pull/N/head` into `refs/pr/N` when the forge reports a head the local ref does not have; nothing is added to the repository's configuration. The base is a commit id from the forge, so merged and closed pull requests review the same way as open ones.

The whole pull request is `base...head`; one commit is `sha^..sha`.

## Forges

`origin`'s configured URL decides: `github.com` means `gh`, anything else `tea`. The configured URL is read rather than `git remote get-url`, which applies `insteadOf` rewrites. Web addresses always come from the forge, never from the remote.

Things learned the hard way:

- `tea` cannot name the repository when `origin` is a loopback URL such as `git@localhost:owner/repo`, so every `tea api` path carries the owner and repository read from `origin`, and nothing goes through `tea pr`.
- `tea api` exits 0 whatever the HTTP status. `-i` puts the status line on stderr, and that line is the verdict.
- On Gitea a draft is a title starting with `WIP:` or `[WIP]`. The API reports it as `draft`, but changing it means editing the title.
- `tea pr checkout` leaves a half-applied checkout on Forgejo, so checkout is plain git from `refs/pr/N`.
- Forgejo's combined commit status disagrees with its Actions runs (a crashed run reports success, a cancelled one failure). Only the runs API is used, and `?head_sha=` matches the full id only.
- Forgejo's jobs carry no times; a running job's elapsed time counts from its run's start.
- GitHub serves no log for a job that is still running, and none once it has expired.
- `gh api` refuses output containing escape sequences unless given `--allow-escape-sequences`, which older versions do not know. The flag is added after the first refusal.
- A review comment's line on Forgejo is derived from its `diff_hunk`, whose last line is the commented one.
- Fork pull requests are skipped as stack parents: their head branch names collide with the base repository's.

List and log statuses ask per commit, six at a time, and remember settled answers for the session.
