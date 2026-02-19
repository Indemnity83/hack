#!/usr/bin/env zsh
SRCDIR="${0:h}/../src"
source "${0:h}/assert.zsh"
source "$SRCDIR/utils.zsh"

# ---- sanitize_branch_name ----
print "sanitize_branch_name"

assert_eq "lowercases input" \
  "my-feature" \
  "$(sanitize_branch_name "My Feature")"

assert_eq "spaces become hyphens" \
  "my-feature-idea" \
  "$(sanitize_branch_name "my feature idea")"

assert_eq "collapses multiple hyphens" \
  "my-feature" \
  "$(sanitize_branch_name "my---feature")"

assert_eq "strips leading and trailing hyphens" \
  "feature" \
  "$(sanitize_branch_name "-feature-")"

assert_eq "removes colon and exclamation" \
  "feat-add-thing" \
  "$(sanitize_branch_name "feat: add thing!")"

assert_eq "preserves forward slash" \
  "feature/add-login" \
  "$(sanitize_branch_name "feature/add login")"

assert_eq "collapses double slashes" \
  "feature/add" \
  "$(sanitize_branch_name "feature//add")"

assert_eq "already-clean name is unchanged" \
  "fix-authentication-bug" \
  "$(sanitize_branch_name "fix-authentication-bug")"

assert_eq "numbers are preserved" \
  "fix-issue-42" \
  "$(sanitize_branch_name "fix issue #42")"

long_name="$(printf 'a%.0s' {1..80})"
result="$(sanitize_branch_name "$long_name")"
assert_max_len "caps at 60 chars" 60 "$result"

result_with_trailing="$(sanitize_branch_name "$(printf 'a-%.0s' {1..35})")"
[[ "${result_with_trailing[-1]}" != "-" ]]
assert_eq "no trailing hyphen after truncation" "0" "$?"

# ---- truncate_str ----
print ""
print "truncate_str"

short="hello world"
assert_eq "short string is unchanged" \
  "$short" \
  "$(truncate_str "$short" 100)"

at_limit="$(printf 'x%.0s' {1..100})"
assert_eq "string at exact limit is unchanged" \
  "$at_limit" \
  "$(truncate_str "$at_limit" 100)"

long_str="$(printf 'x%.0s' {1..25000})"
truncated="$(truncate_str "$long_str" 20000)"
assert_contains "long string gets truncation marker" "TRUNCATED" "$truncated"
assert_max_len "truncated output fits within limit (plus marker overhead)" 20200 "$truncated"

summarize
