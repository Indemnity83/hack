#!/usr/bin/env zsh
SRCDIR="${0:h}/../src"
source "${0:h}/assert.zsh"
source "$SRCDIR/output.zsh"

# Helper: parse the NUL-separated output of split_title_body
parse_title() { local combined="$1"; print -r -- "${combined%%$'\0'*}"; }
parse_body()  { local combined="$1"; print -r -- "${combined#*$'\0'}"; }

# ---- split_title_body ----
print "split_title_body"

# Single line — no body
combined="$(split_title_body "feat: add login")"
assert_eq "single line: title" "feat: add login" "$(parse_title "$combined")"
assert_eq "single line: body is empty" "" "$(parse_body "$combined")"

# Title + blank line + body
combined="$(split_title_body $'fix: correct typo\n\nUpdated the README.')"
assert_eq "title+body: title" "fix: correct typo" "$(parse_title "$combined")"
assert_eq "title+body: body" "Updated the README." "$(parse_body "$combined")"

# Title directly followed by body (no blank separator)
combined="$(split_title_body $'chore: update deps\nBumped lodash to 4.17.21.')"
assert_eq "no-blank: title" "chore: update deps" "$(parse_title "$combined")"
assert_eq "no-blank: body contains text" "Bumped lodash to 4.17.21." "$(parse_body "$combined")"

# Leading/trailing whitespace on title is stripped
combined="$(split_title_body $'  feat: spaces  \n\nBody text.')"
assert_eq "strips title whitespace" "feat: spaces" "$(parse_title "$combined")"

# Carriage returns on title are stripped
combined="$(split_title_body $'feat: windows line ending\r\n\nBody.')"
assert_eq "strips CR from title" "feat: windows line ending" "$(parse_title "$combined")"

# Multi-paragraph body is preserved
# Note: $'...' ANSI-C quoting is not recognised inside double quotes in zsh,
# so we concatenate the title and body outside double quotes.
body_text=$'## Summary\n\nThing changed.\n\n## Details\n\nMore info here.'
combined="$(split_title_body $'feat: full PR\n\n'"$body_text")"
assert_contains "multi-para body preserved" "## Summary" "$(parse_body "$combined")"
assert_contains "multi-para body second section" "## Details" "$(parse_body "$combined")"

summarize
