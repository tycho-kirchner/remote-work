# Maintain multiple screen sessions and manage working dirs of new
# sessions. Update DISPLAY for seamless ssh Xforwarding.
# Source from ~/.bashrc as we are needed before running screen
# as well as inside a screen bash session.

_remote_screen_eprint(){
    echo "screen_sessions::${FUNCNAME[1]}: $*" >&2
}

# Resume or create a screen session. If it is still
# attached, resume fails.
_remote_screen(){
    local screen_name="screen${1}"
    local screen_path screen_dir
    local ret=0
    local args

    if [ -n "${_REMOTE_SCREEN_NAME+x}" ]; then
        _remote_screen_eprint "Apparently you are already running inside" \
                              "a remote screen. Nothing to do."
        return 0
    fi

    # Do not use $HOME -> potentially mounted on NFS, which may cause
    # problem with sockets
    for screen_dir in "/dev/shm" "/run/shm" "/var/run/user/$UID" "${TMPDIR:-/tmp}"; do
        screen_dir+="/remote-screen-$USER"
        mkdir -p "$screen_dir" 2>/dev/null && break
    done
    ret=$?
    if [ $ret -ne 0 ]; then
        _remote_screen_eprint "Failed to find adequate location for SCREENDIR - please report"
        return $ret
    fi
    chmod 700 "$screen_dir" || return

    # format is 175720.screen1
    set -- "$screen_dir/"*".$screen_name"
    # Note: in case of no results $1 is _not_ empty, so check
    # for existence. Race condition here - we might still rarely steal
    # running screen with -R.
    screen_path="$1"

    args=(screen)
    if [ -e "$screen_path" ] ; then
        # better remove dead screens beforehand?:
        # screen -wipe >/dev/null || :
        args+=(-rd)

    else
        # Do not enter working dir of previous screen here. If it is
        # below a mount, the running screen may prevent unmounting
        # even if calling cd within the nested shell session. Instead,
        # we chdir there (we must be sourced from ~/.bashrc again).
        # do not use -R -> otherwise fuzzy search screen1 screen11 ..
        # s. https://stackoverflow.com/a/37239784/7015849
        :
    fi
    args+=(-S "$screen_name")
    _REMOTE_SCREEN_NAME="$screen_name" SCREENDIR="$screen_dir" exec "${args[@]}"
}

# During a remote_screen_session we are sourced twice: the first time,
# when bashrc is sourced during ssh login and a second time, when our
# bashrc is sourced within the screen we created above. In the first case,
# _REMOTE_SCREEN_NAME is not set, in the second it is.
if [ -z "${_REMOTE_SCREEN_NAME+x}" ]; then
    return 0
fi

########################################################################
#                       IN REMOTE SCREEN SESSION                       #
########################################################################

