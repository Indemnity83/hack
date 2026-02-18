#!/usr/bin/env zsh
set -euo pipefail

# hack — lightweight git helper with OpenAI
#
# Subcommands (interactive):
#   hack idea [-i "my idea"]
#   hack commit
#   hack propose
#   hack port [commit-sha] [target-branch]  (defaults to current branch)
#   hack done
#   hack prune
#
# Dependencies:
#   git, curl, jq
#   propose/done/prune: gh (GitHub CLI)
#   optional: git town, fzf (better UI for selections)

# ---- CONFIG ----
# Load API key from environment or config file
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hack/config"

# Source config file if it exists (allows it to set defaults)
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Set model default
: "${OPENAI_MODEL:=gpt-5.2}"

# Hard safety limits so we don't accidentally ship massive diffs:
MAX_CHARS_DIFF_COMMIT=20000
MAX_CHARS_DIFF_PROPOSE=50000

# ---- UTIL ----
die() { print -r -- "❌ $*" >&2; exit 1; }
info() { print -r -- "ℹ️  $*" >&2; }
ok() { print -r -- "✅ $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

in_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

repo_root() {
  git rev-parse --show-toplevel
}

current_branch() {
  git branch --show-current
}

has_changes() {
  [[ -n "$(git status --porcelain)" ]]
}

has_staged_changes() {
  [[ -n "$(git diff --cached --name-only)" ]]
}

truncate_str() {
  # usage: truncate_str "$string" $maxchars
  local s="$1"
  local max="$2"

  if (( ${#s} > max )); then
    # zsh strings are 1-indexed for [start,end] slices
    print -r -- "${s[1,$max]}\n\n[...TRUNCATED...]\n"
  else
    print -r -- "$s"
  fi
}

prompt_choice() {
  # usage: prompt_choice "Question?" "default"
  local q="$1"
  local def="${2:-}"
  local ans=""
  if [[ -n "$def" ]]; then
    vared -p "$q [$def] " ans
    [[ -z "$ans" ]] && ans="$def"
  else
    vared -p "$q " ans
  fi
  print -r -- "$ans"
}

confirm() {
  # usage: confirm "Proceed?" ["y"|"n"]
  local ans
  local default="${2:-y}"
  ans="$(prompt_choice "$1 (y/n)" "$default")"
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

sanitize_branch_name() {
  # Convert to a safe kebab-case-ish branch name, keep it readable.
  # - lowercase
  # - replace illegal chars with '-'
  # - collapse repeats
  # - trim
  # - cap length
  local s="$1"
  s="${s:l}"
  s="${s//[^a-z0-9\/._-]/-}"
  s="$(print -r -- "$s" | tr -s '-')"
  s="$(print -r -- "$s" | sed -E 's/^-+//; s/-+$//; s/--+/-/g; s@//@/@g')"
  if (( ${#s} > 60 )); then
    s="${s:0:60}"
    s="$(print -r -- "$s" | sed -E 's/-+$//')"
  fi
  print -r -- "$s"
}

git_town_available() {
  git town --version >/dev/null 2>&1
}

fzf_available() {
  command -v fzf >/dev/null 2>&1
}

select_with_fzf() {
  # usage: select_with_fzf "prompt" [--preview "preview command with {}"]
  local prompt="$1"
  shift

  local preview_cmd=""
  if [[ "${1:-}" == "--preview" ]]; then
    preview_cmd="$2"
    shift 2
  fi

  if fzf_available; then
    local fzf_opts=(
      --height=40%
      --reverse
      --border
      --prompt="$prompt > "
      --pointer="▶"
      --marker="✓"
    )

    if [[ -n "$preview_cmd" ]]; then
      fzf_opts+=(--preview "$preview_cmd" --preview-window=right:60%:wrap)
    fi

    fzf "${fzf_opts[@]}"
  else
    # Fallback: just read first line from stdin
    head -n 1
  fi
}

default_base_branch() {
  # Priority order:
  # 1. git-town main-branch config (if git-town is configured)
  # 2. origin/HEAD symref
  # 3. Existing main/master branch
  # 4. Default to "main"
  local base

  # Check git-town config first
  base="$(git config git-town.main-branch 2>/dev/null || true)"
  if [[ -n "$base" ]]; then
    print -r -- "$base"
    return
  fi

  # Check origin/HEAD
  local ref
  ref="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$ref" ]]; then
    base="${ref#refs/remotes/origin/}"
    print -r -- "$base"
    return
  fi

  # Check for existing branches
  if git show-ref --verify --quiet refs/heads/main; then print -r -- "main"; return; fi
  if git show-ref --verify --quiet refs/heads/master; then print -r -- "master"; return; fi
  print -r -- "main"
}

find_parent_branch() {
  # usage: find_parent_branch <current-branch> <remote>
  # Returns the branch <current-branch> was most likely created from.
  # Priority:
  #   1. git-town explicit parent config
  #   2. Heuristic: local branch whose tip is the nearest ancestor of HEAD
  #   3. Remote's default branch
  local current="$1"
  local remote="$2"

  # 1. git-town stores the parent in git config
  local gt_parent
  gt_parent="$(git config "git-town-branch.${current}.parent" 2>/dev/null || true)"
  if [[ -n "$gt_parent" ]]; then
    print -r -- "$gt_parent"
    return
  fi

  # 2. Heuristic: among all local branches (except current), find the one
  #    whose tip is an ancestor of HEAD and has the fewest commits between
  #    it and HEAD (i.e. the most recent fork point = closest parent).
  local best_branch="" best_distance=2147483647
  local branches
  branches=(${(f)"$(git branch --format='%(refname:short)')"})
  local b b_sha mb ahead
  for b in $branches; do
    [[ "$b" == "$current" ]] && continue
    b_sha="$(git rev-parse "$b" 2>/dev/null || true)"
    [[ -z "$b_sha" ]] && continue
    mb="$(git merge-base HEAD "$b" 2>/dev/null || true)"
    # Branch tip must be a direct ancestor of HEAD (not diverged)
    [[ "$mb" != "$b_sha" ]] && continue
    ahead="$(git rev-list --count "${b_sha}..HEAD" 2>/dev/null || echo 2147483647)"
    if (( ahead < best_distance )); then
      best_distance=$ahead
      best_branch="$b"
    fi
  done
  if [[ -n "$best_branch" ]]; then
    print -r -- "$best_branch"
    return
  fi

  # 3. Fall back to the remote's default branch
  remote_default_branch "$remote"
}

remote_to_gh_repo() {
  # usage: remote_to_gh_repo <remote>
  # Returns "owner/repo" parsed from the remote's URL.
  # Handles SSH (git@github.com:owner/repo.git) and HTTPS URLs.
  local remote="$1"
  local url
  url="$(git remote get-url "$remote" 2>/dev/null)" \
    || die "No remote named: $remote"
  local repo
  repo="$(print -r -- "$url" \
    | sed -E 's|^git@[^:]+:||; s|^https?://[^/]+/||' \
    | sed 's|\.git$||')"
  [[ -n "$repo" ]] || die "Could not parse GitHub repo from remote URL: $url"
  print -r -- "$repo"
}

remote_default_branch() {
  # usage: remote_default_branch <remote>
  # Returns the default branch for the given remote, with fallbacks.
  local remote="${1:-origin}"
  local ref base

  # For origin, honour git-town config first
  if [[ "$remote" == "origin" ]]; then
    base="$(git config git-town.main-branch 2>/dev/null || true)"
    [[ -n "$base" ]] && { print -r -- "$base"; return; }
  fi

  # Check the remote's HEAD symref (may need a fetch to populate)
  ref="$(git symbolic-ref -q "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
  if [[ -z "$ref" ]]; then
    git fetch "$remote" --quiet 2>/dev/null || true
    ref="$(git symbolic-ref -q "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
  fi
  if [[ -n "$ref" ]]; then
    print -r -- "${ref#refs/remotes/$remote/}"
    return
  fi

  # Fallback: check known branch names on the remote
  if git show-ref --verify --quiet "refs/remotes/$remote/main";   then print -r -- "main";   return; fi
  if git show-ref --verify --quiet "refs/remotes/$remote/master"; then print -r -- "master"; return; fi
  print -r -- "main"
}

get_perennial_branches() {
  # Get all perennial branches from git-town config (space-separated list)
  git config git-town.perennial-branches 2>/dev/null || true
}

ensure_clean_or_handle_changes_for_new_branch() {
  if ! has_changes; then
    return
  fi

  info "Working tree has uncommitted changes."
  print -r -- "$(git status -sb)" >&2
  print -r -- "" >&2
  print -r -- "What do you want to do with these changes?" >&2
  print -r -- "  1) Bring them to the new branch (default)" >&2
  print -r -- "  2) Keep them here by stashing (new branch will be clean; stash remains)" >&2
  print -r -- "  3) Cancel" >&2

  local choice
  choice="$(prompt_choice "Choose 1/2/3:" "1")"
  case "$choice" in
    1)
      ok "Changes will come with you to the new branch."
      return
      ;;
    2)
      local msg="hack idea stash: $(date '+%Y-%m-%d %H:%M:%S')"
      git stash push -u -m "$msg" >/dev/null
      ok "Stashed changes: $msg"
      info "You can re-apply later with: git stash list && git stash pop"
      return
      ;;
    3) die "Cancelled." ;;
    *) die "Invalid choice." ;;
  esac
}

select_base_branch() {
  # Collects all perennial/default branches and prompts if more than one exists.
  local default_branch
  default_branch="$(default_base_branch)"

  local candidates=("$default_branch")
  local perennials
  perennials="$(get_perennial_branches)"
  if [[ -n "$perennials" ]]; then
    local p
    for p in ${(z)perennials}; do
      local found=0
      local c
      for c in "${candidates[@]}"; do
        [[ "$c" == "$p" ]] && found=1 && break
      done
      [[ $found -eq 0 ]] && candidates+=("$p")
    done
  fi

  if (( ${#candidates[@]} == 1 )); then
    print -r -- "${candidates[1]}"
    return
  fi

  info "Select a base branch:"
  if fzf_available; then
    print -r -- "${(j:\n:)candidates}" | select_with_fzf "Base branch"
  else
    local i=1
    local b
    for b in "${candidates[@]}"; do
      print -r -- "  $i) $b" >&2
      ((i++))
    done
    local choice
    choice="$(prompt_choice "Base branch (1-${#candidates[@]}):" "1")"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#candidates[@]} )); then
      print -r -- "${candidates[$choice]}"
    else
      print -r -- "${candidates[1]}"
    fi
  fi
}

create_branch_and_checkout() {
  local branch="$1"
  local base="${2:-}"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    die "Branch already exists locally: $branch"
  fi

  if git_town_available; then
    if [[ -n "$base" ]]; then
      git town hack --onto "$base" "$branch"
    else
      git town hack "$branch"
    fi
  else
    if [[ -n "$base" ]]; then
      git switch -c "$branch" "$base"
    else
      git switch -c "$branch"
    fi
  fi
}

# ---- CHANGELOG HELPERS ----
changelog_excerpt() {
  # Returns a useful excerpt from CHANGELOG.md, favoring "Unreleased" if present.
  local root file
  root="$(repo_root)"
  file="$root/CHANGELOG.md"
  [[ -f "$file" ]] || return 0

  local start
  start="$(grep -n -i -m1 '^##\s*\[?\s*unreleased' "$file" 2>/dev/null | cut -d: -f1 || true)"

  if [[ -n "$start" ]]; then
    sed -n "${start},$((start+200))p" "$file"
  else
    sed -n '1,200p' "$file"
  fi
}

last_release_tag() {
  # Best-effort: find the most recent tag reachable. If none, empty.
  git describe --tags --abbrev=0 2>/dev/null || true
}

# ---- OPENAI ----
openai_response() {
  # usage: openai_response "$instructions" "$input"
  local instructions="$1"
  local input="$2"

  if [[ -z "$OPENAI_API_KEY" ]]; then
    die "OPENAI_API_KEY not set. Set it via:
  1) Environment variable (add to ~/.zshrc or ~/.bashrc):
     export OPENAI_API_KEY='your-key-here'
  2) Config file at ${CONFIG_FILE}:
     echo 'OPENAI_API_KEY=\"your-key-here\"' > ${CONFIG_FILE}
     chmod 600 ${CONFIG_FILE}"
  fi

  # Trim whitespace/newlines from key (common when copy/pasting)
  local key
  key="$(print -r -- "$OPENAI_API_KEY" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [[ -n "$key" ]] || die "OPENAI_API_KEY is empty after trimming."

  local payload
  payload="$(jq -n \
    --arg model "$OPENAI_MODEL" \
    --arg instructions "$instructions" \
    --arg input "$input" \
    '{
      model: $model,
      instructions: $instructions,
      input: $input
    }')"

  local resp
  resp="$(curl -sS https://api.openai.com/v1/responses \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $key" \
    --data-raw "$payload")"

  # If the API returns an error object, show it and stop.
  local api_err
  api_err="$(print -r -- "$resp" | jq -r '.error.message // empty')"
  if [[ -n "$api_err" ]]; then
    info "Raw response:"
    print -r -- "$resp" >&2
    die "$api_err"
  fi

  # Extract ALL output text (not just the first line).
  local out
  out="$(print -r -- "$resp" | jq -r '
    (
      .output_text
      // (
        [ .output[]?.content[]? | select(.type=="output_text") | .text ]
        | join("\n")
      )
      // ""
    )
  ')"

  # Treat whitespace-only output as empty
  out="$(print -r -- "$out" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  [[ -n "$out" ]] || {
    info "Raw response:"
    print -r -- "$resp" >&2
    die "OpenAI response did not include output text."
  }

  print -r -- "$out"
}

# ---- OUTPUT HELPERS ----
split_title_body() {
  # usage: split_title_body "$text"
  # echoes title then NUL then body (for safe parsing)
  local text="$1"
  local title body
  title="$(print -r -- "$text" | head -n 1 | tr -d '\r')"
  body="$(
    print -r -- "$text" \
    | tail -n +2 \
    | sed -E 's/\r$//' \
    | sed -E '1{/^[[:space:]]*$/d;}' \
    | sed -E '1{/^[[:space:]]*$/d;}'
  )"
  title="$(print -r -- "$title" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  print -rn -- "$title"
  print -rn -- $'\0'
  print -r -- "$body"
}

