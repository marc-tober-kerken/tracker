#! /bin/bash

main(){
	local l_starttime=$(date +%s)
	# init_vars
	# should be replaced by f_init_from_ini
	f_init_from_ini
	log_always "$_scriptlocal $LINENO +++++++++++++++++++++++++++ Start of processing"
	if [ -e $_base/lock ]; then
		log_warning "$_scriptlocal $LINENO Lock from other script found"
		lock_age=$(( $(date +%s) - $(cat lock) ))
		log_warning "$_scriptlocal $LINENO lock age $lock_age secs"
		if (( $lock_age >= 1200 ))
		then
			rm $_base/lock
			log_error "$_scriptlocal $LINENO lock age is greater than 20min, rebooting"
			log_error "+++++++++++++++++++++++++++ $_scriptlocal $LINENO end of processing - reboot" 
			sudo shutdown -r -t sec 1 &
			exit 1
		else
			log_warning "$_scriptlocal $LINENO waiting if situation resolves itself"
		fi
	else
		echo $(date +%s) >lock
		l_timestamp=$(f_get_timestamp_rounded_5)
		f_create_DB $g_database $g_table
		# implement later on
		# f_do_housekeeping $g_database $g_table $l_timestamp
		
		# only for testing - otherwise called by housekeeping
		# echo date $(date +%u)
		# f_do_backup /testtemp tober-kerken D$(date +%u)
		# exit
		
		# use "1" for random numbers - if no sensors available
		# f_get_sensordata $g_database $l_timestamp 1
		f_get_position $g_database $l_timestamp 
		# exit
		# f_do_jsondata_month $g_database $g_table TempA TempWW RoomTemp1 TempKist
		# f_do_jsondata_week $g_database $g_table TempA RoomTemp1 BrennerSekunden1 BrennerSekunden2
		# f_do_jsondata_day $g_database $g_table TempA TempWW RoomTemp1 TempKist BrennerSekunden1 BrennerSekunden2
		# f_do_transfer
		# f_do_control_heating $g_database $g_table $l_timestamp
		rm lock
		log_info "$_scriptlocal $LINENO removed lock"
	fi

	log_always "$_scriptlocal $LINENO +++++++++++++++++++++++++++ runtime script $(( $(date +%s) - $l_starttime )) secs - End of processing"
}

_current=$(pwd)
_scriptlocal="$(readlink -f ${BASH_SOURCE[0]})"
_base="$(dirname $_scriptlocal)"
cd $_base
. ./functions.sh
main "$@"
cd $_current
