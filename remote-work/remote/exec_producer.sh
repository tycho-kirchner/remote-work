#!/usr/bin/env bash

REMOTE_EXEC_PRODUCER_ADD_APPS(){
    local app
    local script_path="$(realpath -s "${BASH_SOURCE[0]}")"

    if [ -z "${_remote_exec_setup_done+x}" ]; then
        _remote_exec_producer_setup || return
    fi
    for app in "$@"; do
        test -e "$_remote_exec_producer_app_path/$app" && continue
        ln -s "$script_path" "$_remote_exec_producer_app_path/$app" || return
    done
    return 0
}


REMOTE_EXEC_PRODUCER_DELETE_APPS(){
    local app
    if [ -z "${_remote_exec_setup_done+x}" ]; then
        _remote_exec_producer_setup || return
    fi
    for app in "$@"; do
        if ! test -e "$_remote_exec_producer_app_path/$app"; then
            echo "REMOTE_EXEC: no such app: $app" >&2
        else
            rm "$_remote_exec_producer_app_path/$app"
        fi
    done
    return 0
}


REMOTE_EXEC_PRODUCER_OPEN(){
    local file
    local args=()
    local filesize i

    if [ -z "${_remote_exec_setup_done+x}" ]; then
        _remote_exec_producer_setup || return
    fi

    # first arg is always the working directory:
    args+=( $(echo "$PWD" | base64 -w 0) )
    for (( i=1; i <= ${#@}; i++ )); do
        # base-64 encode to ensure correct word splitting
        args+=( $(printf '%s\n' "${!i}" | base64 -w 0) )
        # Arguments not starting with a dash are most often file-paths.
        # Warn, if not exist.
        if [[ $i -gt 1 && "${!i}" != -* && ! -e "${!i}" ]]; then
            echo "REMOTE_EXEC warning: not exist: ${!i}" >&2
        fi
    done

    filesize=$(stat -c%s "$_remote_exec_producer_event_path") || return 1
    if [[ $filesize -gt 50000 ]]; then
        # always rotate first. It's still racy but unlikely when used interactively
        mv "$_remote_exec_producer_event_path" "$_remote_exec_producer_event_path"_old
    fi
    echo "${args[*]}" >> "$_remote_exec_producer_event_path"
}


_remote_exec_producer_setup(){
    local cachepath="$HOME/.cache/remote-work"
    local configpath="$HOME/.remote-work"

    _remote_exec_producer_event_path="$cachepath/exec-events"
    _remote_exec_producer_app_path="$configpath/apps"

    mkdir -p "$cachepath" || return
    mkdir -p "$_remote_exec_producer_app_path" || return

    _remote_exec_producer_path_prepend "$_remote_exec_producer_app_path"

    touch "$_remote_exec_producer_event_path" || return
    _remote_exec_setup_done=true
    return 0
}


_remote_exec_producer_path_prepend() {
    if [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]]; then
        PATH="$1${PATH:+":$PATH"}"
    fi
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # we are executed
    REMOTE_EXEC_PRODUCER_OPEN "$(basename "${BASH_SOURCE[0]}")" "$@"
fi