# SUBCOMMAND: idea (interactive)
cmd_idea() {
  local idea="${1:-}"

  if [[ -z "$idea" ]]; then
    idea="$(prompt_choice "What are you planning to do? (short description)" "")"
    [[ -n "$idea" ]] || die "No idea provided."
  fi

  local base_branch
  base_branch="$(select_base_branch)"

  ensure_clean_or_handle_changes_for_new_branch

  local instructions input out branch
  instructions=$'You are a git assistant.\n\nTask:\n- Propose ONE git branch name for the user\'s idea.\n\nRules for the branch name:\n- output ONLY the branch name, nothing else\n- lowercase\n- kebab-case\n- may include "/" for grouping (optional)\n- no spaces\n- keep <= 60 characters\n- must be descriptive but concise\n\nExamples:\n- feature/add-meter-billing-ui\n- fix/authentik-oauth-profile-claim\n- chore/update-docker-compose\n'
  input="Idea:\n$idea\n\nContext:\n- Base branch: $base_branch\n- Repo: $(basename "$(repo_root)")\n"

  out="$(openai_response "$instructions" "$input" | head -n 1 | tr -d '\r')"
  branch="$(sanitize_branch_name "$out")"
  [[ -n "$branch" ]] || die "Model returned an empty branch name."

  info "Proposed branch: $branch"
  if ! confirm "Create and switch to '$branch'?"; then
    local manual
    manual="$(prompt_choice "Okay—enter the branch name you want to use:" "$branch")"
    branch="$(sanitize_branch_name "$manual")"
    [[ -n "$branch" ]] || die "Empty branch name."
  fi

  create_branch_and_checkout "$branch" "$base_branch"
  ok "Now on branch: $(current_branch)"
}

