# pr.nvim

> Development, issues, and pull requests: [Forgejo](https://git.harivan.sh/harivansh-afk/pr.nvim). GitHub is a read-only mirror.

Review GitHub and Forgejo/Gitea pull requests in Neovim: the list, each pull request's commits and diffs, CI checks and job logs, review threads, and the real files in a worktree.

## Install

Requires Neovim 0.11+, Git, and an authenticated [`gh`](https://cli.github.com/) or [`tea`](https://gitea.com/gitea/tea) for the repository's `origin`.

Install `https://git.harivan.sh/harivansh-afk/pr.nvim` with your plugin manager, or as a native package:

```sh
git clone https://git.harivan.sh/harivansh-afk/pr.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/pr.nvim
```

After a native install, run `:helptags ALL` once. [`diffs.nvim`](https://github.com/barrettruth/diffs.nvim) is optional: it highlights inline diffs and provides the full diff review on `dd` and `dv`.

## Use

Run `:PR` in a Git repository, or start with `nvim +PR`. Press `g?` in any buffer for its mappings.

| Command | Does |
| --- | --- |
| `:PR` | List open pull requests |
| `:PR {number}` | Review one |
| `:PR log` | Commits of `HEAD` with their CI status |
| `:PR checks` | Toggle CI checks in the preview window |
| `:PR threads` | Toggle reviews and comments in the preview window |
| `:PR merge`, `draft`, `close`, `checkout`, `browse` | Act on the pull request under the cursor |
| `:PR mark`, `:PR marks` | Keep a short list of pull requests and jump between them |

Every view is a normal buffer (`pr://list`, `pr://12`, `pr://12/checks`), so `:edit` reloads it and `<C-^>` and the jumplist move between them. Nothing needs setup, and there are no global mappings: map `:PR` to the keys you want.

Opening a file checks the pull request out into a detached worktree under `stdpath("cache")/pr`, one per repository, so language servers work and your checkout is never touched. `:PR clean` removes it.

See `:help pr.nvim` for everything.

## Development

```sh
bash scripts/test.sh
stylua --check lua plugin tests
```

The tests run headless against fixture forge responses and need no account. `docs/design.md` explains how the parts fit.

Licensed under GPLv3.
