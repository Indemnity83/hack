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