# SUBCOMMAND: issue (interactive)
cmd_issue() {
  need_cmd gh
  gh auth status >/dev/null 2>&1 || die "GitHub CLI not authenticated. Run: gh auth login"

  local issue_number="${1:-}"
  [[ -n "$issue_number" ]] || die "Usage: hack issue <number>"

  local issue_json
  issue_json="$(gh issue view "$issue_number" --json title,body)" \
    || die "Failed to fetch issue #$issue_number"

  local issue_title issue_body idea
  issue_title="$(print -r -- "$issue_json" | jq -r '.title')"
  issue_body="$(print -r -- "$issue_json" | jq -r '.body // ""')"

  idea="$(printf '%s\n\n%s' "$issue_title" "$issue_body")"
  idea="$(truncate_str "$idea" 1500)"
  [[ -n "$issue_title" ]] || die "Issue #$issue_number returned no title."

  info "Issue #$issue_number: $issue_title"

  local base_branch
  base_branch="$(select_base_branch)"

  ensure_clean_or_handle_changes_for_new_branch

  local instructions input out branch
  instructions=$'You are a git assistant.\n\nTask:\n- Propose ONE git branch name for the user\'s idea.\n\nRules for the branch name:\n- output ONLY the branch name, nothing else\n- lowercase\n- kebab-case\n- may include "/" for grouping (optional)\n- no spaces\n- keep <= 60 characters\n- must be descriptive but concise\n\nExamples:\n- feature/add-meter-billing-ui\n- fix/authentik-oauth-profile-claim\n- chore/update-docker-compose\n'
  input="Idea (from GitHub issue #${issue_number}):\n$idea\n\nContext:\n- Base branch: $base_branch\n- Repo: $(basename "$(repo_root)")\n"

  out="$(openai_response "$instructions" "$input" | head -n 1 | tr -d '\r')"
  branch="$(sanitize_branch_name "$out")"
  [[ -n "$branch" ]] || die "Model returned an empty branch name."

  info "Proposed branch: $branch"
  if ! confirm "Create and switch to '$branch'?"; then
    local manual
    manual="$(prompt_choice "Okay—enter the branch name you want to use:" "$branch")"
    branch="$(sanitize_branch_name "$manual")"
    [[ -n "$branch" ]] || die "Empty branch name."
  fi

  create_branch_and_checkout "$branch" "$base_branch"
  ok "Now on branch: $(current_branch)"
}

