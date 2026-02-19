# hack

A lightweight git CLI that uses OpenAI to automate the repetitive parts of your workflow: naming branches, writing commit messages, and drafting pull requests.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Indemnity83/hack/main/hack -o /usr/local/bin/hack && chmod +x /usr/local/bin/hack
```

Or if you prefer `~/.local/bin` (no `sudo` required):

```bash
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/Indemnity83/hack/main/hack -o ~/.local/bin/hack && chmod +x ~/.local/bin/hack
```

Make sure the target directory is on your `$PATH`.

## Configuration

Set your OpenAI API key via environment variable or a config file:

```bash
# Option 1: environment variable (e.g. in ~/.zshrc)
export OPENAI_API_KEY='sk-proj-...'

# Option 2: config file
mkdir -p ~/.config/hack
echo 'OPENAI_API_KEY="sk-proj-..."' > ~/.config/hack/config
chmod 600 ~/.config/hack/config
```

To override the model (default: `gpt-5.2`):

```bash
export OPENAI_MODEL="gpt-4o"
```

## Dependencies

| Tool | Required | Used for |
|------|----------|----------|
| `git` | yes | everything |
| `curl` | yes | OpenAI API calls |
| `jq` | yes | JSON parsing |
| `gh` | for `propose`, `done`, `prune`, `issue` | GitHub operations |
| `fzf` | no | improved selection UI |
| `git town` | no | branch parent tracking |

Install optional tools for the best experience:

```bash
brew install fzf gh git-town
```

## Commands

### `hack idea ["description"]`

Creates a new feature branch. AI suggests a branch name from your description; you confirm or edit it before the branch is created. If you have uncommitted changes, you can bring them along or stash them.

```bash
hack idea
hack idea "add dark mode toggle to settings page"
```

### `hack issue <number>`

Same as `idea`, but fetches the title and body from a GitHub issue to generate the branch name.

```bash
hack issue 42
```

### `hack commit`

Generates a commit message from your staged diff. If nothing is staged, offers to run `git add -p`. You can accept, edit, or cancel before the commit is made.

```bash
git add -p
hack commit
```

### `hack propose [remote]`

Creates or updates a GitHub PR for the current branch. Generates a conventional-commit title and a release-notes-style body from your commits, diff, and `CHANGELOG.md` (if present). Pushes the branch if needed.

```bash
hack propose           # targets origin (default)
hack propose upstream  # targets a different remote (fork workflow)
```

### `hack port [sha] [branch]`

Cherry-picks a commit onto another branch. Without arguments, shows an interactive list of recent commits from the default branch (uses `fzf` if available). Returns to your original branch when done.

```bash
hack port                        # interactive: pick commit and target branch
hack port abc1234                # cherry-pick onto current branch
hack port abc1234 release/v2     # cherry-pick onto a specific branch
hack port --continue             # resume after resolving conflicts
```

### `hack done`

Cleans up after a merged PR: deletes the remote branch, switches to the base branch, pulls latest, and deletes the local branch. Warns if the PR is still open or was closed without merging.

```bash
hack done
```

### `hack prune`

Bulk-deletes all local branches that have been fully merged into the default branch (plus their remote counterparts). Protected branches (`main`, `master`, the default branch, and any git-town perennials) are never deleted.

```bash
hack prune
```

## Git-Town integration

If `git town` is configured, `hack` respects it automatically:

- Uses `git-town.main-branch` as the default base
- Uses `git town hack` to create branches (preserves branch parent metadata)
- Reads `git-town-branch.<name>.parent` to find a branch's parent for `propose`
- Skips `git-town.perennial-branches` during `done` and `prune`
