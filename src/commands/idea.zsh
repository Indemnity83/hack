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