# SUBCOMMAND: commit (interactive)
cmd_commit() {
  has_staged_changes || {
    info "No staged changes."
    if confirm "Run 'git add -p' now?"; then
      git add -p
    fi
  }

  has_staged_changes || die "Still no staged changes. Stage changes and try again."

  local rawdiff diff_trunc instructions input msg
  rawdiff="$(git diff --cached)"
  diff_trunc="$(truncate_str "$rawdiff" "$MAX_CHARS_DIFF_COMMIT")"

  instructions=$'You are a meticulous git commit assistant.\n\nGiven a staged diff, output a SINGLE-LINE commit subject.\n\nRules:\n- Output ONLY the subject line\n- No conventional-commit prefix (no "feat:", no "fix:", etc.)\n- No scope, no body\n- Imperative mood (e.g. "Add", "Fix", "Refactor")\n- Aim for <= 72 characters\n- Be specific about what changed\n'
  input="Repo: $(basename "$(repo_root)")\nBranch: $(current_branch)\n\nSTAGED DIFF:\n$diff_trunc"

  msg="$(openai_response "$instructions" "$input" | head -n 1 | tr -d '\r')"
  msg="$(print -r -- "$msg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [[ -n "$msg" ]] || die "Empty commit message from model."

  info "Proposed commit message:"
  print -r -- "  $msg" >&2

  local choice
  print -r -- "" >&2
  print -r -- "Options: (y) commit, (e) edit, (n) cancel" >&2
  choice="$(prompt_choice "Choose y/e/n:" "y")"

  case "$choice" in
    y|Y)
      git commit -m "$msg"
      ok "Committed."
      ;;
    e|E)
      local manual
      manual="$(prompt_choice "Enter commit subject:" "$msg")"
      manual="$(print -r -- "$manual" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [[ -n "$manual" ]] || die "Empty message."
      git commit -m "$manual"
      ok "Committed."
      ;;
    n|N) die "Cancelled." ;;
    *) die "Invalid choice." ;;
  esac
}

