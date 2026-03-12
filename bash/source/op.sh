# Load environment variables from a local file of 1Password secret references.
# Format:
#   VAR_NAME=op://vault/item/field
#   export VAR_NAME=op://vault/item/field

export OP_ENV_FILE="${OP_ENV_FILE:-$HOME/.config/1Password/op/env}"
export OP_ENV_CACHE_TTL="${OP_ENV_CACHE_TTL:-43200}"

op_collect_env_ref_names() {
    local env_file="$1"
    local line='' var_name='' secret_ref=''
    local parse_failed=0
    OP_ENV_REF_NAMES=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+ ]]; then
            line="${line#${line%%[![:space:]]*}}"
            line="${line#export }"
        fi

        if [[ ! "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$ ]]; then
            parse_failed=$((parse_failed + 1))
            continue
        fi

        var_name="${BASH_REMATCH[1]}"
        secret_ref="${BASH_REMATCH[2]}"

        if [[ "$secret_ref" =~ ^\"(.*)\"$ || "$secret_ref" =~ ^\'(.*)\'$ ]]; then
            secret_ref="${BASH_REMATCH[1]}"
        fi

        if [[ "$secret_ref" != op://* ]]; then
            parse_failed=$((parse_failed + 1))
            continue
        fi

        OP_ENV_REF_NAMES[${#OP_ENV_REF_NAMES[@]}]="$var_name"
    done < "$env_file"

    return "$parse_failed"
}

op_env_cache_path() {
    local env_file="${1:-$OP_ENV_FILE}"
    local cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/bash"
    local cache_key="${env_file//\//_}"
    cache_key="${cache_key// /_}"
    printf '%s/op-env-%s.sh\n' "$cache_root" "$cache_key"
}

op_file_mtime() {
    local file_path="$1"

    if stat -f '%m' "$file_path" >/dev/null 2>&1; then
        stat -f '%m' "$file_path"
    else
        stat -c '%Y' "$file_path"
    fi
}

op_source_env_cache() {
    local cache_file="$1"

    [[ -r "$cache_file" ]] || return 1
    # shellcheck disable=SC1090
    source "$cache_file"
    export OP_SECRETS_LOADED=1
    export OP_ENV_CACHE_HIT=1
}

op_cache_is_fresh() {
    local env_file="$1"
    local cache_file="$2"
    local now='' cache_mtime='' env_mtime='' ttl=''

    [[ -r "$cache_file" ]] || return 1

    ttl="$OP_ENV_CACHE_TTL"
    [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=43200
    (( ttl > 0 )) || return 1

    now="$(date +%s)"
    cache_mtime="$(op_file_mtime "$cache_file")" || return 1
    env_mtime="$(op_file_mtime "$env_file")" || return 1

    (( cache_mtime >= env_mtime )) || return 1
    (( now - cache_mtime <= ttl )) || return 1
}

op_write_env_cache() {
    local env_file="$1"
    local cache_file="$2"
    local cache_dir='' tmp_file='' name=''

    cache_dir="$(dirname "$cache_file")"
    mkdir -p "$cache_dir" || return 1
    chmod 700 "$cache_dir" 2>/dev/null || true

    tmp_file="$(mktemp "$cache_dir/.op-env-cache.XXXXXX")" || return 1

    (
        umask 077
        {
            printf '# Generated from %s\n' "$env_file"
            printf 'export OP_SECRETS_LOADED=1\n'
            printf 'export OP_ENV_CACHE_HIT=1\n'
            for name in "${OP_ENV_REF_NAMES[@]}"; do
                if [[ "${!name+set}" == 'set' ]]; then
                    printf 'export %s=%q\n' "$name" "${!name}"
                fi
            done
        } > "$tmp_file"
    ) || {
        rm -f "$tmp_file"
        return 1
    }

    mv "$tmp_file" "$cache_file"
    chmod 600 "$cache_file" 2>/dev/null || true
}

op_fetch_env_refs() {
    local env_file="$1"
    local entry='' var_name='' secret_value=''
    OP_ENV_FETCHED_COUNT=0

    while IFS= read -r -d '' entry; do
        var_name="${entry%%=*}"
        secret_value="${entry#*=}"

        printf -v "$var_name" '%s' "$secret_value"
        export "$var_name"
        OP_ENV_FETCHED_COUNT=$((OP_ENV_FETCHED_COUNT + 1))
    done < <(
        op run --no-masking --env-file "$env_file" -- bash -c '
            for name in "$@"; do
                if [ "${!name+set}" = "set" ]; then
                    printf "%s=%s\0" "$name" "${!name}"
                fi
            done
        ' bash "${OP_ENV_REF_NAMES[@]}" 2>/dev/null
    )
}

op_load_env_refs() {
    local env_file="${1:-$OP_ENV_FILE}"
    local force_refresh="${2:-false}"
    local cache_file='' loaded_count=0 failed_count=0 parse_failed=0

    [[ -r "$env_file" ]] || return 0

    op_collect_env_ref_names "$env_file"
    parse_failed=$?

    if ((${#OP_ENV_REF_NAMES[@]} == 0)); then
        unset OP_SECRETS_LOADED OP_ENV_CACHE_HIT
        return "$parse_failed"
    fi

    cache_file="$(op_env_cache_path "$env_file")"

    if [[ "$force_refresh" != 'true' ]] && op_cache_is_fresh "$env_file" "$cache_file"; then
        if op_source_env_cache "$cache_file"; then
            if (( parse_failed > 0 )) && [[ $- == *i* ]]; then
                printf '[bash] Ignored %d invalid 1Password env entries in %s\n' \
                    "$parse_failed" "$env_file" >&2
            fi
            return "$parse_failed"
        fi
    fi

    command -v op >/dev/null 2>&1 || {
        if op_source_env_cache "$cache_file"; then
            if [[ $- == *i* ]]; then
                printf '[bash] Loaded cached 1Password env values because `op` is unavailable\n' >&2
            fi
            return 0
        fi
        return 0
    }

    unset OP_ENV_CACHE_HIT
    op_fetch_env_refs "$env_file"
    loaded_count="${OP_ENV_FETCHED_COUNT:-0}"
    failed_count=$parse_failed

    if (( loaded_count < ${#OP_ENV_REF_NAMES[@]} )); then
        failed_count=$((failed_count + ${#OP_ENV_REF_NAMES[@]} - loaded_count))
    fi

    if (( loaded_count > 0 )) && (( failed_count == 0 )); then
        export OP_SECRETS_LOADED=1
        op_write_env_cache "$env_file" "$cache_file" >/dev/null 2>&1 || true
    else
        unset OP_SECRETS_LOADED

        if [[ -r "$cache_file" ]] && op_source_env_cache "$cache_file"; then
            if [[ $- == *i* ]]; then
                printf '[bash] Loaded stale cached 1Password env values from %s after refresh failed\n' \
                    "$cache_file" >&2
            fi
            return 0
        fi
    fi

    if (( failed_count > 0 )) && [[ $- == *i* ]]; then
        printf '[bash] 1Password env load incomplete from %s (%d loaded, %d failed)\n' \
            "$env_file" "$loaded_count" "$failed_count" >&2
    fi
}

op_reload_env() {
    local env_file="${1:-$OP_ENV_FILE}"
    local cache_file=''

    cache_file="$(op_env_cache_path "$env_file")"
    rm -f "$cache_file"
    unset OP_SECRETS_LOADED OP_ENV_CACHE_HIT
    op_load_env_refs "$env_file" true
}

op_clear_env_cache() {
    local env_file="${1:-$OP_ENV_FILE}"
    local cache_file=''

    cache_file="$(op_env_cache_path "$env_file")"
    rm -f "$cache_file"
}

if [[ -z "${OP_SECRETS_LOADED:-}" ]]; then
    op_load_env_refs
fi
