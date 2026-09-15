#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export HOME="$work/home" XDG_CONFIG_HOME="$work/config"
export XDG_STATE_HOME="$work/state" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache"
export PR_TEST_ROOT="$root"

nvim --headless -u NONE -i NONE \
  --cmd 'lua vim.opt.rtp = { vim.env.PR_TEST_ROOT, vim.env.VIMRUNTIME }; vim.opt.packpath = { vim.env.VIMRUNTIME }; vim.o.loadplugins = true; vim.g.mapleader = " "' \
  -c 'lua dofile(vim.env.PR_TEST_ROOT .. "/tests/smoke.lua")' </dev/null
