#!/bin/sh

set -e

mkdir -p "$HOME/.xpra"

cd "$(dirname "$0")"
basename="$0"
while basename="$(readlink "$(basename "$basename")")"
do
	cd "$(dirname "$basename")"
done
pwd

test -x trunk/src/install/bin/xpra || (
	modules="libx11-dev libxtst-dev libxcomposite-dev libxdamage-dev python-gobject-dev python-gtk2-dev xvfb cython libx264-dev libswscale-dev libavcodec-dev libvpx-dev"
	if ! dpkg -l $modules
	then
		sudo apt-get install $modules || exit
	fi
	cd trunk/src
	./setup.py install --home=install
)

export PYTHONPATH=$PWD/trunk/src/install/lib/python:$PYTHONPATH

if test $# = 0
then
	display=97
	case "$SESSION_MANAGER" in
	*iMac*)
		if fuser $HOME/.xpra/$display.log
		then
			set attach :$display
		else
			set -- --xvfb="Xorg -dpi 96 -noreset -verbose +extension GLX +extension RANDR +extension RENDER -logfile $HOME/.xpra/$display.log -config $PWD/xorg.conf" "--start-child=dbus-launch gnome-terminal" start --bind-tcp=127.0.0.1:$((9900+$display)) :$display
		fi
		;;
	*)
		set attach ssh:bigmac:$display
		;;
	esac
fi

case "$*" in
"attach :"[1-9]*)
	DISPLAY="$2" xrandr -s 2048x2048
	;;
esac

exec ./trunk/src/install/bin/xpra "$@"
