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
