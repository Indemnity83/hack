# ---- OPENAI ----
openai_response() {
  # usage: openai_response "$instructions" "$input"
  local instructions="$1"
  local input="$2"

  if [[ -z "$OPENAI_API_KEY" ]]; then
    die "OPENAI_API_KEY not set. Set it via:
  1) Environment variable (add to ~/.zshrc or ~/.bashrc):
     export OPENAI_API_KEY='your-key-here'
  2) Config file at ${CONFIG_FILE}:
     echo 'OPENAI_API_KEY=\"your-key-here\"' > ${CONFIG_FILE}
     chmod 600 ${CONFIG_FILE}"
  fi

  # Trim whitespace/newlines from key (common when copy/pasting)
  local key
  key="$(print -r -- "$OPENAI_API_KEY" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [[ -n "$key" ]] || die "OPENAI_API_KEY is empty after trimming."

  local payload
  payload="$(jq -n \
    --arg model "$OPENAI_MODEL" \
    --arg instructions "$instructions" \
    --arg input "$input" \
    '{
      model: $model,
      instructions: $instructions,
      input: $input
    }')"

  local resp
  resp="$(curl -sS https://api.openai.com/v1/responses \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $key" \
    --data-raw "$payload")"

  # If the API returns an error object, show it and stop.
  local api_err
  api_err="$(print -r -- "$resp" | jq -r '.error.message // empty')"
  if [[ -n "$api_err" ]]; then
    info "Raw response:"
    print -r -- "$resp" >&2
    die "$api_err"
  fi

  # Extract ALL output text (not just the first line).
  local out
  out="$(print -r -- "$resp" | jq -r '
    (
      .output_text
      // (
        [ .output[]?.content[]? | select(.type=="output_text") | .text ]
        | join("\n")
      )
      // ""
    )
  ')"

  # Treat whitespace-only output as empty
  out="$(print -r -- "$out" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  [[ -n "$out" ]] || {
    info "Raw response:"
    print -r -- "$resp" >&2
    die "OpenAI response did not include output text."
  }

  print -r -- "$out"
}
