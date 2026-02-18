git_town_available() {
  git town --version >/dev/null 2>&1 && \
    git config git-town.main-branch >/dev/null 2>&1
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
