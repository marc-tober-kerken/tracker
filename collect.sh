#! /bin/bash

main(){
	# want to make sure, that first start of this procedure does not take place within first 90sec after system start
	# this way, GPS fix can be found & time can be adjusted
	l_sysstart=$(cat /proc/uptime|cut -d' ' -f1)
	if [[ $(echo "$l_sysstart < 90"|bc) == 1 ]]; then
		echo "$FUNCNAME $LINENO system boot $l_sysstart sec ago, less than 90 sec - waiting"|tee -a $_base/logfile.log
		return
	fi
	
	local l_starttime=$(date +%s)
	f_init_from_ini
	log_info "$_scriptlocal $LINENO +++++++++++++++++++++++++++ Start of processing"
	if [ -e $_base/lock ]; then
		log_warning "$_scriptlocal $LINENO Lock from other script found"
		lock_age=$(( $(date +%s) - $(cat lock) ))
		log_warning "$_scriptlocal $LINENO lock age $lock_age secs"
		if (( $lock_age >= 180 ))
		then
			rm $_base/lock
			log_error "$_scriptlocal $LINENO lock age is greater than 3min, rebooting"
			log_error "+++++++++++++++++++++++++++ $_scriptlocal $LINENO end of processing - reboot" 
			sudo shutdown -r now &
		else
			log_warning "$_scriptlocal $LINENO waiting if situation resolves itself"
		fi
	else
		echo $(date +%s) >lock
		l_timestamp=$(cat lock)
		f_create_DB $g_database
		# implement later on
		f_do_housekeeping $g_database $g_table $l_timestamp
		
		# only for testing - otherwise called by housekeeping
		# echo date $(date +%u)
		# f_do_backup /testtemp tober-kerken D$(date +%u)
		# exit
		
		f_get_position $g_database $g_table
		l_rc=$?
		if [[ "$l_rc" = "128" ]]; then
			log_error "$_scriptlocal $LINENO could not get GPS position"
			log_error "+++++++++++++++++++++++++++ $_scriptlocal $LINENO end of processing - reboot" 
			sudo shutdown -r now &
		fi
		# f_create_path_js $g_database $g_table
		# f_create_path_js $g_database path14 $g_path_js
		# exit
		# f_do_jsondata_month $g_database $g_table TempA TempWW RoomTemp1 TempKist
		# f_do_jsondata_week $g_database $g_table TempA RoomTemp1 BrennerSekunden1 BrennerSekunden2
		# f_do_jsondata_day $g_database $g_table TempA TempWW RoomTemp1 TempKist BrennerSekunden1 BrennerSekunden2
		# f_do_transfer
		# f_do_control_heating $g_database $g_table $l_timestamp
		rm lock
		log_info "$_scriptlocal $LINENO removed lock"
	fi

	log_info "$_scriptlocal $LINENO +++++++++++++++++++++++++++ runtime script $(( $(date +%s) - $l_starttime )) secs - End of processing"
}

_current=$(pwd)
_scriptlocal="$(readlink -f ${BASH_SOURCE[0]})"
_base="$(dirname $_scriptlocal)"
cd $_base
. ./functions.sh
main "$@"
cd $_current
