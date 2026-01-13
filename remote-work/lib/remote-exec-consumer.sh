#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/remote_commons.sh" || exit


print_usage(){
    echo "Usage: $0 remote mountdir"
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

    # Do not »while read -r event...« - read may rarely fail, e.g. with
    # "read error: 0: Resource temporarily unavailable".
    while true; do
        read -r -a word_arr || continue
        if [[ ${#word_arr[@]} -lt 2 ]]; then
            pr_warn "ignoring event with invalid format: »${word_arr[*]}«"
            continue
        fi
        args=()
        event_ok=true
        for((i=0; i<${#word_arr[@]};i++));do
            arg="$(echo "${word_arr[$i]}" | base64 -d)" || {
                pr_err "error base64-decoding »${word_arr[$i]}«"
                event_ok=false;
                break;
            }
            if [[ "$arg" == ///* ]]; then
                # We use /// as a special marker for file paths that should be kept "as is", e.g.
                # for code --remote ssh-remote+alias ///home/user/foo
                pr_info "arg starts with ///, not prefixing mount-path ${mount_path} for $arg"
                arg=${arg#//}
            elif [[ "$arg" == /* ]]; then
                # Consider all arguments starting with / remote file paths and resolve
                # them relative to the mount point. First arg is always the remote working dir
                # Note that currently stuff like -f/home/user/somefile is not supported.
                if [[ "$mount_path" == 'sftp://'* ]]; then
                    # gvfs mount: resolve from current ssh_alias
                    # arg="/run/user/$UID/gvfs/sftp:host=${ssh_alias}$arg"
                    arg="sftp://${ssh_alias}$arg"
                else
                    # sshfs mode with explicit mount
                    if [[ -e "${mount_path}${arg}" ]]; then
                        arg="${mount_path}${arg}"
                    else
                        pr_warn "Using $arg as is, it does not exist at ${mount_path}${arg}"
                    fi
                fi

            fi
            args+=("$arg")
        done
        [[ $event_ok == true ]] || { pr_err "malformed event, ignore..."; continue; }
        # first arg is always the remote working dir
        cwd="${args[0]}"
        args=("${args[@]:1}")

        pr_info "at $cwd executing »${args[*]}«"
        { cd "$cwd" && exec setsid "${args[@]}"; } &
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
