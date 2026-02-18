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
