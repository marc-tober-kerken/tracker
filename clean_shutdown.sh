#! /bin/bash

# this is script for safe shutdown when usv reports power failure

main(){
	local l_starttime=$(date +%s)
	f_init_from_ini
	log_always "$_scriptlocal $LINENO ++++CLEAN SHUTDOWN USV++++ Start"
	sudo service cron stop
	if [ -e $_base/lock ]; then
		lock_age=$(( $(date +%s) - $(cat lock) ))
		log_always "$_scriptlocal $LINENO lock found - age $lock_age secs, wait 10 sec"
		sleep 10
		if [ -e $_base/lock ]; then
			rm $_base/lock
			log_error "$_scriptlocal $LINENO lock still existed - now deleted, shutting down now"
		fi
	fi
	sudo shutdown -h now &
	log_always "$_scriptlocal $LINENO ++++CLEAN SHUTDOWN USV++++ shutdown sent"
}

_current=$(pwd)
_scriptlocal="$(readlink -f ${BASH_SOURCE[0]})"
_base="$(dirname $_scriptlocal)"
cd $_base
. ./functions.sh
main "$@"
cd $_current


# pi@lmcpi:~ $  sudo dpkg -i piupsmon-0.9.deb
# Vormals nicht ausgewähltes Paket piupsmon wird gewählt.
# (Lese Datenbank ... 33952 Dateien und Verzeichnisse sind derzeit installiert.)
# Vorbereitung zum Entpacken von piupsmon-0.9.deb ...
# Entpacken von piupsmon (0.9) ...
# piupsmon (0.9) wird eingerichtet ...
# Trigger für systemd (215-17+deb8u5) werden verarbeitet ...

# vi /etc/piupsmon/piupsmon.conf

# ShutdownTimer=<Zeit in Sekunden>
# Dieser Wert gibt an, wie lange das System weiter läuft, nachdem die Spannungs-
# versorgung auf den Akku gewechselt ist. Es sind Werte zwischen 1 - 999.999.999.
# möglich.

# PowerOffTimer=<Zeit in Sekunden>
# Dieser Wert gibt an, wie lange die PiUSV+ noch eingeschaltet bleiben soll, nachdem
# der Befehl zum Herunterfahren gesendet wurde. Es kann hier ein Wert zwischen 1 -
# 255 angegeben werden.

# ShutdownCmd=<Befehlszeile>
# Mit dieser Option geben Sie einen Befehl an, mit dem die PiUSV+ heruntergefahren
# werdensoll.Siekönnenhierz.B.direktdenBefehlzumAusschaltengebenodereinei-
# genes Skript hinterlegen. Wenn Sie ein eigenes Skript hinterlegen, müssen Sie darauf
# achten, dass das Betriebssystem durch das Skript heruntergefahren wird.
# default:
# ShutdownCmd=init 0
# 

# LogLevel=<notice|error|debug>
# Mit dieser Option können Sie steuern, welche Einträge im Log gespeichert werden
# sollen.

# LogStatusDesc=<0|1>
# Mit dem Befehl können Sie beinflussen, ob bei Statusänderungen nur ein nummeri-
# scher Wert oder auch eine Beschreibung zu diesem Wert geloggt wird

# cat /var/log/piupsmon.log
# tail -f /var/log/piupsmon.log
# sudo /etc/init.d/piupsmon status
# sudo /etc/init.d/piupsmon stop
# sudo /etc/init.d/piupsmon start
