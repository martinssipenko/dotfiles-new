# Dotfiles root (defaults to ~/.dotfiles)
export DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

# XDG config home
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Source helper: src [name] -> DOTFILES/bash/source/<name>.sh, or all if none given
src() {
  local file
  if [[ -n "$1" ]]; then
    file="$DOTFILES/bash/source/$1.sh"
    [[ -r "$file" ]] && source "$file"
  else
    for file in "$DOTFILES"/bash/source/*.sh; do
      [[ -r "$file" ]] && source "$file"
    done
  fi
}

# Load all snippets
src

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

if [[ -s $HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh ]]; then
  . "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh"
fi
