#! /bin/bash

# OPL:
# - implementieren von Teamviewer done
# - implementieren WIFI done
# - backup
# - logrotate; DB Backup_monthly, daily
# - optimierung Dateierstellung im 00:00
# - Gauge Darstellung / Zahlendarstellung / Google Fonts
# - check initialization for production + ini file for production
# - beautify charts
# - create bar / line combochart 
# - maybe implement local webserver
# - append date instead of creating everything

# 
# required settings: 
# - mailx has to be configured
#
# cronjob:
# m h  dom mon dow   command
# */15 * *   *   *     cd /testtemp && ./collect.sh
# */15 * *   *   *     cd /production && ./collect.sh
# 
# logrotate - place file in /etc/logrotate.d
# /testtemp/logfile.log /production/logfile.log {
        # monthly
        # copytruncate
        # rotate 6
        # compress
		# missingok
# }

function f_init_from_ini()
{
# This function initializes the relevant variables from a .ini file
# ini file need to be located in same directory as the functions.sh file

# filename with full path
local l_own_name=$(readlink -f ${BASH_SOURCE[0]})

# same, but without exntension
local l_own_name_wo="${l_own_name%.*}"

# directory of script, without trailing /
local l_own_path=$(dirname $l_own_name)

local l_current_dir=$(pwd)
cd "$l_own_path"

declare -r -g g_logfile=$l_own_path/logfile.log

local l_inifile="$l_own_name_wo"".ini"
if [[ ! -f "$l_inifile" ]]; then
	echo "$FUNCNAME $LINENO ini file $l_inifile not found"|tee -a $g_logfile
	return 1
fi

if [[ ! -d "$l_own_path/data" ]]; then
	log_info "$FUNCNAME $LINENO create data directory $l_own_path/data"
	mkdir -p "$l_own_path/data"
fi

# 1=only fatal; 2=only fatal+error; 3=...+warning; 4=...+info; 5=...+debug
g_log_level=$(grep "^g_log_level" "$l_inifile"|cut -d= -f2)
# echo Loglevel $g_log_level from $l_inifile
log_debug "$FUNCNAME $LINENO initialized g_log_level with $g_log_level"

declare -r -g g_database=$(grep "^g_database" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_database with $g_database"

declare -r -g g_table=$(grep "^g_table" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_table with $g_table"

declare -r -g g_subdomain=$(grep "^g_subdomain" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_subdomain with $g_subdomain"

declare -r -g g_mail_rcpt=$(grep "^g_mail_rcpt" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_mail_rcpt with \"$g_mail_rcpt\""

declare -r -g g_object=$(grep "^g_object" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_object with \"$g_object\""

# declare -r -g g_path_js=$(grep "^g_path_js=" "$l_inifile"|cut -d= -f2)
declare -r -g g_path_json=$(grep "^g_path_json=" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_path_json with \"$g_path_json\""

declare -r -g g_markers_json=$(grep "^g_markers_json=" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_markers_json with \"$g_markers_json\""

}

function f_check_time()
{
# This function checks if time of raspi os is valid
# if raspi is used offline, it does not have access to NTP server and has no accurate time
# will use timestamp from gps if this is the case
local l_own_name=$(readlink -f ${BASH_SOURCE[0]})
local l_own_path=$(dirname $l_own_name)
local l_logfile=$l_own_path/logfile.log

echo "$FUNCNAME $LINENO Get time from GPS after reboot"|tee -a $l_logfile

# i=0
# l_bt_active=false
# while [[ "$l_bt_active" = "false" && $i < 5 ]]; do
	# i=$(( $i + 1 ))
	# l_bt_status=$(sudo systemctl status bluetooth|grep "Active:"|awk '{print $2}')
	# if [[ "$l_bt_status" = "active" ]]; then
		# echo "$FUNCNAME $LINENO iteration $i bluetooth active"|tee -a $l_logfile
		# l_bt_active=true
	# else
		# echo "$FUNCNAME $LINENO iteration $i waiting for bluetooth"|tee -a $l_logfile
		# sleep 5
	# fi
# done


local l_valid_data=false
local i=0
while [[ "$l_valid_data" = "false" && $i < 5 ]]; do
	l_valid_data=true
	i=$(( $i + 1 ))
	local l_gpsdata=$(gpspipe -w -n 10| grep -m 1 time)
	local l_gpstimestring=$(echo "$l_gpsdata" | jq '.time'| sed -e 's/^"//' -e 's/"$//')
	l_result=$(date -d $l_gpstimestring +%s >/dev/null 2>&1)
	l_rc=$?
	if [[ "$l_rc" != "0" ]]; then
		echo "$FUNCNAME $LINENO loop $i string $l_gpstimestring invalid - no GPS fix yet"|tee -a $l_logfile
		l_valid_data=false
	fi
done

if [[ "$l_valid_data" = "true" ]]; then
	local l_gpstime=$(date -d $l_gpstimestring +%s)
	local l_systime=$(date +%s)
	local l_diff=$(echo "$l_gpstime - $l_systime"|bc -l|tr -d -)

	if (( $l_diff > 50 )); then
		sudo date -s @$l_gpstime
		echo "$FUNCNAME $LINENO Time Difference detected - use GPS time $l_gpstimestring - systime was $(date -d @$l_systime) - is now $(date)"|tee -a $l_logfile
	else
		echo "$FUNCNAME $LINENO No Time Difference detected - GPS $l_gpstimestring - sysdate $(date)"|tee -a $l_logfile
	fi
else
	echo "$FUNCNAME $LINENO GPS timestring data $l_gpstimestring invalid - bad reception?"|tee -a $l_logfile
	return 128
fi
}

log_debug(){
  if [[ $g_log_level -ge 5 ]]
  then
    do_log DEBUG $1
  fi
}

log_debug_silent(){
  if [[ $g_log_level -ge 5 ]]
  then
    do_log_silent DEBUG $1
  fi
}

log_info(){
  if [[ $g_log_level -ge 4 ]]
  then
    do_log INFO $1
  fi
}

log_info_silent(){
  if [[ $g_log_level -ge 4 ]]
  then
    do_log_silent INFO $1
  fi
}

log_warning(){
  if [[ $g_log_level -ge 3 ]]
  then
    do_log WARN $1
  fi
}

log_warning_silent(){
  if [[ $g_log_level -ge 3 ]]
  then
    do_log_silent WARN $1
  fi
}

log_error(){
  if [[ $g_log_level -ge 2 ]]
  then
    do_log ERROR $1
  fi
}

log_error_silent(){
  if [[ $g_log_level -ge 2 ]]
  then
    do_log_silent ERROR $1
  fi
}

log_fatal(){
  if [[ $g_log_level -ge 1 ]]
  then
    do_log FATAL $1
  fi
}

log_always(){
    do_log ALWAYS $1
}

do_log(){
  declare -r l_severity=$1
  shift
  echo $(date +"%Y-%m-%d %H:%M:%S") "$l_severity" "$*" | tee -a $g_logfile
}

do_log_silent(){
  declare -r l_severity=$1
  shift
  echo $(date +"%Y-%m-%d %H:%M:%S") "$l_severity" "$*" >>$g_logfile
}

function f_checkFloat {
local -r i_number="$1"

    regExp='^[+-]?([0-9]+\.?|[0-9]*\.[0-9]+)$'
    if [[ $i_number =~ $regExp ]]
    then
        echo "OK"
    else
        echo "NAN"
    fi
}


f_do_housekeeping(){
# wrapper function to call 
# - DB reorg: delete unneeded values (not done/necessary here)
# - backup DB/software + upload to webserver as backup
log_info "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
local -r i_db="$1"
local -r i_table="$2"
local -r i_unixtime="$3"

if [[ "$i_db" = "" ]]; then
	log_error "$FUNCNAME $LINENO no db specified"
fi

if [[ "$i_table" = "" ]]; then
	log_error "$FUNCNAME $LINENO no table specified"
fi

if [[ "$i_unixtime" = "" ]]; then
	log_error "$FUNCNAME $LINENO no timestamp specified"
fi

# uncomment for testing
# log_info "$FUNCNAME $LINENO perform daily housekeeping"
# f_do_backup $_base tober-kerken D$(date -d @$i_unixtime +%u)

# uncomment for testing
# log_info "$FUNCNAME $LINENO perform monthly housekeeping"
# f_do_backup $_base tober-kerken M$(date -d @$i_unixtime +%m)
# sqlite3 $i_db "vacuum;"

if [[ ! -e logrotate_tracker.conf ]]; then
	log_info "$FUNCNAME $LINENO create logrotate entry for $_base/*.log"
	touch logrotate_tracker.conf
	
sudo cat >> logrotate_tracker.conf <<f_do_housekeeping_EOF
$_base/*.log {
rotate 6
weekly
compress
sharedscripts
}
f_do_housekeeping_EOF

	sudo chmod 644 logrotate_tracker.conf
	sudo chown root:root logrotate_tracker.conf

fi

if [ -e $_base/daily ]; then
	l_daily_age=$(( $(date +%s) - $(cat daily) ))
	log_debug "$_scriptlocal $LINENO last daily task was $l_daily_age sec ago"
	if (( $l_daily_age >= 86400 )); then
		log_info "$FUNCNAME $LINENO perform daily backup"
		f_do_backup $_base tober-kerken D$(date -d @$i_unixtime +%u)
		log_info "$FUNCNAME $LINENO run logrotate"
		sudo logrotate logrotate_tracker.conf
		echo $(date +%s) >$_base/daily
	else
		log_info "$FUNCNAME $LINENO daily task not yet due - $l_daily_age sec ago"
	fi
else
	echo $(date +%s) >$_base/daily
fi

if [ -e $_base/monthly ]; then
	l_monthly_age=$(( $(date +%s) - $(cat monthly) ))
	log_debug "$_scriptlocal $LINENO last monthly task was $l_monthly_age sec ago"
	if (( $l_monthly_age >= 2592000 )); then
		log_info "$FUNCNAME $LINENO perform monthly backup"
		f_do_backup $_base tober-kerken M$(date -d @$i_unixtime +%m)
		# 63936000 = 740 days
		# local l_time_limit=$(( $i_unixtime - 63936000 ))
		# local l_old_records=$(sqlite3 $i_db "select count(1) from $i_table where unixtime<=$l_time_limit;")
		# log_info "$FUNCNAME $LINENO removing data older than $(date -d @$l_time_limit) - $l_old_records records found"
		# sqlite3 $i_db "delete from $i_table where unixtime<=$l_time_limit;"
		sqlite3 $i_db "vacuum;"
		log_info "$FUNCNAME $LINENO DB reorg performed."
		echo $(date +%s) >$_base/monthly
	else
		log_info "$FUNCNAME $LINENO monthly task not yet due - $l_monthly_age sec ago"
	fi
else
	echo $(date +%s) >$_base/monthly
fi


log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

f_get_single_value(){
# function to retriev a single value from the database
# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: field name
# input parameter 4: unixepoch time for desired datapoint

# output:
# value of field for specified unixepoch time.
local -r i_db="$1"
local -r i_table="$2"
local -r i_field="$3"
local -r i_unixtime="$4"

local i_return=$(sqlite3 $i_db "select $i_field from $i_table where unixtime=$i_unixtime;")
echo $i_return
}

f_create_markers_json(){
log_info "$FUNCNAME $LINENO start $1 $2 $3"
local -r -i l_runtime=$SECONDS
# function to create file with positions
# for markers in google maps
# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: filename with markers for google maps

local -r i_db="$1"
local -r i_table="$2"
local -r i_filename="$3"

cat > $i_filename <<f_create_markers_json_EOF
eqfeed_callback({
	"type":"FeatureCollection",
	"features": [
f_create_markers_json_EOF


l_datapoints=$(sqlite3 $i_db "select unixtime from $i_table order by unixtime;")

for l_datapoint in $l_datapoints
do 
	l_lat=$(f_get_single_value $i_db $i_table latitude_n $l_datapoint)
	l_lon=$(f_get_single_value $i_db $i_table longitude_e $l_datapoint)
	l_elevation=$(f_get_single_value $i_db $i_table elevation $l_datapoint)
	log_debug "$FUNCNAME $LINENO processing $l_datapoint, got $l_lat $l_lon $l_elevation"
	if [[ "$l_elevation" = "" ]]; then
		l_coordinates="[$l_lon,$l_lat]"
	else
		l_coordinates="[$l_lon,$l_lat,$l_elevation]"
	fi

cat >> $i_filename <<f_create_markers_json2_EOF
			{"type":"Feature",
			"properties":{
				"time":$l_datapoint
			},
			"geometry":{
				"type":"Point",
				"coordinates":$l_coordinates
			}
		},
f_create_markers_json2_EOF

done

# remove last line "}," - has to be without ","
sed -i '$ d' $i_filename

cat >> $i_filename <<f_create_markers_json3_EOF
		}
	]
})
f_create_markers_json3_EOF

log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

f_create_path_json(){
log_info "$FUNCNAME $LINENO start $1 $2 $3"
local -r -i l_runtime=$SECONDS
# function to create file with positions
# for markers in google maps
# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: filename with markers for google maps

local -r i_db="$1"
local -r i_table="$2"
local -r i_filename="$3"

cat > $i_filename <<f_create_path_json_EOF
[
f_create_path_json_EOF


l_datapoints=$(sqlite3 $i_db "select unixtime from $i_table order by unixtime;")

# l_filename_snap="$i_filename""-snap"

for l_datapoint in $l_datapoints
do 
	l_lat=$(f_get_single_value $i_db $i_table latitude_n $l_datapoint|awk '{printf "%2.6f", $0}')
	l_lon=$(f_get_single_value $i_db $i_table longitude_e $l_datapoint|awk '{printf "%2.6f", $0}')
	l_elevation=$(f_get_single_value $i_db $i_table elevation $l_datapoint)
	log_debug "$FUNCNAME $LINENO processing $l_datapoint, got $l_lat $l_lon $l_elevation"
	if [[ "$l_elevation" = "" ]]; then
		l_coordinates="[$l_lon,$l_lat]"
	else
		l_coordinates="[$l_lon,$l_lat,$l_elevation]"
	fi

	l_date_human=$(date -d @$l_datapoint +"%d.%m.%Y %H:%M")

cat >> $i_filename <<f_create_path_json2_EOF
{
"title": "$l_date_human",
"lat": $l_lat,
"lng": $l_lon
},
f_create_path_json2_EOF

# printf "$l_lat,$l_lon|" >>$l_filename_snap

done

# remove last line "}," - has to be without ","
sed -i '$ d' $i_filename

cat >> $i_filename <<f_create_path_json4_EOF
}
]
f_create_path_json4_EOF

log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

f_snap2road(){
log_info "$FUNCNAME $LINENO start $1 $2 $3"
local -r i_url="$1"
local -r i_idx_tmp="$2"

# l_response=$(curl "https://roads.googleapis.com/v1/snapToRoads?path=-35.27801,149.12958|-35.28032,149.12907|-35.28099,149.12929|-35.28144,149.12984|-35.28194,149.13003|-35.28282,149.12956|-35.28302,149.12881|-35.28473,149.12836&interpolate=true&key=AIz")

l_response=$(cat maps_response.txt)

# You need printf '%s\n' "$var" here because if you use printf '%s' "$var" 
# on a variable that doesn't end with a newline then the while loop will
# completely miss the last line of the variable.

l_lat_found_idx=0
l_pair_found_idx=0
l_idx=-1
i=0
printf '%s\n' "$l_response" | while IFS= read -r line
do
	i=$(( $i + 1 ))
	l_line=$(echo $line| sed -e 's/^[ \t]*//')
	case $l_line in 
		\"latitude\"*)
			l_lat_found_idx=$i
			l_lat=$(echo $l_line|cut -d' ' -f2|sed 's/,//')
		;;
		\"longitude\"*)
			if (( $(( $i - $l_lat_found_idx )) == 1 )); then
				l_lon=$(echo $l_line|cut -d' ' -f2|sed 's/,//')
				l_pair_found_idx=$i
				log_debug "$FUNCNAME $LINENO $l_lat found also $l_lon at line $i"
			else
				log_error "$FUNCNAME $LINENO Longitude value without Latitude found"
			fi
			l_lat_found_idx=0
		;;
		\"originalIndex\"*)
			if (( $(( $i - $l_pair_found_idx )) == 2 )); then
				l_idx=$(echo $l_line|cut -d' ' -f2|sed 's/,//')
				log_debug "$FUNCNAME $LINENO $l_lat $l_lon found google index $l_idx at line $i" 
			else
				log_error "$FUNCNAME $LINENO Index value without Lon/Lat pair found at line $i"
			fi
		;;
		\"placeId\"*)
			if (( $(( $i - $l_pair_found_idx )) < 4 )); then
				l_placeId=$(echo $l_line|cut -d' ' -f2|sed 's/\"//g')
				log_info "$FUNCNAME $LINENO corresponding PlaceID found $l_placeId at line $i"
				log_info "$FUNCNAME $LINENO record complete $l_lat $l_lon $l_idx $l_placeId"
				if [[ "$l_idx" != "-1" ]]; then
					l_time=$(sqlite3 $g_database "select unixtime from google_idx_tmp where google_idx=$l_idx;")
					log_info "$FUNCNAME $LINENO found unixtime $l_time for index $l_idx"
					sql_string="snap_lon=$l_lon, snap_lat=$l_lat, placeId=$l_placeId"
					eval "sqlite3 $i_db \"update google_idx_tmp	set $sql_string where unixtime=$l_time;\""
					l_idx=-1
				fi
			else
				log_error "$FUNCNAME $LINENO placeId value without Lon/Lat pair found at line $i"
			fi
		;;
	esac
	echo "$i: $l_line"
done

log_info "$FUNCNAME $LINENO end"
}

f_snap2road_json(){
log_info "$FUNCNAME $LINENO start $1 $2 $3"
local -r -i l_runtime=$SECONDS
# function to use GPS positions and then retrieve 
# new coordinates from google using snap to road
# these new coordinates will be written in new table

# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: filename with markers for google maps

local -r i_db="$1"
local -r i_table="$2"
local -r i_filename="$3"

l_url="https://roads.googleapis.com/v1/snapToRoads?path="

l_datapoints=$(sqlite3 $i_db "select unixtime from $i_table where snap_flag=0 order by unixtime;")

i_last_datapoint=0
i=0
for l_datapoint in $l_datapoints
do 
	if [[ $i != 0 ]]; then
		l_url_coord="$l_url_coord""|"
	fi
	l_lat=$(f_get_single_value $i_db $i_table latitude_n $l_datapoint|awk '{printf "%3.5f", $0}')
	l_lon=$(f_get_single_value $i_db $i_table longitude_e $l_datapoint|awk '{printf "%3.5f", $0}')
	l_url_coord="$l_url_coord""$l_lat"",""$l_lon"
	sql_string="$l_datapoint,'$g_object',$i,NULL,NULL,NULL"
	eval "sqlite3 $i_db \"insert or replace into google_idx_tmp	values($sql_string);\""
	if [[ "$i" = "99" ]]; then
		f_snap2road $l_url_coord google_idx_tmp
		i=0
		# need to save last point of package - as starting point for next package
		i_last_datapoint=$l_datapoint
		log_info "$FUNCNAME $LINENO first 100 processed, last dp is $l_datapoint"
		exit
	fi
	i=$(( $i + 1 ))
done
# if [[ "$i_last_datapoint" != "0" ]]; then


log_info "$FUNCNAME $LINENO snap2roads string is $l_url_coord"
f_snap2road $l_url_coord

log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function f_create_DB
{
# function to create empty specified DB - if not already existing DB
# input parameter 1: sqlite3 database file
local -r i_db="$1"

log_info "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

if [[ "$i_db" = "" ]]; then
	log_error "$FUNCNAME $LINENO DB not specified"
	return 1
fi

if [[ ! -e "$i_db" ]]; then
	# object - text description for object to be tracked
    sqlite3 $i_db "CREATE TABLE IF NOT EXISTS position (unixtime INTEGER PRIMARY KEY, object TEXT, longitude_e REAL, latitude_n REAL, elevation REAL, gpstime TEXT, distance REAL, snap_flag INT);"
	sqlite3 $i_db "CREATE TABLE IF NOT EXISTS google_idx_tmp (unixtime INTEGER PRIMARY KEY, object TEXT, google_idx INT, snap_long REAL, snap_lat REAL, placeId TEXT);"
	log_info "$FUNCNAME $LINENO DB $i_db initialized and table \"position\" created"
else
	log_info "$FUNCNAME $LINENO DB $i_db already exists"
	sqlite3 $i_db "CREATE TABLE IF NOT EXISTS position (unixtime INTEGER PRIMARY KEY, object TEXT, longitude_e REAL, latitude_n REAL, elevation REAL, gpstime TEXT, distance REAL,snap_flag INT);"
	sqlite3 $i_db "CREATE TABLE IF NOT EXISTS google_idx_tmp (unixtime INTEGER PRIMARY KEY, object TEXT, google_idx INT, snap_long REAL, snap_lat REAL, placeId TEXT);"
fi

log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
return 0
}

function f_get_position(){
log_info "$FUNCNAME $LINENO start $1 $2 $3"
local -r -i l_runtime=$SECONDS
# function to retrieve position from GPS device
# check sanity of retrieved values
# Google Maps min/max values
# Latitude: -85 to +85 (actually -85.05115 for some reason)
# Longitude: -180 to +180
# input parameter 1: sqlite3 database file
# input parameter 2: tablename

local -r i_db="$1"
local -r i_table="$2"

local l_unixtime=$(date +%s)

if [[ "$i_db" = "" ]]; then
	log_error "$FUNCNAME $LINENO no database specified"
	return 128
else
	log_debug "$FUNCNAME $LINENO using DB $i_db"
fi

if [[ "$i_table" = "" ]]; then
	log_error "$FUNCNAME $LINENO no DB table specified"
	return 128
else
	log_debug "$FUNCNAME $LINENO using DB table $i_table"
fi


# check if bluetooth is active - connection to GPS
# i=0
# l_bt_active=false
# while [[ "$l_bt_active" = "false" && $i < 5 ]]; do
	# i=$(( $i + 1 ))
	# l_bt_status=$(sudo systemctl status bluetooth|grep "Active:"|awk '{print $2}')
	# if [[ "$l_bt_status" = "active" ]]; then
		# log_info "$FUNCNAME $LINENO Bluetooth active"
		# l_bt_active=true
	# else
		# log_error "$FUNCNAME $LINENO iteration $i Bluetooth not active, waiting 5 sec"
		# sleep 5
	# fi
# done

# get GPS data and try 5 times to get valid position
local l_valid_data=false
local i=0
while [[ "$l_valid_data" = "false" && $i < 5 ]]; do
	l_valid_data=true
	i=$(( $i + 1 ))
	local gpsdata=$(gpspipe -w -n 10|grep -m 1 TPV)

	local l_lat_new=$(echo "$gpsdata"|jq '.lat')
	case $(f_checkFloat $l_lat_new) in
		"OK" )
			if [[ $(echo "$l_lat_new >= -85 && $l_lat_new <= 85"|bc) == 1 ]]; then
				log_info "$FUNCNAME $LINENO loop $i l_lat_new $l_lat_new is valid"
			else
				log_error "$FUNCNAME $LINENO l_lat_new \"$l_lat_new\" is invalid"
				l_valid_data=false
			fi
			;;
		* )
			log_error "$FUNCNAME $LINENO l_lat_new \"$l_lat_new\" is invalid"
			l_valid_data=false
			;;
	esac

	local l_lon_new=$(echo "$gpsdata"|jq '.lon')
	case $(f_checkFloat $l_lon_new) in
		"OK" )
			if [[ $(echo "$l_lon_new >= -180 && $l_lon_new <= 180"|bc) == 1 ]]; then
				log_info "$FUNCNAME $LINENO loop $i l_lon_new $l_lon_new is valid"
			else
				log_error "$FUNCNAME $LINENO loop $i l_lon_new \"$l_lon_new\" is invalid"
				l_valid_data=false
			fi
			;;
		* )
			log_error "$FUNCNAME $LINENO l_lon_new \"$l_lon_new\" is invalid"
			l_valid_data=false
			;;
	esac
	
	local l_elevation_new=$(echo "$gpsdata"|jq '.alt')
	log_debug "$FUNCNAME $LINENO loop $i value l_elevation \"$l_elevation\" "

	local l_gpstime_new=$(echo "$gpsdata"|jq '.time')
	log_debug "$FUNCNAME $LINENO loop $i $l_lat_new $l_lon_new $l_elevation $l_gpstime_new"
done

l_datapoints_count=$(sqlite3 $i_db "select count(*) from $i_table;")
if [[ "$l_datapoints_count" != "0" ]]; then
	local l_last_entry=$(sqlite3 $i_db "select max(unixtime) from $i_table;")
	local l_lat=$(f_get_single_value $i_db $i_table latitude_n $l_last_entry)
	local l_lon=$(f_get_single_value $i_db $i_table longitude_e $l_last_entry)
	log_debug "$FUNCNAME $LINENO $l_last_entry $l_lat $l_lon"
	local l_distance=$(f_distance $l_lat $l_lon $l_lat_new $l_lon_new)
	log_info "$FUNCNAME $LINENO position $l_lat_new $l_lon_new at l_elevation_new $l_elevation_new with time $l_gpstime_new distance $l_distance"
	log_debug "$FUNCNAME $LINENO raw data $gpsdata"
else
	l_distance=0
fi


# if moved more than 100m, write values into DB 
# also long & lat have to be valid values
# otherwise not
if [[ $(echo "$l_distance > 0.1"|bc) -eq 1 && "$l_valid_data" = "true" ]]; then
	sql_string="$l_unixtime,'$g_object',$l_lon_new,$l_lat_new,$l_elevation_new,'$l_gpstime_new','$l_distance',0"
	log_always "$FUNCNAME $LINENO distance $l_distance sqlite3 $i_db insert or replace into $i_table values $sql_string"
	eval "sqlite3 $i_db \"insert or replace into $i_table values($sql_string);\""
	f_create_path_json $i_db $i_table $g_path_json
	# f_create_markers_json  $i_db $i_table $g_markers_json
	# f_snap2road_json $i_db $i_table 
	f_do_transfer
else
	log_always "$FUNCNAME $LINENO pos $l_lat_new $l_lon_new - distance $l_distance <= 0.1 km - data validity is $l_valid_data"
	f_create_path_json $i_db $i_table $g_path_json
	# f_create_markers_json  $i_db $i_table $g_markers_json
	# f_snap2road_json $i_db $i_table 
	f_do_transfer
fi

# initialize table with first position - if empty
l_datapoints_count=$(sqlite3 $i_db "select count(*) from $i_table;")
if [[ $l_datapoints_count = 0 && "$l_valid_data" = "true" ]]; then
	sql_string="$l_unixtime,'$g_object',$l_lon_new,$l_lat_new,$l_elevation_new,'$l_gpstime_new','$l_distance',0"
	log_always "$FUNCNAME $LINENO init pos $l_lat_new $l_lon_new sqlite3 $i_db insert or replace into $i_table values $sql_string"
	eval "sqlite3 $i_db \"insert or replace into $i_table values($sql_string);\""
	f_create_path_json $i_db $i_table $g_path_json
	# f_create_markers_json  $i_db $i_table $g_markers_json
	# f_snap2road_json $i_db $i_table 
	f_do_transfer
fi

log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function f_acos(){
local -r i_value="$1"
local -r c_pi=3.141592653589793
echo $(echo "$c_pi / 2 - a($i_value / sqrt(1 - $i_value * $i_value))"|bc -l)
}

function f_distance(){
log_info_silent "$FUNCNAME $LINENO start $1 $2 $3 $4"
local -r -i l_runtime=$SECONDS
# function to calculate distance in [km] between 2 lat/long coordinates
# found here: https://ethertubes.com/bash-snippet-calculating-the-distance-between-2-coordinates/
# input parameter 1: lat1 [°]
# input parameter 2: long1 [°]
# input parameter 3: lat2 [°]
# input parameter 4: long2 [°]
# output on stdout: distance in [km]
local -r c_deg2rad=0.01745329251994329577
local -r c_rad2deg=57.29577951308232087680

local -r i_lat1=$(echo "$1 * $c_deg2rad"|bc -l)
local -r i_long1=$(echo "$2 * $c_deg2rad"|bc -l)
local -r i_lat2=$(echo "$3 * $c_deg2rad"|bc -l)
local -r i_long2=$(echo "$4 * $c_deg2rad"|bc -l)
local -r i_lat_delta=$(echo "($3 - $1) * $c_deg2rad"|bc -l)
local -r i_long_delta=$(echo "($4 - $2) * $c_deg2rad"|bc -l)


log_debug_silent "$FUNCNAME $LINENO lat/long [rad] lat/long [rad] $i_lat1 $i_long1 $i_lat2 $i_long2"
log_debug_silent "$FUNCNAME $LINENO d-long/d-lat $i_long_delta $i_lat_delta"
l_distance=$(echo "s($i_lat1) * s($i_lat2) + c($i_lat1) * c($i_lat2) * c($i_long_delta)"|bc -l)
log_debug_silent "$FUNCNAME $LINENO distance1 $l_distance"

l_distance=$(f_acos $l_distance)
log_debug_silent "$FUNCNAME $LINENO distance2 $l_distance"

l_distance=$(echo "$l_distance * $c_rad2deg * 60 * 1.85200"|bc -l|awk '{printf "%2.3f", $0}')
log_debug_silent "$FUNCNAME $LINENO distance3 $l_distance"
echo $l_distance

log_info_silent "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function f_check_internet()
{
log_info "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

# check if internet connection is available or not by pinging google.com
# returns 0 if internet ok
# returns 1 if no internet connection
wget -q --tries=1 --timeout=10 --delete-after http://google.com
if [[ $? -eq 0 ]]; then
        wget $g_subdomain --tries=1 --timeout=10 --delete-after 2> speedtest.out
        speed=$(grep saved speedtest.out |cut -d' ' -f3|cut -d'(' -f2)
        speedunit="$(grep saved speedtest.out |cut -d' ' -f4|cut -d')' -f1)"
		case "$speedunit" in
			"B/s" )
				internet=offline
				log_error "$FUNCNAME $LINENO case Internet slooooow $speed $speedunit - set script to offline" 
				return 1
				;;
			"KB/s" )
				if [ $(echo "$speed > 50" |bc) -eq 0 ]; then
					internet=offline
					log_error "$FUNCNAME $LINENO case Internet slooooow $speed $speedunit - set script to offline"
					return 1
				else
					internet=online
					log_info "$FUNCNAME $LINENO case Internet online and >50KB/s, i.e. $speed $speedunit"
					return 0
				fi
				;;
			"MB/s" )
				internet=online
				log_info "$FUNCNAME $LINENO case Internet online and >50KB/s, i.e. $speed $speedunit"
				return 0
				;;
			* )
				log_error "$FUNCNAME $LINENO unexpected result, i.e. $speed $speedunit, assuming internet down"
				internet=offline
				return 1
				;;
		esac
else
        log_error "$FUNCNAME $LINENO did not reach Google, internet down"
        internet=offline
		return 1
fi
}

function f_do_transfer()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
# make sure that scp is working and that on source / destination maschine 
# the mechanism for logon via certificate is working
# cd ~/.ssh
# files: authorized_keys id_rsa id_rsa.pub known_hosts

# this is necessary, so that programs like wget use english for thier messages
# otherwise, grep "saved" will not succeed
export LANG=en_EN.UTF8

# transfer files if internet is online
if f_check_internet; then
	rsync -avzq data/* tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/$g_subdomain/data
fi
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_transfer_daily()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
# make sure that scp is working and that on source / destination maschine 
# the mechanism for logon via certificate is working
# cd ~/.ssh
# files: authorized_keys id_rsa id_rsa.pub known_hosts

# this is necessary, so that programs like wget use english for their messages
# otherwise, grep "saved" will not succeed
export LANG=en_EN.UTF8

# determine internet connection & speed
wget -q --tries=1 --timeout=10 --delete-after http://google.com
if [[ $? -eq 0 ]]; then
        wget http://$subdomain/img/dummy --tries=1 --timeout=10 --delete-after 2> speedtest.out
        speed=$(grep saved speedtest.out |cut -d' ' -f3|cut -d'(' -f2)
        speedunit="$(grep saved speedtest.out |cut -d' ' -f4|cut -d')' -f1)"
        if [ "$speedunit" = "B/s" ]; then
                internet=offline
                log_error "$FUNCNAME $LINENO Internet slooooow $speed $speedunit - set script to offline"
        fi
        if [ "$speedunit" = "KB/s" ]; then
                if [ $(echo "$speed > 50" |bc) -eq 0 ]; then
                        internet=offline
                        log_error "$FUNCNAME $LINENO Internet slooooow $speed $speedunit - set script to offline"
                else
                        internet=online
                        log_info "$FUNCNAME $LINENO Internet online and >50KB/s, that is $speed $speedunit"
                fi
        fi
else
        log_error "$FUNCNAME $LINENO did not reach Google, internet down"
        internet=offline
fi

# transfer files if internet is online
if [ "$internet" = "online" ]; then
    scp tempday?.png tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/$subdomain/img
    log_info "$FUNCNAME $LINENO graphics for daily statistics tempday+ transferred to homepage"

    scp temp7d?.png tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/$subdomain/img
    log_info "$FUNCNAME $LINENO graphics for past 7 weeks transferred to homepage"

    scp tempmo?.png tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/$subdomain/img
    log_info "$FUNCNAME $LINENO graphics for past 7 months transferred to homepage"
fi
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}


function f_do_backup()
{
# function to create backup of specified diretory + transfer to webserver
# input parameter 1: directory to be "tar"ed + transferred; e.g. "/testtemp"
# input parameter 2: OS user on destination side; prerequisite: authorized key mechanism has to be working
local -r i_dir="$1"
local -r i_dest_user="$2"
local -r i_suffix="$3"

log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

# this function should be called daily to transfer a backup 
# resulting backup will be handled by logrotation daily at 00:05,
# so make sure that the backup exists at that time
# check crontab entries of root for logrotation 
# 
# $pool_env is set in init_vars; starts with / e.g. /production
local l_dest_basedir=/private-backup/raspi-backups/$(hostname)$(pwd)

local l_filename_tar="$(echo $i_dir|sed 's/\///')""_""$i_suffix".tgz
log_info "$FUNCNAME $LINENO dir $i_dir to tar file $l_filename_tar and dest dir $l_dest_basedir"
tar -czf ~/$l_filename_tar $i_dir
l_rc=$?

if [[ "$l_rc" != "0" ]]; then
	tail -n 100 $g_logfile >"$g_logfile"_temp
	log_error "$FUNCNAME $LINENO command tar -czf ~/$l_filename_tar $i_dir returned $l_rc"|mailx -s "Error during tar creation for Backup" -a "$g_logfile"_temp $g_mail_rcpt
	rm "$g_logfile"_temp
else
	log_info "$FUNCNAME $LINENO Backup tar archive created"
fi
ssh $i_dest_user@h2144881.stratoserver.net "mkdir -p $l_dest_basedir"
rsync -avz ~/$l_filename_tar $i_dest_user@h2144881.stratoserver.net:$l_dest_basedir >/dev/null 2>>$g_logfile
l_rc=$?
if [[ "$l_rc" != "0" ]]; then
	tail -n 100 $g_logfile >"$g_logfile"_temp
	log_error "$FUNCNAME $LINENO command \"rsync -avz ~/$l_filename_tar $i_dest_user@h2144881.stratoserver.net:$l_dest_basedir\" return code $l_rc"|mailx -s "Error during file transfer for Backup" -a "$g_logfile"_temp $g_mail_rcpt
	rm "$g_logfile"_temp
else
	log_info "$FUNCNAME $LINENO Backup tar archive transferred"
fi
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}
