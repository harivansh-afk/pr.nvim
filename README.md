# pr.nvim

> Development, issues, and pull requests: [Forgejo](https://git.harivan.sh/harivansh-afk/pr.nvim). GitHub is a read-only mirror.

Review GitHub and Forgejo/Gitea pull requests in Neovim: PR lists, commit navigation, file diffs, CI logs, review threads, and a persistent list of marked PRs.

## Install

Requires Neovim 0.11+, Git, and an authenticated [`gh`](https://cli.github.com/) or [`tea`](https://gitea.com/gitea/tea) CLI for the repository's `origin` remote.

Install with your plugin manager using this URL:

```
https://git.harivan.sh/harivansh-afk/pr.nvim
```

Or use Neovim's native packages:

```sh
git clone https://git.harivan.sh/harivansh-afk/pr.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/pr.nvim
```

After a native install, run `:helptags ALL` once to index the help.

Optional plugins, installed and loaded by your plugin manager:

- [`fzf-lua`](https://github.com/ibhagwan/fzf-lua) and `fzf` for `:PR pick` and `:PR commit`.
- [`diffs.nvim`](https://github.com/barrettruth/diffs.nvim) for the full diff review (`dd` / `dv`) and inline diff styling.

## Use

Open Neovim in a Git repository and run `:PR`, or launch with `nvim +PR`.
Press `g?` in a PR buffer for its mappings.

| Command | Opens or changes |
| --- | --- |
| `:PR` | Open pull requests |
| `:PR log` | Commit log |
| `:PR files` | Files in the selected PR or commit |
| `:PR checks` | CI checks and job logs |
| `:PR threads` | Comments and review threads |
| `:PR mode` | Cumulative / incremental diff |
| `:PR whole` | Whole PR diff |
| `:PR clean` | Remove clean review worktrees |

Commands and buffer-local mappings work without setup. To enable the global shortcuts:

```lua
require("pr").setup { keymaps = true }
```

These include `<C-p>` for the PR list, `<leader>gl` for commits, `]p` / `[p`
for PR navigation, `]c` / `[c` for commits, and `<C-e>` for marked PRs.
They replace existing mappings for those keys. See `:help pr-keymaps` for the full list.
For your own shortcuts, map commands or call functions such as `require("pr").list()`.

The first PR listing adds an `origin` pull-request fetch refspec to the local Git config.
Opening a file creates a detached review worktree under `.worktrees/pr-<number>`
or `.worktrees/pr-commit-<sha>`. Dirty review worktrees are kept when cleaning.
Marked PRs persist in `stdpath("state")/pr-marks.json`.

## Development

```sh
bash scripts/test.sh
stylua --check lua plugin tests
```

The headless tests isolate Neovim from personal configuration and other plugins;
forge responses are fixtures. They do not require a logged-in forge account.

Extracted from [Hari's Nix configuration](https://git.harivan.sh/harivansh-afk/nix)
at `c01fa6c`, retaining its GPLv3 license.
