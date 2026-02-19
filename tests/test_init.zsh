#!/usr/bin/env zsh
SRCDIR="${0:h}/../src"
source "${0:h}/assert.zsh"
source "$SRCDIR/utils.zsh"
source "$SRCDIR/git-helpers.zsh"

# Override interactive functions for non-interactive testing
# prompt_choice_responses maps "Question?" -> "answer"
typeset -A _prompt_responses
prompt_choice() {
  local q="$1" def="${2:-}"
  local key="$q"
  if [[ -n "${_prompt_responses[$key]+_}" ]]; then
    print -r -- "${_prompt_responses[$key]}"
  else
    print -r -- "$def"
  fi
}
ok()   { : }
info() { : }

source "$SRCDIR/commands/init.zsh"

# Helper: create isolated temp git repo and run cmd_init inside it
run_init_in_tmp_repo() {
  local tmp
  tmp="$(mktemp -d)"
  git init "$tmp" --quiet
  # Run any setup commands passed before '--'
  local setup_args=()
  while [[ "${1:-}" != "--" && $# -gt 0 ]]; do
    setup_args+=("$1")
    shift
  done
  shift  # consume '--'
  local cmd="$1"

  for arg in "${setup_args[@]}"; do
    eval "git -C '$tmp' $arg" >/dev/null 2>&1 || true
  done

  ( cd "$tmp" && eval "$cmd" )
  local exit_code=$?
  rm -rf "$tmp"
  return $exit_code
}

# ---- cmd_init ----
print "cmd_init"

# Test: init writes hack.main-branch using detected branch name (default "main")
result="$(run_init_in_tmp_repo -- '
  _prompt_responses=()
  cmd_init >/dev/null 2>&1
  git config hack.main-branch
')"
assert_eq "init writes hack.main-branch (default main)" "main" "$result"

# Test: init pre-fills from git-town.main-branch when present
result="$(run_init_in_tmp_repo \
  "config git-town.main-branch develop" \
  -- '
  _prompt_responses=()
  cmd_init >/dev/null 2>&1
  git config hack.main-branch
')"
assert_eq "init pre-fills from git-town.main-branch" "develop" "$result"

# Test: re-running init preserves existing hack.main-branch
result="$(run_init_in_tmp_repo \
  "config hack.main-branch existing-main" \
  -- '
  _prompt_responses=()
  cmd_init >/dev/null 2>&1
  git config hack.main-branch
')"
assert_eq "re-run init preserves existing hack.main-branch" "existing-main" "$result"

# Test: init writes hack.perennial-branches when provided
result="$(run_init_in_tmp_repo -- '
  _prompt_responses=(["Perennial branches (space-separated):"]="release staging")
  cmd_init >/dev/null 2>&1
  git config hack.perennial-branches
')"
assert_eq "init writes hack.perennial-branches" "release staging" "$result"

# Test: init skips hack.perennial-branches when left blank
result="$(run_init_in_tmp_repo -- '
  _prompt_responses=()
  cmd_init >/dev/null 2>&1
  git config hack.perennial-branches 2>/dev/null || echo "__unset__"
')"
assert_eq "init skips perennial-branches when blank" "__unset__" "$result"

summarize
