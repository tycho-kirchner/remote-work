
# Dependencies
Local:
~~~
sudo apt install rsync
~~~
Remote:
~~~
sudo apt install screen
~~~



# Remote setup
~~~
TODO
~~~

Into ~/.bashrc
~~~
source ~/.lib/remote_exec_producer.sh
if [ $? -eq 0 ]; then
    REMOTE_EXEC_PRODUCER_SETUP
    for a in atril caja geany okular pcmanfm kdiff3 eom libreoffice chromium; do
        REMOTE_EXEC_PRODUCER_ADD_APP "$a"
    done
fi
~~~

# Local setup
~~~
TODO
~~~


# Remote execution
TODO: document that paths are resolved for all arguments not starting with dashes...

# Force usage of file path %f instead of URI %u
create desktop file launch-uri-as-path.desktop
~~~
[Desktop Entry]
# Usage:
# $ gtk-launch launch-uri-as-path "$(which  echo)" 'sftp://bcl100/home/lakatos/tkirch/bar.pdf'  'sftp://bcl100/home/lakatos/kk'
# /run/user/1000/gvfs/sftp:host=bcl100/home/lakatos/tkirch/bar.pdf /run/user/1000/gvfs/sftp:host=bcl100/home/lakatos/kk
Version=1.0
Name=launch-uri-as-path
Exec=bash -c '"$@"' _ %F
# Exec=%F
Terminal=false
# X-MultipleArgs=false
Type=Application
~~~

Into ~/.local/lib/remote-exec/bin/okular
exec gtk-launch launch-uri-as-path /usr/bin/okular "$@"


# TODO: document remote nested screens (ssh to another host in same network):
~~~
ssh(){
    # export screen name, so we use same working directory when ssh'ing to the next host.
    # Do this, however, only in simple cases, where ssh gets no other arguments.
    if [[ ${#@} -eq 1 ]]; then
        command ssh -t "$1" _SCREEN_NAME="$_SCREEN_NAME" bash
    else
        command ssh "$@"
    fi
}
~~~

# License
The project is licensed under the GPL, v3 or later
(see LICENSE file for details) <br>
