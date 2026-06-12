#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

# If on tty1, auto-start Pegasus in cage (Wayland kiosk)
if [ "$(tty)" = "/dev/tty1" ]; then
    exec cage -- pegasus-fe
fi
