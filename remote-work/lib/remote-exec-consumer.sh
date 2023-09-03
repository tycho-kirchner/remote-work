#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/remote_commons.sh" || exit


print_usage(){
    echo "Usage: $0 remote1@remote2 mountdir"
}

path_prepend() {
    if [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]]; then
        PATH="$1${PATH:+":$PATH"}"
    fi
}

main(){
    if [ ${#@} -ne 2 ]; then
        pr_err "invalid format: 2 arguments required"
        print_usage >&2
        exit 1
    fi

    ssh_alias="$1"
    mount_path="$2"

    # allow for local overrides
    path_prepend "$HOME/.local/lib/remote-work/remote-exec-bin"

    while read -r event; do
        event_ok=true
        # pr_info got event $event
        read -r -a word_arr <<< "$event"
        if [[ ${#word_arr[@]} -lt 2 ]]; then
            pr_warn "event has invalid format - ignore..."
            continue
        fi
        app="${word_arr[0]}"
        args=()
        for((i=1; i<${#word_arr[@]};i++));do
            arg="$(echo "${word_arr[$i]}" | base64 -d)"
            # Consider all arguments starting with / remote file paths and resolve
            # them relative to the current directory
            # Note that currently stuff like -f/home/user/somefile is not supported.
            if [[ "$arg" == /* ]]; then
                if [[ "$mount_path" == 'sftp://'* ]]; then
                    # gvfs mount: resolve from current ssh_alias
                    # arg="/run/user/$UID/gvfs/sftp:host=${ssh_alias}$arg"
                    arg="sftp://${ssh_alias}$arg"
                else
                    # sshfs mode with explicit mount
                    arg="${mount_path}$arg"
                     if [[ ! -e "$arg" ]]; then
                        pr_warn "file $arg does not exist - ignore..."
                        event_ok=false
                        break
                    fi
                fi

            fi
            args+=("$arg")
        done
        [[ $event_ok == true ]] || continue
        pr_info "executing «$app ${args[*]}»"
        setsid "$app" "${args[@]}" &
        sleep 0.25
    done < <(__async__
        while true; do
            ssh "$ssh_alias" 'PLEASE_NO_BASHRC=true
                             mkdir -p ~/.cache/remote-work
                             touch ~/.cache/remote-work/exec-events
                             stdbuf -oL tail -n0 --retry --follow=name  ~/.cache/remote-work/exec-events'
            _remote_wait_for_connection "$ssh_alias"
        done
    )
}

main "$@"; exit # exit in same line!
