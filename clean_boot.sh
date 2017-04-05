#! /bin/bash

# put this script in after each boot
# crontab entry of user pi:
# @reboot cd /tracker/dev && ./clean_boot.sh

main(){
	# this is 2037, so that the standard collect.sh will not be able to start until
	# this clean_boot.sh script is finished
	# "master lock" only during boot
	# echo 2114377200 >$_base/lock
	f_check_time
	l_rc=$?
	if [[ "$l_rc" = "128" ]]; then
		echo "no GPS - rebooting in 30 sec, forcing diskcheck"|tee -a $_base/logfile.log
		rm $_base/lock
		sudo touch /forcefsck
		sleep 1
		sudo shutdown -r now &
	fi 
	local l_starttime=$(date +%s)
	f_init_from_ini
	log_always "$_scriptlocal $LINENO ++++BOOT++++++++++++++++++ Cleanup after boot"
	log_always "$_scriptlocal $LINENO ++++BOOT++++++++++++++++++ Start DB integrity check for $g_database"
	local l_db_consistent=$(sqlite3 $g_database "pragma integrity_check;")
	log_always "$_scriptlocal $LINENO ++++BOOT++++++++++++++++++ DB integrity check on $g_database done"
	if [[ -e "$_base/lock" ]]; then
		rm $_base/lock
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
