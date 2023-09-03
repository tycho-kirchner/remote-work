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

REMOTE_EXEC_PRODUCER_OPEN(){
    local app="$1"
    local a
    local file
    local args=()
    local filesize

    if [ "${#@}" -lt 2 ]; then
        echo "REMOTE_EXEC: at least two args required but ${#@} given" >&2
        return 1
    fi
    shift

    if [ -z "${_remote_exec_setup_done+x}" ]; then
        _remote_exec_producer_setup || return
    fi

    for a in "$@"; do
        if [[ "$a" != -* ]]; then
            # resolve file path of non-flag
            file="$(realpath --no-symlinks "$a")"
            if ! test -e "$file"; then
                echo "REMOTE_EXEC: not exist: $a" >&2
                return 1
            fi
            a="$file"
        fi
        # base-64 encode to ensure correct word splitting
        args+=( $(echo "$a" | base64 -w 0) )
    done

    filesize=$(stat -c%s "$_remote_exec_producer_event_path") || return 1
    if [[ $filesize -gt 50000 ]]; then
        # always rotate first. It's still racy but unlikely when used interactively
        mv "$_remote_exec_producer_event_path" "$_remote_exec_producer_event_path"_old
    fi

    echo "$app ${args[@]}" >> "$_remote_exec_producer_event_path"
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

