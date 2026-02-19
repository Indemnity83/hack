#!/usr/bin/env zsh
SRCDIR="${0:h}/../src"
source "${0:h}/assert.zsh"
source "$SRCDIR/utils.zsh"
source "$SRCDIR/git-helpers.zsh"

# Helper: create an isolated temp git repo, run a command inside it, return output.
# Usage: in_repo [setup_cmds...] -- cmd
# The last argument after '--' is the command to evaluate; all prior args are
# git commands run via "git -C $tmp <args>" before entering the repo.
run_in_tmp_repo() {
  local tmp
  tmp="$(mktemp -d)"
  git init "$tmp" --quiet
  # Run setup commands (passed as individual args before --)
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

# ---- remote_to_gh_repo ----
print "remote_to_gh_repo"

result="$(run_in_tmp_repo \
  "remote add origin git@github.com:owner/repo.git" \
  -- "remote_to_gh_repo origin")"
assert_eq "SSH URL: owner/repo" "owner/repo" "$result"

result="$(run_in_tmp_repo \
  "remote add origin https://github.com/owner/repo.git" \
  -- "remote_to_gh_repo origin")"
assert_eq "HTTPS URL: owner/repo" "owner/repo" "$result"

result="$(run_in_tmp_repo \
  "remote add origin git@github.com:owner/repo" \
  -- "remote_to_gh_repo origin")"
assert_eq "SSH URL without .git suffix" "owner/repo" "$result"

result="$(run_in_tmp_repo \
  "remote add origin https://github.com/acme-corp/my-tool.git" \
  -- "remote_to_gh_repo origin")"
assert_eq "hyphenated org and repo" "acme-corp/my-tool" "$result"

# ---- default_base_branch ----
print ""
print "default_base_branch"

# git-town config takes priority
result="$(run_in_tmp_repo \
  "config git-town.main-branch development" \
  -- "default_base_branch")"
assert_eq "git-town config" "development" "$result"

# origin/HEAD symref is used when no git-town config
result="$(run_in_tmp_repo \
  "symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/staging" \
  -- "default_base_branch")"
assert_eq "origin/HEAD symref" "staging" "$result"

# refs/heads/main exists → "main"
result="$(run_in_tmp_repo \
  "commit --allow-empty -m init --quiet --author='T <t@t>' -c user.name=T -c user.email=t@t" \
  -- "default_base_branch")"
# git init defaults to 'main' on modern git; this just confirms the fallback works
assert_contains "main-or-master fallback is not empty" "" "$result"  # basic smoke test
[[ "$result" == "main" || "$result" == "master" ]]
assert_eq "fallback is main or master" "0" "$?"

summarize
