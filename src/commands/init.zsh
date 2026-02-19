############################################
# SUBCOMMAND: init (interactive)
############################################
cmd_init() {
  in_git_repo || die "Run this inside a git repository."
  info "Setting up hack for this repository..."
  print -r -- "" >&2

  # Detect likely main branch
  local detected_main
  detected_main="$(git config hack.main-branch 2>/dev/null || true)"
  if [[ -z "$detected_main" ]]; then
    detected_main="$(git config git-town.main-branch 2>/dev/null || true)"
  fi
  if [[ -z "$detected_main" ]]; then
    local ref
    ref="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)"
    [[ -n "$ref" ]] && detected_main="${ref#refs/remotes/origin/}"
  fi
  if [[ -z "$detected_main" ]]; then
    if git show-ref --verify --quiet refs/heads/main;   then detected_main="main";   fi
    if git show-ref --verify --quiet refs/heads/master; then detected_main="master"; fi
  fi
  : "${detected_main:=main}"

  local main_branch
  main_branch="$(prompt_choice "Main branch:" "$detected_main")"
  [[ -n "$main_branch" ]] || die "Main branch cannot be empty."

  print -r -- "" >&2
  info "Perennial branches are protected from deletion by 'hack done' and 'hack prune'."
  info "Leave blank to skip."
  local perennial_input
  perennial_input="$(prompt_choice "Perennial branches (space-separated):" "")"

  git config hack.main-branch "$main_branch"
  ok "Set hack.main-branch = $main_branch"

  if [[ -n "$perennial_input" ]]; then
    git config hack.perennial-branches "$perennial_input"
    ok "Set hack.perennial-branches = $perennial_input"
  fi

  print -r -- "" >&2
  ok "hack is configured for this repository."
}
