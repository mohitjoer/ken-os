# Asura OS zsh configuration
[[ ${__ASURA_ZSH_LOADED:-0} == 1 ]] && return
__ASURA_ZSH_LOADED=1

typeset -U path
path=(
  "$HOME/.local/bin"
  "$HOME/.opencode/bin"
  "$HOME/.cargo/bin"
  "$HOME/.bun/bin"
  $path
)

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  [[ -d "$NVM_DIR/versions/node" ]] && {
    _node_bin=$(ls -d "$NVM_DIR/versions/node"/*/bin 2>/dev/null | tail -n 1)
    [[ -n "$_node_bin" ]] && path=("$_node_bin" $path)
  }
fi

# Editor selection: use GUI zed --wait when available in a display session,
# falling back cleanly to terminal editors (nano, vi) on TTY, SSH, or headless
if [[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]] && command -v zed >/dev/null 2>&1; then
  export EDITOR="${EDITOR:-zed --wait}" VISUAL="${VISUAL:-zed --wait}"
else
  for _editor in nano vi; do
    if command -v "$_editor" >/dev/null 2>&1; then
      export EDITOR="${EDITOR:-$_editor}" VISUAL="${VISUAL:-$_editor}"
      break
    fi
  done
  export EDITOR="${EDITOR:-nano}" VISUAL="${VISUAL:-nano}"
fi

[[ -o interactive ]] || return

_asura_cfg=${XDG_CONFIG_HOME:-$HOME/.config}
_cache=${XDG_CACHE_HOME:-$HOME/.cache}/zsh
mkdir -p "$_cache"

# Helper: evaluate and cache CLI init hooks, invalidating only when binary mtime changes
_asura_cache_eval() {
  local tool="$1"
  shift
  local bin_path cache_file
  bin_path=$(command -v "$tool" 2>/dev/null) || return
  cache_file="$_cache/init_${tool}.zsh"
  if [[ ! -f "$cache_file" || "$bin_path" -nt "$cache_file" ]]; then
    "$@" >| "$cache_file" 2>/dev/null
  fi
  source "$cache_file"
}

# A starship.toml of the user's own (at $_asura_cfg/starship.toml) wins over the packaged one.
# The packaged starship.toml lives at $_asura_cfg/asura/apps/starship/starship.toml
[[ -z $STARSHIP_CONFIG && ! -e $_asura_cfg/starship.toml ]] &&
  export STARSHIP_CONFIG=$_asura_cfg/asura/apps/starship/starship.toml

_asura_cache_eval starship starship init zsh
_asura_cache_eval zoxide zoxide init zsh --cmd cd
_asura_cache_eval mise mise activate zsh
_asura_cache_eval fzf fzf --zsh

autoload -Uz compinit
# Skip expensive security directory audits on every shell launch if dump is under 24 hours old
if [[ -n "$_cache/zcompdump"(#qN.m-1) ]]; then
  compinit -C -d "$_cache/zcompdump"
else
  compinit -d "$_cache/zcompdump"
fi

[[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#8A8A8A'

# History substring search (up/down arrows search history with current buffer)
if [[ -r /usr/share/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
  source /usr/share/zsh-history-substring-search/zsh-history-substring-search.zsh
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
fi

# Atuin for enhanced history (cached init)
_asura_cache_eval atuin atuin init zsh --disable-up-arrow

# Sourced last: the highlighter wraps the widgets that exist when it loads.
if [[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  ZSH_HIGHLIGHT_STYLES[default]='fg=#F2F2F2'
  ZSH_HIGHLIGHT_STYLES[command]='fg=#F2F2F2,bold'
  ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=#F2F2F2,bold'
  ZSH_HIGHLIGHT_STYLES[builtin]='fg=#F2F2F2,bold'
  ZSH_HIGHLIGHT_STYLES[function]='fg=#F2F2F2,bold'
  ZSH_HIGHLIGHT_STYLES[alias]='fg=#F2F2F2,bold'
  ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=#F2F2F2,bold'
  ZSH_HIGHLIGHT_STYLES[global-alias]='fg=#F2F2F2,bold'
  ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#CCCCCC,bold'
  ZSH_HIGHLIGHT_STYLES[precommand]='fg=#CCCCCC,bold'
  ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#A1A1A1'
  ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#CCCCCC'
  ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#CCCCCC'
  ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#A1A1A1'
  ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#A1A1A1'
  ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#A1A1A1'
  ZSH_HIGHLIGHT_STYLES[redirection]='fg=#A1A1A1'
  ZSH_HIGHLIGHT_STYLES[named-fd]='fg=#A1A1A1'
  ZSH_HIGHLIGHT_STYLES[numeric-fd]='fg=#A1A1A1'
  ZSH_HIGHLIGHT_STYLES[globbing]='fg=#CCCCCC'
  ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=#CCCCCC'
  ZSH_HIGHLIGHT_STYLES[comment]='fg=#8A8A8A'
  ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#E5484D'
fi

if command -v eza >/dev/null 2>&1; then
  alias ls='eza -lh --group-directories-first'
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --git'
  alias lta='lt -a'
fi

# Fastfetch wrapper and startup banner
fast() {
  if [[ "$1" == "fetch" ]]; then
    shift
  fi
  command fastfetch "$@"
}

if [[ -o interactive ]] && command -v fastfetch >/dev/null 2>&1; then
  # Display system summary on top-level terminal launch, suppressing in subshells
  if [[ -z "$__ASURA_FASTFETCH_SHOWN" ]]; then
    # Suppress fastfetch on bare console login (tty1) before graphical session starts
    if [[ -n "$WAYLAND_DISPLAY" || -n "$DISPLAY" || "$XDG_SESSION_TYPE" == "wayland" || "$(tty 2>/dev/null)" != "/dev/tty1" ]]; then
      export __ASURA_FASTFETCH_SHOWN=1
      fastfetch
    fi
  fi
fi

# Opt-in mimalloc high-performance allocator wrapper
with-mimalloc() {
  if [[ -f /usr/lib/libmimalloc.so.3 ]]; then
    LD_PRELOAD="/usr/lib/libmimalloc.so.3${LD_PRELOAD:+:$LD_PRELOAD}" "$@"
  elif [[ -f /usr/lib/libmimalloc.so ]]; then
    LD_PRELOAD="/usr/lib/libmimalloc.so${LD_PRELOAD:+:$LD_PRELOAD}" "$@"
  else
    "$@"
  fi
}

# Ghostty injects its integration into the shell it starts itself; this covers
# nested shells (exec zsh, tmux, sudo -E). The script guards against a second load.
if [[ -n $GHOSTTY_RESOURCES_DIR ]]; then
  source "$GHOSTTY_RESOURCES_DIR"/shell-integration/zsh/ghostty-integration
fi

unset _asura_cfg _cache