# SUBCOMMAND: propose (interactive, uses gh)
cmd_propose() {
  need_cmd gh
  gh auth status >/dev/null 2>&1 || die "GitHub CLI not authenticated. Run: gh auth login"

  local remote="${1:-origin}"
  git remote get-url "$remote" >/dev/null 2>&1 || die "No remote named: $remote"

  local base branch
  branch="$(current_branch)"
  [[ -n "$branch" ]] || die "Detached HEAD; check out a branch first."
  base="$(find_parent_branch "$branch" "$remote")"

  # Ensure we have up-to-date refs for the target remote
  info "Proposing $branch → $remote/$base"
  info "Fetching $remote/$base..."
  git fetch "$remote" "$base" --quiet 2>/dev/null || true

  local last_tag
  last_tag="$(last_release_tag)"

  # gather commit history and diff vs remote base
  local remote_base_ref commits diffstat rawdiff diff_trunc
  remote_base_ref="$remote/$base"
  commits="$(git log --no-decorate --oneline "${remote_base_ref}..HEAD" 2>/dev/null || true)"
  [[ -n "$commits" ]] || die "No commits ahead of '$remote_base_ref'. Nothing to propose."

  # Use merge-base diff to represent "what this branch introduces"
  diffstat="$(git diff --stat "${remote_base_ref}...HEAD" || true)"
  rawdiff="$(git diff "${remote_base_ref}...HEAD" || true)"
  diff_trunc="$(truncate_str "$rawdiff" "$MAX_CHARS_DIFF_PROPOSE")"

  # changelog context
  local cl
  cl="$(changelog_excerpt || true)"

  local instructions input pr_message combined title body

  instructions=$'You are a senior engineer preparing a GitHub Pull Request message.\n\nGenerate a CONVENTIONAL COMMIT message (no scope) that accurately describes what this branch does.\n\nPR BODY STYLE (read like release notes):\n- Write the body like patch notes for users.\n- Focus on WHAT changed and WHY it matters.\n- Prefer short sections with headings like: Summary / Changes / Notes.\n- Use bullet points. Group related items. Keep it scannable.\n- Do NOT include low-level implementation details unless they affect behavior, compatibility, or contributors.\n\nOutput format:\n- Line 1: <type>: <description>\n- Blank line\n- Body: release-notes style (MUST NOT be empty)\n- Optional blank line + footer ONLY if BREAKING CHANGE (e.g. \"BREAKING CHANGE: ...\")\n\nValid types: feat, fix, refactor, perf, test, docs, build, ci, chore, revert\nNo scope in parentheses.\nDo not invent changes that aren’t in the commits/diff/changelog.\n'
  input="Repo: $(basename "$(repo_root)")\nBranch: $branch\nBase: $remote_base_ref\nLast release tag (best-effort): ${last_tag:-<none>}\n\nCOMMITS (${remote_base_ref}..HEAD):\n$commits\n\nDIFFSTAT (merge-base ${remote_base_ref}...HEAD):\n$diffstat\n\nCHANGELOG EXCERPT (if present):\n${cl:-<no changelog found>}\n\nDIFF (merge-base ${remote_base_ref}...HEAD, may be truncated):\n$diff_trunc"

  pr_message="$(openai_response "$instructions" "$input" | tr -d '\r')"
  combined="$(split_title_body "$pr_message")"
  title="${combined%%$'\0'*}"
  body="${combined#*$'\0'}"

  # One retry if the model returns title-only (common failure mode).
  if [[ -z "${body:-}" ]]; then
    info "Model returned an empty PR body; retrying with stricter instructions..."
    local instructions_retry
    instructions_retry=$'You are a senior engineer preparing a GitHub Pull Request message.\n\nReturn BOTH a conventional-commit title AND a non-empty PR body.\n\nOutput format:\n- Line 1: <type>: <description>\n- Blank line\n- Body with at least:\n  - A \"Summary\" heading (1-2 sentences)\n  - A \"Changes\" heading with 3-8 bullet points\n\nRules:\n- No scope in parentheses.\n- No code blocks.\n- Do not invent changes.\n'
    pr_message="$(openai_response "$instructions_retry" "$input" | tr -d '\r')"
    combined="$(split_title_body "$pr_message")"
    title="${combined%%$'\0'*}"
    body="${combined#*$'\0'}"
  fi

  title="$(print -r -- "$title" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [[ -n "$title" ]] || die "Model returned empty title."
  [[ -n "${body:-}" ]] || die "Model returned empty body (twice)."

  info "Proposed PR title:"
  print -r -- "  $title" >&2
  print -r -- "" >&2
  info "Proposed PR body (preview):"
  print -r -- "$body" | sed -n '1,40p' >&2
  if [[ "$(print -r -- "$body" | wc -l | tr -d ' ')" -gt 40 ]]; then
    print -r -- "  ... (truncated preview) ..." >&2
  fi

  if ! confirm "Use this title/body for the PR?"; then
    die "Cancelled."
  fi

  # ensure branch is pushed to origin (the fork)
  if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    info "No upstream set for this branch."
    if confirm "Push branch to origin and set upstream?"; then
      git push -u origin HEAD
    else
      die "Cannot create/update PR without a pushed branch."
    fi
  else
    git push >/dev/null 2>&1 || true
  fi

  # Build gh flags: when targeting a non-origin remote, point gh at that
  # repo and qualify --head as fork-owner:branch so GitHub routes it correctly.
  local gh_repo_args=()
  local gh_head="$branch"
  if [[ "$remote" != "origin" ]]; then
    local upstream_repo fork_owner
    upstream_repo="$(remote_to_gh_repo "$remote")"
    fork_owner="$(remote_to_gh_repo "origin")"
    fork_owner="${fork_owner%%/*}"
    gh_repo_args=(--repo "$upstream_repo")
    gh_head="${fork_owner}:${branch}"
  fi

  if gh pr view "${gh_repo_args[@]}" --json number >/dev/null 2>&1; then
    ok "Existing PR found for this branch. Updating title/body…"
    gh pr edit "${gh_repo_args[@]}" --title "$title" --body "$body"
    ok "PR updated."
  else
    ok "No PR found for this branch. Creating…"
    gh pr create "${gh_repo_args[@]}" --base "$base" --head "$gh_head" --title "$title" --body "$body"
    ok "PR created."
  fi
}

