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
