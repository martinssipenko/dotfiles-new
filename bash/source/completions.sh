if command -v brew >/dev/null 2>&1; then
  if [ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]; then
    source "$(brew --prefix)/etc/profile.d/bash_completion.sh"
  fi
fi
