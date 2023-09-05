
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
  ssh multiplexing can be enabled, i.e.:
  ~~~
  Host ssh_alias
      Hostname example.host.com
      User your_user
      ControlPath ~/.ssh/controlmasters/%r@%h:%p
      ControlMaster auto
      ControlPersist 10m
  ~~~
* copy your public key to the server, e.g., by <br>
  `ssh-copy-id ssh_alias`. remote-work does not support logins by password!
* Deploy `remote-work` onto the server (only necessary once):
  ~~~
  remote-deploy ssh_alias --add-to-rc
  ~~~
  That command also adds the following code to the **remote** bashrc:
  ~~~
  source ~/.remote-work/SOURCE_ME.bash
  ~~~
  If you ommit `--add-to-rc`, bashrc is not modified but you'll have
  to add the code yourself.
  Further, a default .screenrc is deployed if none exists. If you
  already had one, native scrolling can be enabled by placing the following
  to the **remote** screenrc
  ~~~
  termcapinfo xterm* ti@:te@
  scrollback 30000
  defscrollback 30000
  startup_message off
  ~~~

* Start remote work using the terminal emulator of your choice ( by
  default [konsole](https://github.com/KDE/konsole) is used)
. Arguments after <br>
  `--terminal` are passed as is, gnome-terminal must be launched
  with `--wait`, otherwise X11 forwarding and opening of remote files
  won't work (the script waits for the terminal to close and then cleans up).
  The same applies to tilix - use `tilix --new-process` here.
  ~~~
  remote-start-work ssh_alias --terminal gnome-terminal --wait
  ~~~
  Now, every new terminal tab ssh-connects immediately and fires up a screen.

* Configure some apps to open remote files locally (via *sshfs*).
  Add apps by placing the following code to the **remote** bashrc
  ~~~
  REMOTE_EXEC_PRODUCER_ADD_APPS app1 app2 # e.g. geany evince libreoffice
  ~~~
  Delete them by calling
  ~~~
  REMOTE_EXEC_PRODUCER_DELETE_APPS app1 app2
  ~~~


## Advanced Usage
* Nested ssh-sessions: in the case of multiple machines in the LAN of
  the server, nested ssh-sessions are not uncommon. To jump right to
  the same working directory when ssh-ing to a machine, where the same
  home-directory is mounted (e.g. via NFS), place the following function
  into the remote bashrc:
  ~~~
  ssh(){
      # execute another remote_screen with the same session name, so we use the
      # same working directory when ssh'ing to the next host.
      # Do this, however, only when we no commands are executed (i.e. only one non-dash arg exists).
      # Note that this only works if arguments are passed as one string, so
      # use e.g. »-p222« instead of »-p 222«
      local n_none_dash_args=0 arg
      for arg in "$@"; do
          [[ "$arg" != -* ]] && ((++n_none_dash_args))
      done
      if [[ -n "${REMOTE_SCREEN_NUMBER+x}" && $n_none_dash_args -eq 1 ]]; then
          command ssh "$@" -t "source ~/.remote-work/SOURCE_ME.bash && remote_screen $REMOTE_SCREEN_NUMBER"
      else
          command ssh "$@"
      fi
  }
  ~~~
  Note that X11 forwarding does not work in nested ssh-sessions.
* Use remote-work without launching a terminal by <br>
  `remote-start-work ssh_alias --no-konsole`


## Requirements
Local:
~~~
sudo apt install rsync sshfs
~~~

Remote (typically already installed on a server):
~~~
sudo apt install rsync screen
~~~



## TODO Remote execution
TODO: document that paths are resolved for all arguments not starting with dashes...

## TODO Docuemnt Force usage of file path %f instead of URI %u
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




# License
The project is licensed under the GPL, v3 or later
(see LICENSE file for details) <br>
