# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`hack` is a single-file Zsh CLI utility (~1,200 lines) that augments git workflows with OpenAI-powered assistance. It automates branch creation, commit message generation, and GitHub PR creation.

## Running and Testing

There is no build system. The script is a standalone executable:

```bash
# Run directly
./hack --help
./hack idea -i "my feature idea"

# Syntax check (no test suite exists)
zsh -n hack
```

## Configuration

The script requires `~/.config/hack/config`:
```bash
export OPENAI_API_KEY="sk-proj-..."
export OPENAI_MODEL="gpt-4o"  # optional, defaults to gpt-5.2
```

## Architecture

The entire program lives in the single `hack` file with this structure:

**Configuration & constants** (lines ~19-31): Loads `~/.config/hack/config`, defines diff size limits (20k chars for commits, 50k for PRs).

**Utility functions** (lines ~33-281): Error handling (`die`, `info`, `ok`), git helpers, interactive prompts (`prompt_choice`, `confirm`, `select_with_fzf`), branch discovery (`default_base_branch`, `find_parent_branch`).

**Changelog support** (lines ~383-404): Extracts unreleased section from `CHANGELOG.md` for PR context.

**OpenAI integration** (lines ~406-475): `openai_response()` posts to `https://api.openai.com/v1/responses` using `curl`, parses with `jq`.

**Command dispatcher** (lines ~480+): `main()` routes to individual `cmd_*` functions:
- `cmd_idea` — generates branch name from a free-text idea
- `cmd_issue` — generates branch name from a GitHub issue (via `gh` CLI)
- `cmd_commit` — generates commit message from staged diff
- `cmd_propose` — creates/updates GitHub PR with AI-generated conventional commit title and release-notes-style body
- `cmd_port` — cherry-picks commits across branches with fzf-powered selection
- `cmd_done` — safely deletes a merged feature branch
- `cmd_prune` — bulk-deletes all merged non-protected branches

## Key Dependencies

Required: `git`, `curl`, `jq`, `zsh`
Optional (improve UX): `fzf` (interactive selection), `gh` (GitHub operations), `git town` (branch parent tracking)

## Git-Town Integration

The script respects git-town configuration when present: reads `main-branch`, `perennial-branches`, and branch parent relationships. Falls back to heuristics (`origin/HEAD`, common branch names) when git-town is not configured.

## Protected Branches

`cmd_done` and `cmd_prune` never delete: the default branch, `main`, `master`, or any git-town perennial branches.
