
set -o nounset -o pipefail
# Explictily set default of "no job control" in scripts. On the upside
# this allows for sending the SIGSTOP with Ctrl+Z easily to the
# whole process group and it allows a background job to kill the whole
# group in case of failure. On the downside, async background jobs get SIGINT
# set to ignore (posix requirement, s. chapter 2.11. Signals and Error Handling),
# which may be avoided using below __async__ function.
set +m # default in scripts: no new process group ID's for subprocesses.

# Place below code near the beginning of the file, due to alias expansion rules.
# Further, don't change working dir beforehand.
shopt -s expand_aliases

# do not expand non-matching globs to the pattern, if it does not exist
shopt -s nullglob

# Bash sets SIGINT to ignore for async commands, e.g.
# $ bash -c 'trap -p' & wait  # --> trap -- '' SIGINT
# As we may sometimes forget to use __async__, also
# send TERM once we receive SIGINT.
_bash_commons_pgid="$(($(ps -o pgid= -p $$)))"

_bash_commons_do_exit(){
    local ret=$?
    local usr_ret=0
    _bash_commons_within_exit=true
    trap '' INT TERM HUP QUIT PIPE

    # Also kill with TERM after we were interrupted (Ctrl+C).
    # That way, we also kill background jobs launched like »cmd & «
    if [[ -n ${_bash_commons_gotint+x} ]]; then
        env kill -TERM -- -$_bash_commons_pgid
    fi

    if [ -n "$_bash_commons_user_exit_trap" ]; then
        # Protect us from user code calling »exit«
        exit(){
            pr_warn "ignore exit request from user function »${FUNCNAME[1]}«">&2
        }
        eval "$_bash_commons_user_exit_trap" || usr_ret=$?
        if [ $usr_ret -ne 0 ]; then
            pr_err "Error $usr_ret occurred in user EXIT trap. Previous" \
                   "exit code was $ret"
            ret=$usr_ret
        fi
    fi
    builtin exit $ret
}

# Always use add_to_exit instead of trap '...' EXIT, so we
# properly kill leftovers with TERM in _bash_commons_do_exit.
add_to_exit(){
    _bash_commons_user_exit_trap+="$1"$'\n'

}
trap '_bash_commons_do_exit' EXIT
_bash_commons_user_exit_trap=''

bash_commons_set_int_trap(){
    trap "_bash_commons_gotint=true; $_bash_commons_trap_prefix 130" INT
}

# Protect the exit trap from signals - cleanup-code must not be interrupted!
_bash_commons_trap_prefix='trap "" INT TERM HUP QUIT PIPE
[[ -n ${_bash_commons_within_exit+x} || "${FUNCNAME:-main}" == _bash_commons_do_exit ]] || exit'
bash_commons_set_int_trap
trap "$_bash_commons_trap_prefix 143" TERM
trap "$_bash_commons_trap_prefix 1" HUP
trap "$_bash_commons_trap_prefix 3" QUIT
trap "$_bash_commons_trap_prefix 13" PIPE


# Allow for asynchronous execution _without_ setting INT trap to ignore.
# If $1 is --setsid, the command or function is called in a new process
# group, however, on sending a signal to $!, the whole group is killed.
# Note: when sporadic 'Terminated' messages are acceptable, it is easier
# and sufficient to just kill the whole group on INT with TERM:
# trap 'trap "" TERM; env kill -TERM -- -$$; exit 130' INT
# Usage:
# __async__ bash -c 'echo first; trap -p'; wait
# foofunc(){ bash -c 'echo foofunc; trap -p'; }
# __async__ foofunc; wait
# { __async__; exec bash -c 'echo second; trap -p'; } & wait
# cat <(__async__; exec bash -c 'echo psub; trap -p';)
# f(){ printf "%s\n" "$@"; sleep 7; wait; }; __async__ --setsid f "first arg"  "second arg"; kill $!
__async__(){
    local int_trap use_setsid
    int_trap="$(trap -p INT)"
    use_setsid=false

    [ -z "$int_trap" ] && int_trap="trap -- 'exit 130' SIGINT"
    if [ "${#@}" -eq 0 ]; then
        # Already running async, just set parent's INT handler.
        eval "$int_trap";
        return
    fi

    [[ "$1" == --setsid ]] && { shift; use_setsid=true; }

    case $(type -t "$1") in
    file)
        if [[ $use_setsid == true ]]; then
            # Forward INT and TERM to our new child process group
            {
                trap 'env kill -INT -- -$!' INT
                trap 'env kill -TERM -- -$!' TERM
                set -m
                "$@" &
                wait $!
            } &
        else
            # exec into external file so pid is same as if called like 'cmd &'
            { eval "$int_trap"; exec "$@"; } &
        fi
    ;;
    'function')
        if [[ $use_setsid == true ]]; then
            {
                trap 'env kill -INT -- -$!' INT
                trap 'env kill -TERM -- -$!' TERM
                set -m
                export -f "$1"
                bash -c '"$@"' _ "$@" &
                wait $!
            } &
        else
            { eval "$int_trap"; "$@"; } &
        fi
    ;;
    *)
        { eval "$int_trap"; "$@"; } &
    ;;
    esac
}



