ZSH_NVM_DIR=${0:a:h}

export NVM_DIR="$(_zsh_nvm_install_dir)"
export NVM_SYS_DIR="$(nvm_system_install_dir)"

nvm_system_install_dir() {
  if _zsh_nvm_has brew && ls $(brew --prefix)/opt/ | grep -q nvm; then
    echo "$(brew --prefix)/opt/nvm"
  else
    echo $NVM_DIR
  fi
}

_zsh_nvm_default_install_dir() {
  [ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm"
}

_zsh_nvm_install_dir() {
  if [ -n "$NVM_DIR" ]; then
    printf %s "${NVM_DIR}"
  else
    _zsh_nvm_default_install_dir
  fi
}

_zsh_nvm_rename_function() {
  test -n "$(declare -f $1)" || return
  eval "${_/$1/$2}"
  unset -f $1
}

_zsh_nvm_has() {
  type "$1" > /dev/null 2>&1
}

_zsh_nvm_global_binaries() {

  # Look for global binaries
  local global_binary_paths=$(echo "$NVM_DIR"/v0*/bin/*(N) "$NVM_DIR"/versions/*/*/bin/*(N))

  # If we have some, format them
  if [[ -n "$global_binary_paths" ]]; then
    echo $global_binary_paths |
      xargs -n 1 basename |
      sort |
      uniq
  fi
}

_zsh_nvm_load() {
  [[ "$NVM_AUTO_USE" == true ]] && _zsh_nvm_auto_use

  # Source nvm (check if `nvm use` should be ran after load)
  if [[ "$NVM_NO_USE" == true ]]; then
    source "$NVM_SYS_DIR/nvm.sh" --no-use
  else
    source "$NVM_SYS_DIR/nvm.sh"
  fi

  # Rename main nvm function
  _zsh_nvm_rename_function nvm _zsh_nvm_nvm

  # Wrap nvm in our own function
  nvm() {
    case $1 in
      'use')
        _zsh_nvm_nvm "$@"
        export NVM_AUTO_USE_ACTIVE=false
        ;;
      'install' | 'i')
        _zsh_nvm_install_wrapper "$@"
        ;;
      *)
        _zsh_nvm_nvm "$@"
        ;;
    esac
  }
}

_zsh_nvm_completion() {

  # Add provided nvm completion
  [[ -r $NVM_SYS_DIR/bash_completion ]] && source $NVM_SYS_DIR/bash_completion
}

_zsh_nvm_lazy_load() {

  # Get all global node module binaries including node
  # (only if NVM_NO_USE is off)
  local global_binaries
  if [[ "$NVM_NO_USE" == true ]]; then
    global_binaries=()
  else
    global_binaries=($(_zsh_nvm_global_binaries))
  fi

  # Add yarn lazy loader if it's been installed by something other than npm
  _zsh_nvm_has yarn && global_binaries+=('yarn')

  # Add nvm
  global_binaries+=('nvm')
  global_binaries+=($NVM_LAZY_LOAD_EXTRA_COMMANDS)

  # Remove any binaries that conflict with current aliases
  local cmds
  cmds=()
  local bin
  for bin in $global_binaries; do
    [[ "$(which $bin 2> /dev/null)" = "$bin: aliased to "* ]] || cmds+=($bin)
  done

  # Create function for each command
  local cmd
  for cmd in $cmds; do

    # When called, unset all lazy loaders, load nvm then run current command
    eval "$cmd(){
      unset -f $cmds > /dev/null 2>&1
      _zsh_nvm_load
      $cmd \"\$@\"
    }"
  done
}

autoload -U add-zsh-hook
_zsh_nvm_auto_use() {
  _zsh_nvm_has nvm_find_nvmrc || return

  local node_version="$(nvm version)"
  local nvmrc_path="$(nvm_find_nvmrc)"

  if [[ -n "$nvmrc_path" ]]; then
    local nvmrc_node_version="$(nvm version $(cat "$nvmrc_path"))"

    if [[ "$nvmrc_node_version" = "N/A" ]]; then
      nvm install && export NVM_AUTO_USE_ACTIVE=true
    elif [[ "$nvmrc_node_version" != "$node_version" ]]; then
      nvm use && export NVM_AUTO_USE_ACTIVE=true
    fi
  elif [[ "$node_version" != "$(nvm version default)" ]] && [[ "$NVM_AUTO_USE_ACTIVE" = true ]]; then
    echo "Reverting to nvm default version"
    nvm use default && export NVM_AUTO_USE_ACTIVE=true
  fi
}

_zsh_nvm_install_wrapper() {
  case $2 in
    'rc')
      NVM_NODEJS_ORG_MIRROR=https://nodejs.org/download/rc/ nvm install node && nvm alias rc "$(node --version)"
      echo "Clearing mirror cache..."
      nvm ls-remote > /dev/null 2>&1
      echo "Done!"
      ;;
    'nightly')
      NVM_NODEJS_ORG_MIRROR=https://nodejs.org/download/nightly/ nvm install node && nvm alias nightly "$(node --version)"
      echo "Clearing mirror cache..."
      nvm ls-remote > /dev/null 2>&1
      echo "Done!"
      ;;
    *)
      _zsh_nvm_nvm "$@"
      ;;
  esac
}

# Don't init anything if this is true (debug/testing only)
if [[ "$ZSH_NVM_NO_LOAD" != true ]]; then

  # If nvm is installed
  if [[ -f "$NVM_SYS_DIR/nvm.sh" ]]; then

    # Load it
    [[ "$NVM_LAZY_LOAD" == true ]] && _zsh_nvm_lazy_load || _zsh_nvm_load

    # Enable completion
    [[ "$NVM_COMPLETION" == true ]] && _zsh_nvm_completion
    
    # Auto use nvm on chpwd
    [[ "$NVM_AUTO_USE" == true ]] && add-zsh-hook chpwd _zsh_nvm_auto_use
  fi

fi

# Make sure we always return good exit code
# We can't `return 0` because that breaks antigen
true
