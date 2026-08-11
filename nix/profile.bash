# Installed as /etc/profile: login shells skip /etc/bashrc on their own.
# shellcheck source=/dev/null
if [ -n "${BASH_VERSION-}" ] && [ -r /etc/bashrc ]; then
  . /etc/bashrc
fi