############################################
# SUBCOMMAND: port (interactive)
############################################
cmd_port() {
  in_git_repo || die "Run this inside a git repository."

  # Handle --continue flag
  if [[ "${1:-}" == "--continue" ]]; then
    # Check if there's actually a cherry-pick in progress
    if [[ ! -f "$(git rev-parse --git-dir)/CHERRY_PICK_HEAD" ]]; then
      die "No cherry-pick in progress. Nothing to continue."
    fi

    # Check for unresolved conflicts
    local unmerged
    unmerged="$(git diff --name-only --diff-filter=U)"
    if [[ -n "$unmerged" ]]; then
      info "Still have unresolved conflicts in:"
      print -r -- "$unmerged" | sed 's/^/  /' >&2
      die "Resolve conflicts, then 'git add' the files before continuing."
    fi

    # Check that changes are staged
    if ! has_staged_changes; then
      die "No staged changes. Resolve conflicts and 'git add' the resolved files."
    fi

    # Check for unstaged changes (might have forgotten to add something)
    local unstaged
    unstaged="$(git diff --name-only)"
    if [[ -n "$unstaged" ]]; then
      info "You have unstaged changes in:"
      print -r -- "$unstaged" | sed 's/^/  /' >&2
      print -r -- "" >&2
      if ! confirm "Continue anyway? (you may have forgotten to add files)" "n"; then
        die "Cancelled. Stage all changes with 'git add' and try again."
      fi
    fi

    info "Continuing cherry-pick..."
    if git cherry-pick --continue --no-edit; then
      ok "Cherry-pick completed!"

      # Ask about pushing
      if confirm "Push to origin?" "n"; then
        info "Pushing to origin..."
        if git push; then
          ok "Pushed successfully!"
        else
          info "Push failed. You can push manually later."
        fi
      else
        info "Skipping push. You can push manually with: git push"
      fi

      ok "Done!"
    else
      die "Cherry-pick --continue failed. Resolve conflicts and try again."
    fi
    return
  fi

  local commit_sha="${1:-}"
  local target_branch="${2:-}"
  local original_branch
  original_branch="$(current_branch)"

  # Default to current branch if no target specified
  [[ -z "$target_branch" ]] && target_branch="$original_branch"

  # If no args provided, interactive mode
  if [[ -z "$commit_sha" ]]; then
    local default_branch
    default_branch="$(default_base_branch)"

    info "Fetching $default_branch..."
    git fetch origin "$default_branch" >/dev/null 2>&1 || die "Failed to fetch $default_branch"

    # Select commit with fzf or fallback
    if fzf_available; then
      info "Select a commit from $default_branch:"
      local selected
      selected="$(git log --no-decorate --oneline "origin/$default_branch" -50 | \
        select_with_fzf "Select commit" \
          --preview "echo {} | cut -d' ' -f1 | xargs git show --stat --color=always")"

      [[ -n "$selected" ]] || die "No commit selected."
      commit_sha="${selected%% *}"
    else
      # Fallback to original method
      info "Recent commits from $default_branch:"
      local commits_list
      commits_list="$(git log --no-decorate --oneline "origin/$default_branch" -10 | cat -n)"
      print -r -- "$commits_list" >&2
      print -r -- "" >&2

      local choice
      choice="$(prompt_choice "Which commit? (number or SHA)" "1")"

      # If number, convert to SHA
      if [[ "$choice" =~ ^[0-9]+$ ]]; then
        commit_sha="$(git log --no-decorate --format='%h' "origin/$default_branch" -"$choice" | tail -1)"
      else
        commit_sha="$choice"
      fi

      [[ -n "$commit_sha" ]] || die "No commit selected."
    fi

    # Show selected commit
    local selected_msg
    selected_msg="$(git log --no-decorate --format='%s' -1 "$commit_sha")"
    info "Selected: $commit_sha - $selected_msg"
  fi

  # Show which branch we're porting to
  info "Porting to branch: $target_branch"

  # Only switch and update if porting to a different branch
  if [[ "$target_branch" != "$original_branch" ]]; then
    info "Switching to $target_branch..."
    git checkout "$target_branch" || die "Failed to checkout $target_branch"
  fi

  info "Updating $target_branch..."
  git pull || die "Failed to pull $target_branch"

  # Cherry-pick
  info "Cherry-picking $commit_sha..."
  if git cherry-pick "$commit_sha"; then
    ok "Cherry-pick successful!"

    # Ask about pushing
    local should_push
    if confirm "Push to origin?" "n"; then
      info "Pushing to origin..."
      if git push; then
        ok "Pushed successfully!"
      else
        info "Push failed. You can push manually later."
      fi
    else
      info "Skipping push. You can push manually with: git push"
    fi
  else
    info "Cherry-pick had conflicts. Resolve them and run: hack port --continue"
    info "Or abort with: git cherry-pick --abort"
    info "Won't return to original branch until resolved."
    return 1
  fi

  # Return to original branch
  if [[ "$original_branch" != "$target_branch" ]]; then
    info "Returning to $original_branch..."
    git checkout "$original_branch"
  fi

  ok "Done!"
}


