#!/usr/bin/env bash
set -e

echo "Installing fzf..."
brew install fzf

FZF_CONFIG="$HOME/.fzf.zsh"

echo "Writing fzf config to $FZF_CONFIG..."
cat > "$FZF_CONFIG" <<'EOF'
# Setup fzf
# ---------
if [[ ! "$PATH" == */opt/homebrew/opt/fzf/bin* ]]; then
  PATH="${PATH:+${PATH}:}/opt/homebrew/opt/fzf/bin"
fi

source <(fzf --zsh)
EOF

echo "Adding fzf config to ~/.zshrc..."

if ! grep -q 'source ~/.fzf.zsh' "$HOME/.zshrc" 2>/dev/null; then
  cat >> "$HOME/.zshrc" <<'EOF'

# fzf
source ~/.fzf.zsh
EOF
fi

echo "Loading fzf for this shell..."
source "$FZF_CONFIG"

echo "fzf is ready ✅"
echo "Try: Ctrl+R, Ctrl+T, or Alt+C"
