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
