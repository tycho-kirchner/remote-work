
# Remote-work
Seamless working via ssh as if running locally.
* Each terminal tab runs automatically within its own screen so native
  scrolling and searching works
* Remote files can be opened **from within the ssh session** with your
  local text editor (or any other app)
* ssh X11-forwarding is stabilized, even during days-lasting screen-sessions
* Transparent handling of connection-dropouts - all terminal-tabs reconnect automatically


## Usage
* Place the following into your **local** bashrc
  ~~~
  source /$PATH_TO/remote-work/SOURCE_ME.bash
  ~~~
* Setup the ssh-alias as usual (`~/.ssh/config`). To open new tabs faster,
  ssh multiplexing should be enabled, i.e.:
  ~~~
  Host ssh_alias
      Hostname example.host.com
      User your_user
      ControlPath ~/.ssh/controlmasters/%r@%h:%p
      ControlMaster auto
      ControlPersist 10m
  ~~~
* Install `remote-work` on the server (only necessary once for each server):
  ~~~
  remote-deploy ssh_alias
  ~~~
  and activate it by placing the following to the beginning of the **remote**
  bashrc:
  ~~~
  source ~/.remote-work/SOURCE_ME.bash
  ~~~
  This will also deploy a default .screenrc. If you
  already had one, native scrolling can be enabled by placing the following
  to the **remote** screenrc
  ~~~
  termcapinfo xterm* ti@:te@
  scrollback 30000
  defscrollback 30000
  startup_message off
  ~~~

* Start remote work using konsole, or the terminal of your choice. Arguments after
  `--terminal` are passed as is, gnome-terminal must be launched
  with `--wait`, otherwise X11 forwarding won't work.
  ~~~
  remote-start-work ssh_alias --terminal gnome-terminal --wait
  ~~~
  Now, every new terminal tab immediately ssh-connects and fires up a screen.

* Configure some apps to open remote files locally (via sshfs).
  Add apps by placing <br>
  `REMOTE_EXEC_PRODUCER_ADD_APPS app1 app2` to the end
  of the **remote** bashrc, e.g.
  ~~~
  REMOTE_EXEC_PRODUCER_ADD_APPS geany evince libreoffice
  ~~~


## Requirements
Local:
~~~
sudo apt install rsync sshfs
~~~

Remote (screen is usually already installed):
~~~
sudo apt install screen
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
