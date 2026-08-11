# /etc/profile for bootstrap-toolbox: login shells skip /etc/bashrc on their own.
if [ -n "${BASH_VERSION-}" ] && [ -r /etc/bashrc ]; then
  . /etc/bashrc
fi
