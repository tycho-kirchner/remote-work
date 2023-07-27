
# This is the toplevel script meant to be sourced from bashrc on the local host.
# If we were not launched from »remote-konsole«,
# this script only exports our scripts via $PATH.
# Else we jump directly into our remote-shell script which fires ssh.

# @ separated list of hostnames
if [ -z "${_REMOTE_KONSOLE_HOST+x}" ]; then
    # not remote. Make our scripts available in PATH:
    _remote_do_add_path(){
        local p
        p="$(realpath "${BASH_SOURCE[0]}")"
        p="${p%/*}"
        p="${p%/*}/bin"
        if [[ ":$PATH:" != *":$p:"* ]]; then
            PATH="$p${PATH:+":$PATH"}"
        fi
        return 0
    }
    _remote_do_add_path
    unset _remote_do_add_path
    return 0
else
    _remote_p="$(realpath "${BASH_SOURCE[0]}")"
    _remote_p="${_remote_p%/*}"
    exec "${_remote_p%/*}/lib/remote-shell.sh"
fi