# Use instead of return/exit in order to print function names,
# line numbers and error code, e.g. »false || fail 3«.
__fail_script_path="$(realpath -s "${BASH_SOURCE[1]}")" # determine now, as $PWD may change
__fail='__fail_ret=$?
__fail_lineno=$(($LINENO - 1)) # interested in caller LINENO ...
__fail_mk_dummy_error(){ return $1; }
# Within a function return, otherwise exit.
if [[ -n "${FUNCNAME+x}" ]]; then
    __fail_funcname="${FUNCNAME[0]}"
    [[ $fail_always_exit == true ]] && __fail_return=exit || __fail_return=return
else
    __fail_funcname="main"
    __fail_return=exit
fi

# When this alias is called without return value, re-generate the error code.
# To be compatible with possible set -e, connect with || but only, if $ret is nonzero.
# Otherwise, just return.
[ $__fail_ret -ne 0 ] && __fail_return="__fail_mk_dummy_error $__fail_ret || $__fail_return"

__fail_linecontent="undefined"
if test -f "$__fail_script_path"; then
                                                      # $1=$1 -> trim whitespace
    __fail_linecontent_tmp="$(awk "NR==$__fail_lineno {\$1=\$1; print}" "$__fail_script_path" )" || :
    [ -n "$__fail_linecontent_tmp" ] && __fail_linecontent="$__fail_linecontent_tmp"
fi
printf "Error %d at %s near line %d »%s«\n" $__fail_ret \
        "$(basename "$__fail_script_path")::$__fail_funcname" \
        $__fail_lineno "$__fail_linecontent" >&2
eval "$__fail_return"' # trailing ' in same
                       # line due to alias argument
                       # forwarding

alias fail='eval "$__fail"'
fail_always_exit=true

pr_err(){
    echo "$(basename ${BASH_SOURCE[1]})::${FUNCNAME[1]} error: $*" >&2
}

pr_warn(){
    echo "$(basename ${BASH_SOURCE[1]})::${FUNCNAME[1]} warning: $*" >&2
}

pr_info(){
    echo "$(basename ${BASH_SOURCE[1]})::${FUNCNAME[1]} info: $*" >&2
}

element_in(){
    local el="$1"
    shift
    for cur in "$@"; do
        [[ "$el" == "$cur" ]] && return 0
    done
    return 1
}

# join_by , a b c #a,b,c
join_by(){
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

# TODO: better use
# # arr=(one "tw ho" three)
# # join_by , "${arr[@]}"
# # __ret one,tw ho,three
# join_by(){
#     local sep="$1"; shift
#     local str=""
#     for (( i=1; i <= ${#@}; i++ )); do
#         str+="${!i}"
#         [ ${i} -lt ${#@} ] && str+="$sep"
#     done
#     __ret="$str"
# }

kill_pgid(){
    env kill -INT -- -$_bash_commons_pgid
    env kill -TERM -- -$_bash_commons_pgid
}

bash_commons_enable_builtins(){
    if [ -z "${BASH_LOADABLES_PATH+x}" ]; then
        BASH_LOADABLES_PATH=$(pkg-config bash --variable=loadablesdir)
        [ -n "$BASH_LOADABLES_PATH" ] || {
            pr_err "failed to enable bash builtins"
            return 1
        }
    fi
    enable -f sleep sleep &&
    enable -f mkdir mkdir &&
    enable -f rmdir rmdir
}


tmpdir="${TMPDIR:-/tmp}"
scriptpath="$(realpath -s "${BASH_SOURCE[1]}")"
scriptdir="$(dirname "$scriptpath")"


################ END_OF bash_commons.sh  ################

# Check, if an ssh connection can be established,
# but don't do that too often. We use a global file
# whose timestamp is updated, so different scripts use the same check.
## _remote_check_connection(){
##     local ssh_alias="$1"
##     local ret=0
##     local f current_time last_time FD
##     f="${TMPDIR:-/tmp}/_remote-checknetwork-$USER"
##
##     printf -v current_time '%(%s)T' -1
##     last_time=$(stat -c %Y  "$f" 2>/dev/null)
##     [ -z "$last_time" ] && last_time=0
##
##     [[ $((current_time - last_time)) -lt 20 ]] && return 1
##     echo BUMB > "$f"
##     ssh -o ConnectTimeout=15 "$ssh_alias" true &>/dev/null || ret=$?
##     return $ret
## }

# Use an exclusive lock, so we have only one process per ssh-alias checking
# if the connection works again. By releasing the lock, we wake up all others.
_remote_wait_for_connection(){
    local ssh_alias="$1"
    local f FD
    f="${TMPDIR:-/tmp}/_remote-checknetwork-$USER-$ssh_alias"
    exec {FD}<>"$f"
    flock -x $FD
    while true; do
        if ssh -o ConnectTimeout=10 "$ssh_alias" true &>/dev/null; then
            exec {FD}<&-
            return 0
        fi
        sleep 10
    done
}

_remote_path_prepend() {
    if [[ ":$PATH:" != *":$1:"* ]]; then
        PATH="$1${PATH:+":$PATH"}"
    fi
}


bash_commons_enable_builtins &>/dev/null || true


