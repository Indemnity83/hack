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