############################################
# SUBCOMMAND: done (interactive)
############################################
cmd_done() {
  in_git_repo || die "Run this inside a git repository."
  need_cmd gh
  gh auth status >/dev/null 2>&1 || die "GitHub CLI not authenticated. Run: gh auth login"

  local branch
  branch="$(current_branch)"
  [[ -n "$branch" ]] || die "Detached HEAD; check out a branch first."

  # Don't allow cleanup of important branches
  local default_branch
  default_branch="$(default_base_branch)"
  if [[ "$branch" == "$default_branch" || "$branch" == "main" || "$branch" == "master" ]]; then
    die "Won't delete important branch: $branch"
  fi

  # Also check git-town perennial branches
  local perennials
  perennials="$(get_perennial_branches)"
  if [[ -n "$perennials" ]]; then
    for perennial in ${(z)perennials}; do
      if [[ "$branch" == "$perennial" ]]; then
        die "Won't delete perennial branch: $branch"
      fi
    done
  fi

  # Check for uncommitted changes
  if has_changes; then
    info "You have uncommitted changes:"
    git status -sb >&2
    if ! confirm "Continue anyway? (changes will come with you)"; then
      die "Cancelled."
    fi
  fi

  # Check if there's a PR for this branch
  local pr_json pr_state pr_merged base_branch pr_number
  if ! pr_json="$(gh pr view --json number,state,mergedAt,baseRefName 2>/dev/null)"; then
    info "No PR found for branch: $branch"
    if ! confirm "Delete local branch anyway?"; then
      die "Cancelled."
    fi
    # No PR, just delete local and return to default branch
    git checkout "$default_branch"
    git branch -D "$branch"
    ok "Deleted local branch: $branch"
    info "Updating $default_branch..."
    git pull
    ok "Done!"
    return
  fi

  pr_number="$(print -r -- "$pr_json" | jq -r '.number')"
  pr_state="$(print -r -- "$pr_json" | jq -r '.state')"
  pr_merged="$(print -r -- "$pr_json" | jq -r '.mergedAt')"
  base_branch="$(print -r -- "$pr_json" | jq -r '.baseRefName')"

  info "Found PR #$pr_number (state: $pr_state, base: $base_branch)"

  # Check if PR was merged
  if [[ "$pr_merged" == "null" || -z "$pr_merged" ]]; then
    if [[ "$pr_state" == "OPEN" ]]; then
      info "PR #$pr_number is still OPEN (not merged yet)"
      if ! confirm "Delete branch anyway?"; then
        die "Cancelled. Merge or close the PR first, or force deletion."
      fi
    elif [[ "$pr_state" == "CLOSED" ]]; then
      info "PR #$pr_number was CLOSED (not merged)"
      if ! confirm "Delete branch anyway?"; then
        die "Cancelled."
      fi
    fi
  else
    ok "PR #$pr_number was merged!"
  fi

  # Delete remote branch if it exists
  info "Checking for remote branch..."
  if git ls-remote --heads origin "$branch" | grep -q "$branch"; then
    info "Remote branch exists. Deleting origin/$branch..."
    if git push origin --delete "$branch" 2>/dev/null; then
      ok "Deleted remote branch"
    else
      info "Failed to delete remote branch (may already be deleted or no permission)"
    fi
  else
    info "Remote branch already deleted"
  fi

  # Switch to base branch
  info "Switching to $base_branch..."
  git checkout "$base_branch" || die "Failed to checkout $base_branch"

  # Update base branch
  info "Updating $base_branch..."
  git pull || info "Failed to pull (continuing anyway)"

  # Delete local branch
  info "Deleting local branch $branch..."
  if git branch -D "$branch" 2>/dev/null; then
    ok "Deleted local branch: $branch"
  else
    info "Failed to delete local branch (may already be deleted)"
  fi

  ok "Done! Now on $base_branch with latest changes."
}

