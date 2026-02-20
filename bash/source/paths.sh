# Homebrew (Apple Silicon default)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"
else
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fi

# Add dir to PATH once (after expanding leading ~).
path_prepend() {
  local dir="${1/#\~/$HOME}"
  [ -n "$dir" ] || return 0

  case ":$PATH:" in
    *":$dir:"*) ;;
    *) export PATH="$dir:$PATH" ;;
  esac
}

# Optional user-managed paths file (one path per line, # comments allowed):
#   ~/.config/bash/paths
if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/bash/paths" ]; then
  while IFS= read -r path_entry; do
    case "$path_entry" in
      ''|\#*) continue ;;
      *) path_prepend "$path_entry" ;;
    esac
  done < "${XDG_CONFIG_HOME:-$HOME/.config}/bash/paths"
fi
