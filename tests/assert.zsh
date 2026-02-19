# Shared assertion helpers for hack test suite.
# Source this at the top of each test_*.zsh file.

_PASS=0
_FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    print -r -- "  ✓  $desc"
    (( _PASS++ ))
  else
    print -r -- "  ✗  $desc"
    print -r -- "     expected: ${(q)expected}"
    print -r -- "     actual:   ${(q)actual}"
    (( _FAIL++ ))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    print -r -- "  ✓  $desc"
    (( _PASS++ ))
  else
    print -r -- "  ✗  $desc"
    print -r -- "     expected to contain: ${(q)needle}"
    print -r -- "     actual: ${(q)haystack}"
    (( _FAIL++ ))
  fi
}

assert_max_len() {
  local desc="$1" max="$2" str="$3"
  local len=${#str}
  if (( len <= max )); then
    print -r -- "  ✓  $desc"
    (( _PASS++ ))
  else
    print -r -- "  ✗  $desc"
    print -r -- "     max length: $max  actual length: $len"
    (( _FAIL++ ))
  fi
}

summarize() {
  print -r -- ""
  if (( _FAIL == 0 )); then
    print -r -- "  $_PASS passed"
  else
    print -r -- "  $_PASS passed, $_FAIL failed"
  fi
  return $(( _FAIL > 0 ))
}
