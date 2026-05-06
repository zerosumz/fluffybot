#!/bin/bash

normalize_agent_provider() {
    local provider="${1:-claude}"
    provider=$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')

    case "$provider" in
        claude|codex)
            printf '%s' "$provider"
            ;;
        *)
            echo "ERROR: AGENT_PROVIDER must be one of: claude, codex" >&2
            return 1
            ;;
    esac
}

require_agent_credentials() {
    AGENT_PROVIDER=$(normalize_agent_provider "${AGENT_PROVIDER:-claude}")
    export AGENT_PROVIDER

    case "$AGENT_PROVIDER" in
        claude)
            : "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required when AGENT_PROVIDER=claude}"
            ;;
        codex)
            : "${OPENAI_API_KEY:?OPENAI_API_KEY is required when AGENT_PROVIDER=codex}"
            export OPENAI_API_KEY
            ;;
    esac
}

agent_display_name() {
    case "${AGENT_PROVIDER:-claude}" in
        codex)
            printf '%s' "OpenAI Codex"
            ;;
        *)
            printf '%s' "Claude Code"
            ;;
    esac
}

run_agent_cli() {
    local prompt_file="$1"
    local output_file="$2"
    local prompt

    prompt=$(cat "$prompt_file")

    case "${AGENT_PROVIDER:-claude}" in
        claude)
            claude -p "$prompt" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --verbose 2>&1 | tee "$output_file"
            return "${PIPESTATUS[0]}"
            ;;
        codex)
            if [ -n "${CODEX_MODEL:-}" ]; then
                codex exec --full-auto --model "$CODEX_MODEL" "$prompt" 2>&1 | tee "$output_file"
            else
                codex exec --full-auto "$prompt" 2>&1 | tee "$output_file"
            fi
            return "${PIPESTATUS[0]}"
            ;;
    esac
}

extract_token_usage() {
    local output_file="$1"
    local token_usage=""

    token_usage=$(grep -oP 'Token usage:\s*\K[0-9,]+/[0-9,]+' "$output_file" | tail -1 || echo "")
    [ -z "$token_usage" ] && token_usage=$(grep -oP '[0-9,]+/[0-9,]+(?=\s+tokens?)' "$output_file" | tail -1 || echo "")
    [ -z "$token_usage" ] && token_usage=$(grep -oP '\b[0-9]{4,6}/[0-9]{5,7}\b' "$output_file" | tail -1 || echo "")
    [ -z "$token_usage" ] && token_usage="unknown"

    printf '%s' "$token_usage"
}