# allow the user calling »cdscreen 1« to enter the working dir of another session
cdscreen(){
    if [[ ${#@} -eq 0 ]]; then
        # join latest
        cd "$(readlink "$_remote_screen_symlink_dir/latest")"
    else
        cd "$(readlink "$_remote_screen_symlink_dir/screen$1")"
        _remote_screen_update_symlink
    fi
}

# Re-read screen's scrollback-buffer into the local terminal buffer.
# This function is usually not needed, as »remote-work« is designed
# to be never closed. Even on connection-drop, the content is still in the
# local terminal buffer. However, if, e.g. a reboot of the LOCAL machine
# is necessary (or the terminal crashes), it is desirable to dump screen's
# buffer into the local terminal buffer, so scrolling works as usual.
# Note that for this to work, it is not allowed, to regularly close the
# terminal - on EOF the screen-sessions are closed. Instead, abort
# »remote-konsole« with Ctrl+C.
screen_rewritebuf(){
    local temp_file
    local ret=0
    local last_size="-1"
    local size
    if [ -z "${_REMOTE_SCREEN_NAME+x}" ]; then
        _remote_screen_eprint "_REMOTE_SCREEN_NAME is not set"
        return 1
    fi
    temp_file=$(mktemp)
    screen -S "$_REMOTE_SCREEN_NAME" -X hardcopy -h "$temp_file" || ret=$?
    if [ $ret -eq 0 ]; then
        while true; do
            sleep 0.25
            size=$(stat -c%s "$temp_file") || break
            if [[ $size == $last_size ]]; then
                # echo "tmp file content at $temp_file is $(tail -500 "$temp_file" )"
                # screen -S "$_REMOTE_SCREEN_NAME" -X stuff "./start-build^M"
                # "clear" old content
                yes '' | head -n90000
                iconv -f ISO-8859-1 -t UTF-8 "$temp_file"
                break
            fi
            last_size=$size
        done
    else
        _remote_screen_eprint "hardcopy failed with $ret"
    fi
    rm "$temp_file"
    return $ret
}

_remote_screen_update_symlink () {
    ln -sfn "$PWD" "$_remote_screen_symlink_dir/$_REMOTE_SCREEN_NAME"
    ln -sfn "$PWD" "$_remote_screen_symlink_dir/latest"

    echo "$PWD" > "$_remote_screen_symlink_dir/$_REMOTE_SCREEN_NAME".txtlink
    echo "$PWD" > "$_remote_screen_symlink_dir"/latest.txtlink
}

_remote_screen_get_dpy(){
    local display
    if test -f "$_remote_screen_display_file"; then
        read -r display <"$_remote_screen_display_file"
        echo "$display"
        return 0
    fi
    return 1
}

_remote_screen_ps0(){
    _remote_screen_get_dpy
    # Only DISPLAY may be written to stdout
    _remote_screen_update_symlink >/dev/null
}

_remote_screen_prompt(){
    local ret=$?
    DISPLAY=''
    if [ $_remote_screen_needs_prompt -ne 0 ]; then
        _remote_screen_update_symlink
        _remote_screen_needs_prompt=0
    fi
    return $ret
}

# running inside screen session,
# create a symlink to our working dir, so cdscreen works.
# Do so before executing any command (PS0), to allow
# joining the screen dir of long running commands.
_remote_screen_session_init(){
    local working_dir
    local s display

    _remote_screen_display_file="${TMPDIR:-/tmp}/remote-screen-display-$USER"
    _remote_screen_symlink_dir="$HOME/.cache/remote-work/cwd-links"
    _remote_screen_needs_prompt=0
    _remote_screen_empty=''

    # We may be sourced interactively, non-interactively and nested, so
    # only overwrite DISPLAY if not already set. This allows e.g. noninteractive
    # scripts sourcing .bashrc to use a custom DISPLAY.
    display="${DISPLAY:-}"
    if [ -z "$display" ]; then
        display="$(_remote_screen_get_dpy)"
    fi
    export DISPLAY="$display"

    # Non-interactive invocation using bash -c, no need to set prompts.
    [ -n "${BASH_EXECUTION_STRING+x}" ] && return 0
    if [ -n "${_remote_screen_init_done+x}" ]; then
        _remote_screen_eprint "already initialized..."
        return 0
    fi

    # Running interactively.
    # After ssh connection breakages, $DISPLAY may need to change, e.g., due to
    # other users possibly occupying the port we used previously.
    # So, before executing any command, we update DISPLAY according to
    # X11-forwarding, stored in $_remote_screen_display_file (see
    # also remote-konsole). However, In PS0 we cannot assign variables as usual
    # but have to fallback to nasty parameter expansion tricks:
    # First we abuse an arithmetic expression
    # within substring-expansion to remember for our PROMPT_COMMAND that a "real"
    # command was entered (and not just i.e. ENTER pressed).
    # Then we assign DISPLAY by using :=, making sure to always clear it
    # again in PROMPT_COMMAND (otherwise no re-assignment is possible).
    # Note that in both cases nothing is printed: the first substring
    # has length zero, while in the second case we replace a non-existing
    # pattern in the empty variable with the empty string.
    mkdir -p "$_remote_screen_symlink_dir" || return
    chmod 700 "$_remote_screen_symlink_dir" || return

    s='${_remote_screen_empty:((_remote_screen_needs_prompt=1)):0}'
    s+='${_remote_screen_empty//${DISPLAY:=$(_remote_screen_ps0)}//}'

    [ -z "${PS0+x}" ] && PS0=''
    PS0+="$s"
    [ -z "${PROMPT_COMMAND+x}" ] && PROMPT_COMMAND=''
    PROMPT_COMMAND=$'_remote_screen_prompt\n'"${PROMPT_COMMAND}"
    _remote_screen_init_done=true

    # "$(readlink "$_remote_screen_symlink_dir/$_REMOTE_SCREEN_NAME")"
    for working_dir in "$(readlink "$_remote_screen_symlink_dir/latest")"; do
        if [ -d  "$working_dir" ]; then
            cd "$working_dir" && break
        fi
    done
    _remote_screen_update_symlink
}

if [ -z "${BASH_SUBSHELL+x}" ]; then
    _remote_screen_eprint "Bad shell: BASH_SUBSHELL is not set"
    return 1
fi

_remote_screen_session_init



