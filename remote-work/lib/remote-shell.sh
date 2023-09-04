#!/usr/bin/env bash

# Run screen over ssh on one of the given, @-separated remote hosts.
# Each new terminal tab gets the lowest possible screen session number.
# See also screen_sessions.sh

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/remote_commons.sh" || return

cleanup(){
    local ret=$?
    rmdir "$tmpdir/$remote_screen_session_nb"
    exit $ret
}

# Delete all occurences in arr. Warning: very inefficient.
del_from_arr(){
    declare -n __del_arr="$1"
    local element="$2" new_arr=()
    # avoid index gaps by rebuilding the whole array
    # s. https://stackoverflow.com/a/16861932/7015849
    for el in "${__del_arr[@]}"; do
        [[ "$el" != "$element" ]] && new_arr+=("$el")
    done
    __del_arr=("${new_arr[@]}")
    return 0
}

reserve_session(){
    declare -n reserve_next_ret="$1"
    local min=-1 name
    for((i=1; i < 1025; i++)); do
        [ ! -d "$tmpdir/$i" ] && {
            min="$i"
            break
        }
    done
    [[ $min -eq -1 ]] && {
        pr_err "too many tabs. Bye."
        return 1
    }
    mkdir "$tmpdir/$min" || return 1
    reserve_next_ret="$min"
    return 0
}

main(){
    IFS='@' read -r -a hostnames <<< "$_REMOTE_KONSOLE_HOST"

    tmpdir="$(dirname $(mktemp -u))/remote-konsole-shell-$USER-${hostnames[0]}"
    mkdir -p "$tmpdir" || return
    add_to_exit 'cleanup'

    remote_screen_session_nb=-1
    for((i=0; i<3; i++)); do
        reserve_session remote_screen_session_nb && break
        pr_warn "Failed to reserve session number - trying again..."
        sleep 0.5
    done

    if [ $remote_screen_session_nb -eq -1 ]; then
        pr_err "giving up..."
        sleep 10
        return 1
    fi


    # Set terminal title. Konsole needs special treatment, at least
    # gnome-, mate-, and xfce4-terminal work with the other escape sequence.
    if [[ -n ${KONSOLE_VERSION+x} ]]; then
        echo -ne "\033]30;s$remote_screen_session_nb\007"
    else
        echo -ne "\033]0;s$remote_screen_session_nb\007"
    fi

    while true; do
        # in case of multiple hostnames push the last failed one to the back
        if test -f "$tmpdir/last_failed_hostname"; then
            read -r last_failed_hostname < "$tmpdir/last_failed_hostname"
            if [ -n "$last_failed_hostname" ]; then
                del_from_arr hostnames "$last_failed_hostname"
                hostnames=("${hostnames[@]}" "$last_failed_hostname")
            fi
        fi

        for hostname in "${hostnames[@]}"; do
            # Connect without X11 forwarding here. See »remote-konsole« for the rationale.
            if ssh -x -t "$hostname" "_remote_screen $remote_screen_session_nb"; then
                # On tab closing the terminal sends EOF, making ssh exit with zero.
                # At least konsole v20.12.3 then waits for 1 second, before it sends
                # a SIGHUP (s. src/Session.cpp, after that it prints »shell did not close,
                # sending SIGHUP«), so we exit fast.
                exit 0
            fi
            echo "$hostname" > "$tmpdir/last_failed_hostname"
            sleep 1
            _remote_wait_for_connection "$hostname"
        done
    done

}

main "$@"; exit # exit in same line!
