# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`hack` is a Zsh CLI utility that augments git workflows with OpenAI-powered assistance. It automates branch creation, commit message generation, and GitHub PR creation.

`hack` is a **generated file** — the source of truth is `src/`. Do not edit `hack` directly.

## Build System

```bash
make              # rebuild hack from src/
make check        # zsh -n syntax-check every source file
make test         # run the test suite
make install-hooks  # one-time: activate the pre-commit hook (per clone)
```

The pre-commit hook (`.githooks/pre-commit`) fires automatically when `src/` files are staged. It runs `make check`, `make test`, and `make`, then stages the rebuilt `hack`.

## Running

```bash
./hack --help
./hack idea -i "my feature idea"
```

## Configuration

```bash
export OPENAI_API_KEY="sk-proj-..."
export OPENAI_MODEL="gpt-4o"  # optional, defaults to gpt-5.2
```

Or place in `~/.config/hack/config`.

## Architecture

Source lives in `src/`, concatenated by the Makefile into the single-file `hack` distributable.

```
src/
  header.zsh          # shebang, config loading, constants
  utils.zsh           # die/info/ok, git basics, truncate_str, prompt_choice, sanitize_branch_name
  git-helpers.zsh     # _hack_config_get, fzf, default_base_branch, find_parent_branch, remote helpers
  branch.zsh          # stash-or-carry prompt, base branch selection, create_branch_and_checkout
  changelog.zsh       # changelog_excerpt, last_release_tag
  openai.zsh          # openai_response() — curl to api.openai.com/v1/responses, jq parsing
  output.zsh          # split_title_body() — NUL-separated title/body parsing
  commands/
    idea.zsh          # cmd_idea — branch name from free-text idea
    issue.zsh         # cmd_issue — branch name from GitHub issue (via gh CLI)
    commit.zsh        # cmd_commit — commit message from staged diff
    propose.zsh       # cmd_propose — create/update GitHub PR
    port.zsh          # cmd_port — cherry-pick with fzf selection
    done.zsh          # cmd_done — clean up merged branch
    prune.zsh         # cmd_prune — bulk-delete merged branches
    init.zsh          # cmd_init — interactive per-repo setup
  main.zsh            # main() dispatcher + help text
```

## Tests

```
tests/
  assert.zsh              # assert_eq, assert_contains, assert_max_len, summarize
  test_utils.zsh          # sanitize_branch_name, truncate_str
  test_output.zsh         # split_title_body
  test_git_helpers.zsh    # remote_to_gh_repo, default_base_branch, get_perennial_branches (uses temp git repos)
  test_init.zsh           # cmd_init (uses temp git repos, mocks prompt_choice)
```

Tests cover the pure/mockable functions. The interactive `cmd_*` functions are not unit-tested — they depend on user input and external services.

## Key Dependencies

Required: `git`, `curl`, `jq`, `zsh`
Optional (improve UX): `fzf` (interactive selection), `gh` (GitHub operations)

## Per-repo Configuration

Run `hack init` once per repo to set `hack.main-branch` and `hack.perennial-branches` in `.git/config`. These keys take priority over `git-town.*` equivalents (which are read as silent fallback for backward compatibility).

## Protected Branches

`cmd_done` and `cmd_prune` never delete: the default branch, `main`, `master`, or any perennial branches from `hack.perennial-branches` (or `git-town.perennial-branches` as fallback).