############################################
# SUBCOMMAND: prune (interactive)
############################################
cmd_prune() {
  in_git_repo || die "Run this inside a git repository."
  need_cmd gh
  gh auth status >/dev/null 2>&1 || die "GitHub CLI not authenticated. Run: gh auth login"

  local base_branch current_branch
  base_branch="$(default_base_branch)"
  current_branch="$(current_branch)"

  # Get protected branches (perennials + main/master)
  local protected_branches=("$base_branch" "main" "master")
  local perennials
  perennials="$(get_perennial_branches)"
  if [[ -n "$perennials" ]]; then
    for perennial in ${(z)perennials}; do
      protected_branches+=("$perennial")
    done
  fi

  # Get all local branches
  local all_branches
  all_branches=($(git branch --format='%(refname:short)'))

  # Filter to only merged branches that aren't protected
  local merged_branches=()
  for branch in "${all_branches[@]}"; do
    # Skip if it's a protected branch
    local is_protected=0
    for protected in "${protected_branches[@]}"; do
      if [[ "$branch" == "$protected" ]]; then
        is_protected=1
        break
      fi
    done
    [[ $is_protected == 1 ]] && continue

    # Check if merged into base
    if git merge-base --is-ancestor "$branch" "$base_branch" 2>/dev/null; then
      # Also check that it's actually merged (not just a common ancestor)
      local merge_base
      merge_base="$(git merge-base "$branch" "$base_branch")"
      local branch_head
      branch_head="$(git rev-parse "$branch")"
      if [[ "$merge_base" == "$branch_head" ]]; then
        merged_branches+=("$branch")
      fi
    fi
  done

  if [[ ${#merged_branches[@]} -eq 0 ]]; then
    ok "No merged branches to prune!"
    return
  fi

  # Show what we found
  info "Found ${#merged_branches[@]} merged branch(es):"
  for branch in "${merged_branches[@]}"; do
    local marker=""
    [[ "$branch" == "$current_branch" ]] && marker=" (current)"
    print -r -- "  • $branch$marker" >&2
  done
  print -r -- "" >&2

  if ! confirm "Delete these branches?"; then
    die "Cancelled."
  fi

  # Switch off current branch if needed
  local need_to_return=0
  if [[ " ${merged_branches[@]} " =~ " ${current_branch} " ]]; then
    info "Switching to $base_branch (current branch will be deleted)..."
    git checkout "$base_branch"
    git pull
    need_to_return=0
  else
    need_to_return=1
  fi

  # Delete each branch
  local deleted_count=0
  local failed_count=0
  for branch in "${merged_branches[@]}"; do
    print -r -- "" >&2
    info "Processing: $branch"

    # Check for remote branch and delete if exists
    if git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "$branch"; then
      info "  Deleting remote branch origin/$branch..."
      if git push origin --delete "$branch" 2>/dev/null; then
        ok "  Remote deleted"
      else
        info "  Failed to delete remote (may already be deleted)"
      fi
    fi

    # Delete local branch
    info "  Deleting local branch..."
    if git branch -D "$branch" 2>/dev/null; then
      ok "  Local deleted"
      ((deleted_count++))
    else
      info "  Failed to delete local branch"
      ((failed_count++))
    fi
  done

  print -r -- "" >&2
  ok "Pruning complete!"
  info "Deleted: $deleted_count branch(es)"
  [[ $failed_count -gt 0 ]] && info "Failed: $failed_count branch(es)"

  # Return to original branch if we didn't delete it
  if [[ $need_to_return == 1 && "$current_branch" != "$base_branch" ]]; then
    git checkout "$current_branch" 2>/dev/null || true
  fi
}


# MAIN
main() {
  need_cmd git
  need_cmd curl
  need_cmd jq

  local cmd="${1:-}"
  [[ $# -gt 0 ]] && shift

  case "$cmd" in
    done)    in_git_repo || die "Run this inside a git repository."; cmd_done "$@" ;;
    port)    in_git_repo || die "Run this inside a git repository."; cmd_port "$@" ;;
    idea)    in_git_repo || die "Run this inside a git repository."; cmd_idea "$@" ;;
    issue)   in_git_repo || die "Run this inside a git repository."; cmd_issue "$@" ;;
    commit)  in_git_repo || die "Run this inside a git repository."; cmd_commit "$@" ;;
    propose) in_git_repo || die "Run this inside a git repository."; cmd_propose "$@" ;;
    prune)   in_git_repo || die "Run this inside a git repository."; cmd_prune "$@" ;;

    -h|--help|"")
      cat <<'HELP'
hack — git helper (zsh)

Commands:
  hack idea [-i "my idea"]       Create a new feature branch
  hack issue <number>            Create a branch from a GitHub issue
  hack commit                    Generate and create a commit
  hack propose [remote]          Create/update a GitHub PR (default remote: origin)
  hack port [sha] [branch]       Cherry-pick commit (defaults to current branch)
  hack port --continue           Continue after resolving conflicts
  hack done                      Clean up merged branch
  hack prune                     Delete all merged branches (bulk cleanup)

Config:
  OPENAI_API_KEY (required):
    Option 1: Environment variable (add to ~/.zshrc or ~/.bashrc)
      export OPENAI_API_KEY='sk-proj-...'

    Option 2: Config file at ~/.config/hack/config
      echo 'OPENAI_API_KEY="sk-proj-..."' > ~/.config/hack/config
      chmod 600 ~/.config/hack/config

  OPENAI_MODEL (optional, default: gpt-5.2)

Dependencies:
  git, curl, jq
  propose/done/prune: gh (GitHub CLI)
  optional: fzf (improved selection UI), git town

Install fzf for better experience: brew install fzf

HELP
      ;;
    *)
      die "Unknown command: $cmd (try: hack --help)"
      ;;
  esac
}

main "$@"
