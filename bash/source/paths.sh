# Homebrew (Apple Silicon default)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"
else
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fi
