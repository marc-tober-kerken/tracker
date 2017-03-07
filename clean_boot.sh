#! /bin/bash

# put this script in after each boot
# crontab entry of user pi:
# @reboot cd /tracker/dev && ./clean_boot.sh

main(){
	f_check_time
	l_rc=$?
	if [[ "$l_rc" = "128" ]]; then
		echo "no GPS - rebooting in 30 sec, forcing diskcheck"|tee -a $_base/logfile.log
		sudo touch /forcefsck
		sleep 30
		sudo shutdown -r -t sec 3 &
		exit 1
	fi 
	local l_starttime=$(date +%s)
	f_init_from_ini
	log_always "$_scriptlocal $LINENO ++++BOOT++++++++++++++++++ Cleanup after boot"
	if [ -e $_base/lock ]; then
		log_always "$_scriptlocal $LINENO Lock from other script found"
		lock_age=$(( $(date +%s) - $(cat lock) ))
		log_always "$_scriptlocal $LINENO lock age $lock_age secs"
		if (( $lock_age >= 15 ))
		then
			log_always "$_scriptlocal $LINENO $_base/lock found - interrupted by shutdown or power failure"
			rm $_base/lock
			sudo touch /forcefsck
			sudo shutdown -r -t sec 3 &
			return 1
		else
			log_always "$_scriptlocal $LINENO $_base/lock found - currently running after clean start"
		fi
	else
		log_always "$_scriptlocal $LINENO no $_base/lock found - assuming consistent tracker"
	fi

	log_always "$_scriptlocal $LINENO ++++BOOT++++++++++++++++++ runtime script $(( $(date +%s) - $l_starttime )) secs - End of processing"
}

_current=$(pwd)
_scriptlocal="$(readlink -f ${BASH_SOURCE[0]})"
_base="$(dirname $_scriptlocal)"
cd $_base
. ./functions.sh
main "$@"
cd $_current
