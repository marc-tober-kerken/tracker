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

local l_inifile="$l_own_name_wo"".ini"
log_info "$FUNCNAME $LINENO using ini file $l_inifile for initialization"

if [[ ! -d "$l_own_path/data" ]]; then
	log_info "$FUNCNAME $LINENO create data directory $l_own_path/data"
	mkdir -p "$l_own_path/data"
fi

# 1=only fatal; 2=only fatal+error; 3=...+warning; 4=...+info; 5=...+debug
g_log_level=$(grep "^g_log_level" "$l_inifile"|cut -d= -f2)
echo Loglevel $g_log_level from $l_inifile
log_debug "$FUNCNAME $LINENO initialized g_log_level with $g_log_level"

declare -r -g g_database=$(grep "^g_database" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_database with $g_database"

declare -r -g g_table=$(grep "^g_table" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_table with $g_table"

declare -r -g g_subdomain=$(grep "^g_subdomain" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_subdomain with $g_subdomain"

declare -r -g g_mail_rcpt=$(grep "^g_mail_rcpt" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_mail_rcpt with \"$g_mail_rcpt\""

declare -r -g g_vclient_cmd=$(grep "^g_vclient_cmd" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_vclient_cmd with \"$g_vclient_cmd\""

declare -r -g g_ip_livingroom=$(grep "^g_ip_livingroom" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_ip_livingroom with \"$g_ip_livingroom\""

declare -r -g g_wintermode=$(grep "^g_wintermode" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_wintermode with \"$g_wintermode\""

declare -r -g g_livingroom_target=$(grep "^g_livingroom_target" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_livingroom_target with \"$g_livingroom_target\""

declare -r -g g_livingroom_reduced=$(grep "^g_livingroom_reduced" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_livingroom_reduced with \"$g_livingroom_reduced\""

declare -r -g g_hysteresis=$(grep "^g_hysteresis" "$l_inifile"|cut -d= -f2)
log_debug "$FUNCNAME $LINENO initialized g_hysteresis with \"$g_hysteresis\""


# ATTENTION: this is not implemented yet as ini file parameter; need to test this first
declare -r -g -a g_livingroom_from=( [1]='05:00' [2]='09:30' [3]='09:30' [4]='05:00' [5]='05:00' [6]='05:00' [7]='05:00' )
declare -r -g -a   g_livingroom_to=( [1]='19:00' [2]='19:00' [3]='19:00' [4]='19:00' [5]='20:00' [6]='20:00' [7]='19:00' )
}

function init_vars()
{
# This script uses the following rrdtool database:
# rrdtool create temp_pool.rrd --step 900 --start "20140101 00:00" \
# DS:water:GAUGE:1200:-40:50 \
# DS:air:GAUGE:1200:-40:50 \
# DS:roof:GAUGE:1200:-40:80 \
# DS:flow:GAUGE:1200:-40:50 \
# DS:return:GAUGE:1200:-40:50 \
# DS:delta:COMPUTE:return,flow,- \
# DS:pump_flag:GAUGE:1200:0:1 \
# DS:heat_flag:GAUGE:1200:0:1 \
# DS:device:GAUGE:1200:0:90 \
# RRA:AVERAGE:0.5:1:103680 \
# RRA:MIN:0.5:96:3650 \
# RRA:MAX:0.5:96:3650 \
# RRA:AVERAGE:0.5:96:3650

# determine own path
_scriptlocal="$(readlink -f ${BASH_SOURCE[0]})"
_base="$(dirname $_scriptlocal)"

# declare environment (Test or Production)
# this variable will be part of the used paths
# expample pool_env=production; used path in script /production/...
	pool_env="$_base"
	send_cmd="sudo /home/pi/raspberry-remote/send"

	case "$pool_env" in
		/production )
			subdomain=pool.tober-kerken.de
			# 1=only fatal; 2=only fatal+error; 3=...+warning; 4=...+info; 5=...+debug
			echo "Environment: $pool_env" ;;
		/testtemp )
			subdomain=test.tober-kerken.de

			echo "Environment: $pool_env"  ;;
	esac
	
# create timestamp rounded to 15min interval
	set $(date "+%Y %m %d %H %M")
	# only for test & debug: set desired date manually
	# set $(date -d "20140826 00:00" +"%Y %m %d %H %M")
	m=$((100+15*(${5#0}/15)))
	timestamp_rounded="$1$2$3 $4:${m#1}"
	timestamp_rounded_unix=$(date --date "$1$2$3 $4:${m#1}" +%s)
	timestamp_real=$(date "+%Y%m%d %H:%M")
   	timestamp_real_unix=$(date +%s)

# define sensors

bee_zone1_sens=/sys/bus/w1/devices/28-000005ce8588/w1_slave
bee_zone2_sens=/sys/bus/w1/devices/28-000005cebfa7/w1_slave
bee_zone3_sens=/sys/bus/w1/devices/28-000005ce05e0/w1_slave
bee_air_sens=/sys/bus/w1/devices/28-000005ceaf15/w1_slave
air_sens=/sys/bus/w1/devices/28-000005d2c10c/w1_slave
water_sens=/sys/bus/w1/devices/28-000005d2c38e/w1_slave
return_sens=/sys/bus/w1/devices/28-000005d3c0f8/w1_slave
flow_sens=/sys/bus/w1/devices/28-000005d3010b/w1_slave
roof_sens=/sys/bus/w1/devices/28-000005d2ebb5/w1_slave
device_sens=/sys/class/thermal/thermal_zone0/temp

# define logfile
	logfile=$pool_env/logfile.log
	g_logfile=$pool_env/logfile.log
    redo_logfile=$pool_env/redolog.sh
	redo_logfile_sql=$pool_env/redolog_sql.sh

# define database
    database=$pool_env/temp_pool.rrd

# define database_sql
    database_sql=$pool_env/temp_pool.sqlite
	
# check & define timer; only quarter hours!
	pump_from="10:00"
	pump_to="18:30"

# define address of electrical outlets
	pump_power="10001 2"
	heat_power="10001 3"

# minimum temperature difference between roof and water to turn on heating
# checked and re-calculated every 15min
	temp_diff=5

# define pump flow rate in liter / hour	
	pump_flowrate=3000

# define winter mode on = 1 or off = 0
# no switches of pump or heat occur any more in winter mode
	winter_mode_pump=0
	winter_mode_heat=0
	
# define heat_priority
# if this is 1: whenever heating seems to be appropriate, enable pump + heating even if outside of pump timer
# if this is 0: only heat when appropriate during pump timer hours
	heat_priority=1

# displaypi IP adress
	displaypi_ip=192.168.24.45
	

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

log_warning(){
  if [[ $g_log_level -ge 3 ]]
  then
    do_log WARN $1
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

f_do_housekeeping(){
# wrapper function to call 
# - DB reorg: delete unneeded values
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

# daily tasks
if [[ "$(date -d @$i_unixtime +"%H:%M")" = "00:00" ]]; then
	log_info "$FUNCNAME $LINENO perform daily housekeeping"
	f_do_backup $_base tober-kerken D$(date -d @$i_unixtime +%u)
else
	log_info "$FUNCNAME $LINENO current time $(date -d @$i_unixtime +"%H:%M") not 00:00 - no daily housekeeping"
fi

# monthly tasks
if [[ "$(date -d @$i_unixtime +"%d")" = "01" ]] && [[ "$(date -d @$i_unixtime +"%H:%M")" = "01:00" ]]; then
	log_info "$FUNCNAME $LINENO perform monthly housekeeping"
	f_do_backup $_base tober-kerken M$(date -d @$i_unixtime +%m)
	# 63936000 = 740 days
	local l_time_limit=$(( $i_unixtime - 63936000 ))
	local l_old_records=$(sqlite3 $i_db "select count(1) from $i_table where unixtime<=$l_time_limit;")
	log_info "$FUNCNAME $LINENO removing data older than $(date -d @$l_time_limit) - $l_old_records records found"
	sqlite3 $i_db "delete from $i_table where unixtime<=$l_time_limit;"
	sqlite3 $i_db "vacuum;"
	log_info "$FUNCNAME $LINENO removed $l_old_records records. DB reorg performed."
else
	log_info "$FUNCNAME $LINENO current time $(date -d @$i_unixtime) - no monthly housekeeping"
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

f_get_avg_day_value(){
# function to retrieve a value from the database
# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: field name
# input parameter 4: unixepoch time for desired day; function will generate appropriate 00:00-23:59 for same day
local -r i_db="$1"
local -r i_table="$2"
local -r i_field="$3"
local -r i_unixtime="$4"

# output:
# value of field for specified unixepoch time.
#
# return code:
# 0: success: some data found in DB for desired time
# 1: no data found in DB

local l_day_hlp=$(date -d @$i_unixtime "+%Y%m%d 00:00")
local l_day_start=$(date -d "$l_day_hlp" +%s)
local l_day_end=$(( $l_day_start + 86400 ))

local l_datacount=$(sqlite3 $i_db "select count(1) from $i_table where unixtime>=$l_day_start and unixtime<$l_day_end;")
local l_return=$(sqlite3 $i_db "select round(avg($i_field),1) from $i_table where unixtime>=$l_day_start and unixtime<$l_day_end;")
echo $l_return
if [[ "$l_datacount" = "0" ]]; then
	# no data selected
	return 1
else
	# data found in DB
	return 0
fi
}

f_get_min_day_value(){
# function to retrieve a value from the database
# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: field name
# input parameter 4: unixepoch time for desired day; function will generate appropriate 00:00-23:59 for same day
local -r i_db="$1"
local -r i_table="$2"
local -r i_field="$3"
local -r i_unixtime="$4"

# output:
# value of field for specified unixepoch time.
#
# return code:
# 0: success: some data found in DB for desired time
# 1: no data found in DB

local l_day_hlp=$(date -d @$i_unixtime "+%Y%m%d 00:00")
local l_day_start=$(date -d "$l_day_hlp" +%s)
local l_day_end=$(( $l_day_start + 86400 ))

local l_datacount=$(sqlite3 $i_db "select count(1) from $i_table where unixtime>=$l_day_start and unixtime<$l_day_end;")
local l_return=$(sqlite3 $i_db "select round(min($i_field),1) from $i_table where unixtime>=$l_day_start and unixtime<$l_day_end;")
echo $l_return
if [[ "$l_datacount" = "0" ]]; then
	# no data selected
	return 1
else
	# data found in DB
	return 0
fi
}

f_get_max_day_value(){
# function to retrieve a value from the database
# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: field name
# input parameter 4: unixepoch time for desired day; function will generate appropriate 00:00-23:59 for same day
local -r i_db="$1"
local -r i_table="$2"
local -r i_field="$3"
local -r i_unixtime="$4"

# output:
# value of field for specified unixepoch time.
#
# return code:
# 0: success: some data found in DB for desired time
# 1: no data found in DB

local l_day_hlp=$(date -d @$i_unixtime "+%Y%m%d 00:00")
local l_day_start=$(date -d "$l_day_hlp" +%s)
local l_day_end=$(( $l_day_start + 86400 ))

local l_datacount=$(sqlite3 $i_db "select count(1) from $i_table where unixtime>=$l_day_start and unixtime<$l_day_end;")
local l_return=$(sqlite3 $i_db "select round(max($i_field),1) from $i_table where unixtime>=$l_day_start and unixtime<$l_day_end;")
echo $l_return
if [[ "$l_datacount" = "0" ]]; then
	# no data selected
	return 1
else
	# data found in DB
	return 0
fi
}

f_get_delta_hour_value(){
# function to retrieve a value from the database
# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: field name
# input parameter 4: unixepoch time for desired hour; function will generate appropriate 00:00-00:59 for hour
local -r i_db="$1"
local -r i_table="$2"
local -r i_field="$3"
local -r i_unixtime="$4"

# output:
# difference of max value and min value of that hour
# used e.g. for runtime in [s] in that hour
#
# return code:
# 0: success: some data found in DB for desired time
# 1: no data found in DB

local l_hour_hlp=$(date -d @$i_unixtime "+%Y%m%d %H:00")
local l_hour_start=$(date -d "$l_hour_hlp" +%s)
local l_hour_end=$(( $l_hour_start + 3600 ))

local l_datacount=$(sqlite3 $i_db "select count(1) from $i_table where unixtime>=$l_hour_start and unixtime<$l_hour_end;")

local l_min_value=$(sqlite3 $i_db "select min($i_field) from $i_table where unixtime>=$l_hour_start and unixtime<$l_hour_end;")
local l_max_value=$(sqlite3 $i_db "select max($i_field) from $i_table where unixtime>=$l_hour_start and unixtime<$l_hour_end;")

local l_return=$(( $l_max_value - $l_min_value ))

log_debug_silent "$FUNCNAME $LINENO datapoints $l_datacount with min $l_min_value and max $l_max_value - delta is $l_return"

if [ $(echo "$l_return > 3600" |bc) -eq 0 ]; then
	echo $l_return
	log_debug_silent "$FUNCNAME $LINENO $l_return is normal"
else
	echo 3600
	log_debug_silent "$FUNCNAME $LINENO $l_return larger than 3600"
fi

if [[ "$l_datacount" = "0" ]]; then
	# no data selected
	return 1
else
	# data found in DB
	return 0
fi
}

f_get_delta_day_value(){
# function to retrieve a value from the database
# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: field name
# input parameter 4: unixepoch time for desired hour; function will generate appropriate 00:00-00:59 for hour
local -r i_db="$1"
local -r i_table="$2"
local -r i_field="$3"
local -r i_unixtime="$4"

# output:
# difference of max value and min value of that hour
# used e.g. for runtime in [s] in that hour
#
# return code:
# 0: success: some data found in DB for desired time
# 1: no data found in DB

local l_day_hlp=$(date -d @$i_unixtime "+%Y%m%d %H:00")
local l_day_start=$(date -d "$l_day_hlp" +%s)
local l_day_end=$(( $l_day_start + 86400 ))

local l_datacount=$(sqlite3 $i_db "select count(1) from $i_table where unixtime>=$l_day_start and unixtime<$l_day_end;")

local l_min_value=$(sqlite3 $i_db "select min($i_field) from $i_table where unixtime>=$l_day_start and unixtime<$l_day_end;")
local l_max_value=$(sqlite3 $i_db "select max($i_field) from $i_table where unixtime>=$l_day_start and unixtime<$l_day_end;")

# Attention, only possible for integer values... i_field must have type int in db
local l_return=$(( $l_max_value - $l_min_value ))

log_debug_silent "$FUNCNAME $LINENO $(date -d @$i_unixtime) datapoints $l_datacount with min $l_min_value and max $l_max_value - delta is $l_return"

echo $l_return

# if [ $(echo "$l_return > 3600" |bc) -eq 0 ]; then
	# echo $l_return
	# log_debug_silent "$FUNCNAME $LINENO $l_return is normal"
# else
	# echo 3600
	# log_debug_silent "$FUNCNAME $LINENO $l_return larger than 3600"
# fi

if [[ "$l_datacount" = "0" ]]; then
	# no data selected
	return 1
else
	# data found in DB
	return 0
fi
}


f_get_avg_hour_value(){
# function to retrieve a value from the database
# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: field name
# input parameter 4: unixepoch time for desired hour; function will generate appropriate 00:00-00:59 for hour
local -r i_db="$1"
local -r i_table="$2"
local -r i_field="$3"
local -r i_unixtime="$4"

# output:
# value of field for specified unixepoch time.
#
# return code:
# 0: success: some data found in DB for desired time
# 1: no data found in DB

local l_hour_hlp=$(date -d @$i_unixtime "+%Y%m%d %H:00")
local l_hour_start=$(date -d "$l_hour_hlp" +%s)
local l_hour_end=$(( $l_hour_start + 3600 ))

local l_datacount=$(sqlite3 $i_db "select count(1) from $i_table where unixtime>=$l_hour_start and unixtime<$l_hour_end;")
local l_return=$(sqlite3 $i_db "select round(avg($i_field),1) from $i_table where unixtime>=$l_hour_start and unixtime<$l_hour_end;")
echo $l_return
if [[ "$l_datacount" = "0" ]]; then
	# no data selected
	return 1
else
	# data found in DB
	return 0
fi
}

f_get_avg_2h_value(){
# function to retrieve a value from the database
# input parameter 1: sqlite3 database with full path
# input parameter 2: tablename
# input parameter 3: field name
# input parameter 4: unixepoch time for desired hour; function will generate appropriate 00:00-00:59 for hour
local -r i_db="$1"
local -r i_table="$2"
local -r i_field="$3"
local -r i_unixtime="$4"

# output:
# value of field for specified unixepoch time.
#
# return code:
# 0: success: some data found in DB for desired time
# 1: no data found in DB

local l_hour_hlp=$(date -d @$i_unixtime "+%Y%m%d %H:00")
local l_hour_start=$(date -d "$l_hour_hlp" +%s)
local l_hour_end=$(( $l_hour_start + 7200 ))

local l_datacount=$(sqlite3 $i_db "select count(1) from $i_table where unixtime>=$l_hour_start and unixtime<$l_hour_end;")
local l_return=$(sqlite3 $i_db "select round(avg($i_field),1) from $i_table where unixtime>=$l_hour_start and unixtime<$l_hour_end;")
echo $l_return
if [[ "$l_datacount" = "0" ]]; then
	# no data selected
	return 1
else
	# data found in DB
	return 0
fi
}

f_create_opt_month1(){
# function to create option file for google charts
#
# input parameter 1: filename with full path
local -r l_filename="$1"
local -r l_title="$2"

cat > $l_filename <<f_create_opt_month1_EOF
{
	"width":900,
	"height":525,
	"backgroundColor": {
		"stroke": "#ddd",
		"strokeOpacity":1
	},
	"chart": {
		"title": "Temperaturen Bienenstock",
		"subtitle": "in Grad Celsius",
		"style": {
			"background": {
				"padding": 20,
				"stroke": {
					"width": 4
				}
			}
		}
	},
	"legend": {
		"position":"none"
	},
	"vAxis": {
		"title": "Temperatur [°C]",
		"format": "decimal"
	},
	"hAxis": {
		"title": "$l_title",
		"format": "d"
	},
	"axes": {
		"x": {
			"all": {
				"gridlines":"true",
				"ticks": {
					"pixelsPerTick": 16
				}
			}
		}
	}
}
f_create_opt_month1_EOF
}

f_create_html_temp(){
# function to create single html file, which includes specified temperatures
# this html will be included on final display on webserver
# input parameter 1: filename
# input parameter 2: temperature e.g. "-23.2"
# input parameter 3: temperature min e.g. "-23.2"
# input parameter 4: temperature avg e.g. "-23.2"
# input parameter 5: temperature max e.g. "-23.2"
# input parameter 6: temperature name e.g. "Zone 1 [°C]"

local -r i_filename="$1"
local -r i_temp_current="$2"
local -r i_temp_min="$3"
local -r i_temp_avg="$4"
local -r i_temp_max="$5"
local -r i_temp_name="$6"

local l_temp_part1=$(echo $i_temp_current|cut -d"." -f1)
local l_temp_part2=$(echo $i_temp_current|cut -d"." -f2)

cat > $i_filename <<f_create_html_temp_EOF
<head1>$i_temp_name</head1>
<minmax_left>$i_temp_min</minmax_left>
<minmax_mid>$i_temp_avg</minmax_mid>
<minmax_right>$i_temp_max</minmax_right>
<temp_no>
	<temperature>$l_temp_part1</temperature>
	<fraction>.$l_temp_part2</fraction>
	<cels>°</cels>
</temp_no>
f_create_html_temp_EOF
}

f_create_html_header(){
# function to create single html file, which includes current date
# this html will be included on final display on webserver
# input parameter 1: filename
# input parameter 2: Line1 Text

local -r i_filename="$1"
local -r i_text1="$2"

# <h2>11.06. 19:15</h2>
# <h3>Min/Avg/Max seit 00:00<h3>

cat > $i_filename <<f_create_html_header_EOF
<h2>$i_text1</h2>
<h3>Min/Avg/Max seit 00:00<h3>
f_create_html_header_EOF
}

f_create_opt_month2(){
# function to create option file for google charts
#
# input parameter 1: filename with full path
local -r l_filename="$1"
local -r l_title="$2"

cat > $l_filename <<f_create_opt_month2_EOF
{
			"title":"Temperaturen Bienenstock",
			"width": 900,
			"height": 525,
			"backgroundColor": {
				"stroke": "#ddd",
				"strokeOpacity": 1
			},
			"chartArea": {"width": "88%", "height": "70%"},
			"curveType": "function",
			"theme": "material",
			"legend": {
				"position": "top"
			},
			"vAxis": {
				"title": "Temperatur [°C]",
				"format": "decimal"
			},
			"hAxis": {
				"title": "$l_title",
				"gridlines": {
					"count": 31
				},
				"format": "d"
			}
		}
f_create_opt_month2_EOF
}

f_create_opt_week(){
# function to create option file for google charts
#
# input parameter 1: filename with full path
local -r l_filename="$1"
local -r l_title="$2"
local l_date="$3"

log_debug_silent "$FUNCNAME $LINENO got date $l_date"
l_ticks=""
l_date=$(( $l_date - 86400 ))
log_debug_silent "$FUNCNAME $LINENO calc date $(date -d @$l_date)"
for i in {0..7}
do
	i_date_calc=$(( $i * 86400 ))
	i_date=$(( $l_date + $i_date_calc ))
	log_debug_silent "$FUNCNAME $LINENO $(date -d @$i_date) $l_ticks"
	l_datestring_Y=$(date -d "@$i_date" +%Y)
	l_datestring_M=$(( $(date -d "@$i_date" +%-m) - 1 ))
	# javascript has Jan=0, Feb=1, ...
	l_datestring_D=$(date -d "@$i_date" +%-d)
	l_complete="Date($l_datestring_Y"",""$l_datestring_M"",""$l_datestring_D"
	l_ticks="$l_ticks""{\"v\":"\""$l_complete"",0,0,0)\",\"f\":\"$(date -d @$i_date +%A)\"},"
done

i_date_calc=$(( 8 * 86400 ))
i_date=$(( $l_date + $i_date_calc ))
l_datestring_Y=$(date -d "@$i_date" +%Y)
l_datestring_M=$(( $(date -d "@$i_date" +%-m) - 1 ))
# javascript has Jan=0, Feb=1, ...
l_datestring_D=$(date -d "@$i_date" +%-d)
l_complete="Date($l_datestring_Y"",""$l_datestring_M"",""$l_datestring_D"
l_ticks="$l_ticks""{\"v\":"\""$l_complete"",0,0,0)\",\"f\":\"$(date -d @$i_date +%A)\"}"


# {"v":"Date(2016,11,20,00,00,00)"}

log_debug_silent "$FUNCNAME $LINENO $(date -d @$l_date) $l_ticks"

cat > $l_filename <<f_create_opt_week_EOF
{
	"title":"Temperaturen und Brennerlaufzeiten",
	"width": 900,
	"height": 525,
	"backgroundColor": {
		"stroke": "#ddd",
		"strokeOpacity": 1
	},
	"chartArea": {"width": "88%", "height": "70%"},
	"curveType": "function",
	"theme": "material",
	"legend": {
		"position": "top"
	},
	"seriesType": "line",
	"series": {
		"2": {
			"type": "bars",
			"targetAxisIndex": "1",
			"color": "#D0D0D0"
		},
		"3": {
			"type": "bars",
			"targetAxisIndex": "1",
			"color": "#C0C0C0"
		}
	},
	"vAxes": {
		"0": {
			"title": "Temperatur [°C]",
			"format": "decimal"
		},
		"1": {
			"title": "Brennzeit [s] während 24h = 86400s",
			"format": "decimal",
			"ticks": [{"v":"21600","f":"6h"},{"v":"43200","f":"12h"},{"v":"64800","f":"18h"},{"v":"86400","f":"24h"}]
		}
	},
	"hAxis": {
		"title": "$l_title",
		"format": "H",
		"gridlines": {
			"count": -1,
			"units": {
				"days": {"format": ["MMM dd"]},
				"hours": {"format": ["HH:mm", "ha"]}
			}
		},
		"ticks": [$l_ticks]
	}
}
f_create_opt_week_EOF
}

f_create_opt_day(){
# function to create option file for google charts
#
# input parameter 1: filename with full path
local -r l_filename="$1"
local -r l_title="$2"
local -r l_date="$3"

l_datestring_Y=$(date -d "@$l_date" +%Y)
l_datestring_M=$(( $(date -d "@$l_date" +%-m) - 1 ))
# javascript has Jan=0, Feb=1, ...
l_datestring_D=$(date -d "@$l_date" +%-d)

l_complete="Date($l_datestring_Y"",""$l_datestring_M"",""$l_datestring_D"
l_ticks=""
for i in {0,2,4,6,8,10,12,14,16,18,20,22}
do
	l_ticks="$l_ticks""{\"v\":"\""$l_complete"",$i,0,0)\"},"
done

l_date_next_day=$(( $l_date + 86400 ))

h1=$(date -d "@$l_date")
h2=$(date -d "@$l_date_next_day")
log_debug_silent "$FUNCNAME $LINENO $l_date $h1 $l_date_next_day $h2"

l_datestring_Y=$(date -d "@$l_date_next_day" +%Y)
l_datestring_M=$(( $(date -d "@$l_date_next_day" +%-m) - 1 ))
# javascript has Jan=0, Feb=1, ...
l_datestring_D=$(date -d "@$l_date_next_day" +%-d)
l_complete="Date($l_datestring_Y"",""$l_datestring_M"",""$l_datestring_D"
l_ticks="$l_ticks""{\"v\":"\""$l_complete"",0,0,0)\"}"

# {"v":"Date(2016,11,20,00,00,00)"}

log_debug_silent "$FUNCNAME $LINENO $l_date $l_complete $l_ticks"

cat > $l_filename <<f_create_opt_day_EOF
{
	"title":"Temperaturen und Brennerlaufzeiten",
	"width": 900,
	"height": 525,
	"backgroundColor": {
		"stroke": "#ddd",
		"strokeOpacity": 1
	},
	"chartArea": {"width": "88%", "height": "70%"},
	"curveType": "function",
	"theme": "material",
	"legend": {
		"position": "top"
	},
	"seriesType": "line",
	"series": {
		"4": {
			"type": "bars",
			"targetAxisIndex": "1",
			"color": "#D0D0D0"
		},
		"5": {
			"type": "bars",
			"targetAxisIndex": "1",
			"color": "#C0C0C0"
		}
	},
	"vAxes": {
		"0": {
			"title": "Temperatur [°C]",
			"format": "decimal"
		},
		"1": {
			"title": "Brennzeit [s] während 1h = 3600s",
			"format": "decimal",
			"ticks": [{"v":"900","f":"0,25h"},{"v":"1800","f":"0,50h"},{"v":"2700","f":"0,75h"},{"v":"3600","f":"1,00h"}]
		}
	},
	"hAxis": {
		"title": "$l_title",
		"format": "H",
		"gridlines": {
			"count": -1,
			"units": {
				"days": {"format": ["MMM dd"]},
				"hours": {"format": ["HH:mm", "ha"]}
			}
		},
		"ticks": [$l_ticks]
	}
}
f_create_opt_day_EOF
}

f_create_opt_day_iphone(){
# function to create option file for google charts
#
# input parameter 1: filename with full path
local -r l_filename="$1"
local -r l_title="$2"
local -r l_date="$3"

l_datestring_Y=$(date -d "@$l_date" +%Y)
l_datestring_M=$(( $(date -d "@$l_date" +%-m) - 1 ))
# javascript has Jan=0, Feb=1, ...
l_datestring_D=$(date -d "@$l_date" +%-d)

l_complete="Date($l_datestring_Y"",""$l_datestring_M"",""$l_datestring_D"
l_ticks=""
for i in {0,2,4,6,8,10,12,14,16,18,20,22}
do
	l_ticks="$l_ticks""{\"v\":"\""$l_complete"",$i,0,0)\"},"
done

l_date_next_day=$(( $l_date + 86400 ))

h1=$(date -d "@$l_date")
h2=$(date -d "@$l_date_next_day")
log_debug_silent "$FUNCNAME $LINENO $l_date $h1 $l_date_next_day $h2"

l_datestring_Y=$(date -d "@$l_date_next_day" +%Y)
l_datestring_M=$(( $(date -d "@$l_date_next_day" +%-m) - 1 ))
# javascript has Jan=0, Feb=1, ...
l_datestring_D=$(date -d "@$l_date_next_day" +%-d)
l_complete="Date($l_datestring_Y"",""$l_datestring_M"",""$l_datestring_D"
l_ticks="$l_ticks""{\"v\":"\""$l_complete"",0,0,0)\"}"

# {"v":"Date(2016,11,20,00,00,00)"}

log_debug_silent "$FUNCNAME $LINENO $l_date $l_complete $l_ticks"

cat > $l_filename <<f_create_opt_day_iphone_EOF
{
	"title":"Temperaturen und Brennerlaufzeiten",
	"width": 736,
	"height": 414,
	"backgroundColor": {
		"stroke": "#ddd",
		"strokeOpacity": 1
	},
	"chartArea": {"width": "85%", "height": "70%"},
	"curveType": "function",
	"theme": "material",
	"legend": {
		"position": "top"
	},
	"seriesType": "line",
	"series": {
		"4": {
			"type": "bars",
			"targetAxisIndex": "1",
			"color": "#D0D0D0"
		},
		"5": {
			"type": "bars",
			"targetAxisIndex": "1",
			"color": "#C0C0C0"
		}
	},
	"vAxes": {
		"0": {
			"title": "Temperatur [°C]",
			"format": "decimal"
		},
		"1": {
			"title": "Brennzeit [s] während 1h = 3600s",
			"format": "decimal",
			"ticks": [{"v":"900","f":"0,25h"},{"v":"1800","f":"0,50h"},{"v":"2700","f":"0,75h"},{"v":"3600","f":"1,00h"}]
		}
	},
	"hAxis": {
		"title": "$l_title",
		"format": "H",
		"gridlines": {
			"count": -1,
			"units": {
				"days": {"format": ["MMM dd"]},
				"hours": {"format": ["HH:mm", "ha"]}
			}
		},
		"ticks": [$l_ticks]
	}
}
f_create_opt_day_iphone_EOF
}


f_create_opt_day1(){
# function to create option file for google charts
#
# input parameter 1: filename with full path
local -r l_filename="$1"
local -r l_title="$2"

cat > $l_filename <<f_create_opt_month2_EOF
{
			"title":"Temperaturen Bienenstock",
			"width": 900,
			"height": 525,
			"backgroundColor": {
				"stroke": "#ddd",
				"strokeOpacity": 1
			},
			"chartArea": {"width": "88%", "height": "70%"},
			"curveType": "function",
			"theme": "material",
			"legend": {
				"position": "top"
			},
			"vAxis": {
				"title": "Temperatur [°C]",
				"format": "decimal"
			},
			"hAxis": {
				"title": "$l_title",
				"gridlines": {
					"count": 31
				},
				"format": "d"
			}
		}
f_create_opt_month2_EOF
}

f_get_temp(){
# function to retrieve a temperatur value from the specified sensor
# input parameter 1: sensor name like e.g. "/sys/bus/w1/devices/28-000005ce8588/w1_slave"
# input parameter 2: if parameter 2 = 1, function will provide random number as temperature, not using a sensor
# returns temperature on stdout
# returncode 1 if sensor does not exist
# returncode 0 if sensor exists and returned a value
local -r i_sensor="$1"
local -r i_random="$2"

if [[ "$i_random" = "1" ]]; then
	local l_temp=$(shuf -i 10000-30000 -n 1)
	local l_convert=$(echo "scale=1; $l_temp / 1000" | bc | awk '{printf "%2.1f", $0}')
	echo $l_convert
	return 0
fi

if [[ ! -e "$i_sensor" ]]; then
	return 1
else
	local l_temp=$(grep t= $i_sensor|cut -d= -f2)
	local l_convert=$(echo "scale=1; $l_temp / 1000" | bc | awk '{printf "%2.1f", $0}')
	echo $l_convert
	return 0
fi	
}

function f_create_DB
{
# function to create empty specified DB - if not already existing DB
# input parameter 1: sqlite3 database file
# input parameter 2: sqlite3 database tablename
local -r i_db="$1"
local -r i_table="$2"

log_info "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

if [[ "$i_db" = "" ]] || [[ "$i_table" = "" ]]; then
	log_error "$FUNCNAME $LINENO DB or table not specified"
	return 1
fi

local l_today=$(date +%Y%m%d)
local l_today_00=$(date -d "$l_today" +%s)

if [[ ! -e "$i_db" ]]; then
	sqlite3 $i_db "CREATE TABLE IF NOT EXISTS $i_table (unixtime INTEGER PRIMARY KEY,TempA REAL,TempAg REAL, TempAbg REAL, PumpeStatusSp INT, TempWWsoll REAL, TempWW REAL, TempWWmin REAL, TempKsoll REAL, TempKist REAL, RoomTemp1 REAL, BrennerStatus1 INT, BrennerStatus2 INT, BrennerStarts INT, BrennerSekunden1 INT, BrennerSekunden2 INT, Oil INT, Slope1 REAL, Level1 INT, EcoMode1 INT, GenOpMode1 INT, HeatPump1 INT, IntPump INT, test_flag INTEGER);"
	# sqlite3 $i_db "CREATE TABLE IF NOT EXISTS $i_table (unixtime INTEGER PRIMARY KEY,zone1 REAL,zone2 REAL,zone3 REAL,air REAL,device REAL,test_flag INTEGER);"
	log_info "$FUNCNAME $LINENO DB $i_db created with table $i_table - now initializing DB"
	local l_current_time=$(f_get_timestamp_rounded_5)
	# 15724800 secondes = 182 days
	local l_6m_ago=$(( $l_today_00 - 15724800 ))
	local l_time=$l_6m_ago
	while (( $l_time < $l_current_time )); do
		sql_string=$l_time,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
		log_debug "$FUNCNAME $LINENO sqlite3 insert into $i_table values $sql_string"
		eval "sqlite3 $i_db \"insert into $i_table values($sql_string);\" | tee -a $logfile 2>&1"
		l_time=$(( $l_time + 900 ))
	done
	log_info "$FUNCNAME $LINENO DB $i_db initialized"
else
	log_info "$FUNCNAME $LINENO DB $i_db already exists"
fi

log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
return 0
}

function f_get_timestamp_rounded_15
{
# function to retrieve current temp and round to to 15min intervall
# required for later processing in rrdtool
# returns current time, rounded to 15min intervals and converted to unix epoch time
set $(date "+%Y %m %d %H %M")
# only for test & debug: set desired date manually
# set $(date -d "20140826 00:00" +"%Y %m %d %H %M")
local m=$((100+15*(${5#0}/15)))
# local timestamp_rounded="$1$2$3 $4:${m#1}"
echo $(date --date "$1$2$3 $4:${m#1}" +%s)
}

function f_get_timestamp_rounded_5
{
# function to retrieve current temp and round to to 15min intervall
# required for later processing in rrdtool
# returns current time, rounded to 15min intervals and converted to unix epoch time
set $(date "+%Y %m %d %H %M")
# only for test & debug: set desired date manually
# set $(date -d "20140826 00:00" +"%Y %m %d %H %M")
local m=$((100+5*(${5#0}/5)))
# local timestamp_rounded="$1$2$3 $4:${m#1}"
echo $(date --date "$1$2$3 $4:${m#1}" +%s)
}

function f_get_value_from_heating()
{
# this function retrieves the value from the Viessmann Heating
# it also does some sanity checks
# silent function - returns value on stdout
# returns return code 0 if retrieval was ok
# returns return code 128 if no valid value was retrieved
# input parameter 1: -c command accepted by vclient, e.g. "getIntPump"
# input parameter 2: known invalid return value, e.g. "128.500000" for "getTempA"; function will try again, if invalid value was retrieved
# input parameter 3: unixtime - will be used to retrieve value from db in case the sensor does not deliver value
local -r i_command="$1"
local -r i_invalid="$2"
local -r i_unixtime="$3"

local m_value=$($g_vclient_cmd -h 127.0.0.1:3002 -c $i_command | tail -n 1 |cut -d' ' -f1)

local i=0
while [ "$m_value" == "$i_invalid" -a $i -lt 4 ]
do
	log_error_silent "$FUNCNAME $LINENO attempt $i illegal value $m_value for $i_command"
	m_value=$($g_vclient_cmd -h 127.0.0.1:3002 -c $i_command | tail -n 1 |cut -d' ' -f1)
	((i++))
done

if [ "$m_value" = "$i_invalid" ]; then
	m_value=0
	echo "$m_value"
	return 128
else
	echo "$m_value"
	return 0
fi
}



function f_get_sensordata(){
log_info "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
# function to retrieve temperatures from sensors and store them into specified DB
# input parameter 1: sqlite3 database file
# input parameter 2: unixtime - so that all functions will use the same reference time independent of runtime of certain functions
# input parameter 3: if = 1 will not use temp sensors, but random numbers
# 
local -r i_db="$1"
local -r i_unixtime="$2"
local -r i_random="$3"

if [[ "$i_db" = "" ]]; then
	log_error "$FUNCNAME $LINENO no database specified"
	return 128
else
	log_debug "$FUNCNAME $LINENO using DB $i_db"
fi

if [[ "$i_unixtime" = "" ]]; then
	log_error "$FUNCNAME $LINENO no timestamp specified"
	return 128
else
	log_debug "$FUNCNAME $LINENO using timestamp $(date -d @$i_unixtime)"
fi

if [[ "$i_random" = "1" ]]; then
	log_warning "$FUNCNAME $LINENO no real temp sensors used - using random numbers instead"
fi

m_TempA=$(f_get_value_from_heating getTempA 128.500000 |awk '{printf "%1.1f", $0}')
if [ "$?" = "128" ]; then
	m_TempA=$(f_get_single_value $g_database $g_table $TempA $(( $i_unixtime - 300 )))
	log_error "$FUNCNAME $LINENO got crazy value but will use DB value $m_TempA"
fi
log_info "$FUNCNAME $LINENO got value $m_TempA for m_TempA"
m_TempAg=$(f_get_value_from_heating getTempAg)
log_info "$FUNCNAME $LINENO got value $m_TempAg for m_TempAg"
m_TempAbg=$(f_get_value_from_heating getTempAbg 128.500000)
log_info "$FUNCNAME $LINENO got value $m_TempAbg for m_TempAbg"
m_PumpeStatusSp=$(f_get_value_from_heating getCylPriPump)
log_info "$FUNCNAME $LINENO got value $m_PumpeStatusSp for m_PumpeStatusSp"
m_TempWWsoll=$(f_get_value_from_heating getTempWWsoll)
log_info "$FUNCNAME $LINENO got value $m_TempWWsoll for m_TempWWsoll"
m_TempWW=$(f_get_value_from_heating getTempWW 128.500000 |awk '{printf "%1.1f", $0}')
log_info "$FUNCNAME $LINENO got value $m_TempWW for m_TempWW"
m_TempWWmin=$(f_get_value_from_heating getTempWWmin)
log_info "$FUNCNAME $LINENO got value $m_TempWWmin for m_TempWWmin"
m_TempKist=$(f_get_value_from_heating getTempKist |awk '{printf "%1.1f", $0}')
log_info "$FUNCNAME $LINENO got value $m_TempKist for m_TempKist"

# TempKsoll currently not working
# TempKsoll=$($vclient_cmd -h 127.0.0.1:3002 -c  getTempKsoll | tail -n 1 |cut -d' ' -f1)
m_TempKsoll=0

m_BrennerStatus1=$(f_get_value_from_heating getBrennerStatus1 NOT)
log_info "$FUNCNAME $LINENO got value $m_BrennerStatus1 for m_BrennerStatus1"
m_BrennerStatus2=$(f_get_value_from_heating getBrennerStatus2)
log_info "$FUNCNAME $LINENO got value $m_BrennerStatus2 for m_BrennerStatus2"
m_BrennerStarts=$(f_get_value_from_heating getBrennerStarts)
log_info "$FUNCNAME $LINENO got value $m_BrennerStarts for m_BrennerStarts"
m_BrennerSekunden1=$(f_get_value_from_heating getBrennerSekunden1 84215048.000000)
log_info "$FUNCNAME $LINENO got value $m_BrennerSekunden1 for m_BrennerSekunden1"
m_BrennerSekunden2=$(f_get_value_from_heating getBrennerSekunden2 84215048.000000)
log_info "$FUNCNAME $LINENO got value $m_BrennerSekunden2 for m_BrennerSekunden2"
m_Oil=$(f_get_value_from_heating getOil 84215048.000000)
log_info "$FUNCNAME $LINENO got value $m_Oil for m_Oil"
m_Slope1=$(f_get_value_from_heating getSlope1)
log_info "$FUNCNAME $LINENO got value $m_Slope1 for m_Slope1"
m_Level1=$(f_get_value_from_heating getLevel1)
log_info "$FUNCNAME $LINENO got value $m_Level1 for m_Level1"
m_EcoMode1=$(f_get_value_from_heating getEcoMode1)
log_info "$FUNCNAME $LINENO got value $m_EcoMode1 for m_EcoMode1"
m_GenOpMode1=$(f_get_value_from_heating getGenOpMode1|awk '{printf "%1.0f", $0}')
log_info "$FUNCNAME $LINENO got value $m_GenOpMode1 for m_GenOpMode1"
m_HeatPump1=$(f_get_value_from_heating getHeatPump1)
log_info "$FUNCNAME $LINENO got value $m_HeatPump1 for m_HeatPump1"
m_IntPump=$(f_get_value_from_heating getIntPump NOT)
log_info "$FUNCNAME $LINENO got value $m_IntPump for m_IntPump"

# doing remote read of room temp
m_RoomTemp1=$(ssh pi@$g_ip_livingroom "grep t= /sys/bus/w1/devices/28-000005ceb15d/w1_slave|cut -d= -f2")
if [ "x$m_RoomTemp1" == "x" ]; then 
	log_error "$FUNCNAME $LINENO no RoomTemp1 - sensor / Raspi offline"
	m_RoomTemp1=0
else
	m_RoomTemp1=$(echo "scale=1; $m_RoomTemp1 / 1000" | bc)
	log_info "$FUNCNAME $LINENO Temperature in Room is $m_RoomTemp1"
fi

log_info "$FUNCNAME $LINENO $timestamp_real AussenTemp $m_TempA, AussenTemp gedämpft $m_TempAg, AbgasTemp $m_TempAbg, Speicherladepumpe $m_PumpeStatusSp, Warmwasser Soll $m_TempWWsoll, Warmwasser Ist $m_TempWW, Warmwasser Min $m_TempWWmin, Kessel Soll $m_TempKsoll, Kessel Ist $m_TempKist, Wohnzimmer $m_RoomTemp1, Brennerstufe1 $m_BrennerStatus1, Brennerstufe2 $m_BrennerStatus2, Brenner Starts $m_BrennerStarts, Brennersekunden1 $m_BrennerSekunden1, BrennerSekunden2 $m_BrennerSekunden2, Ölzähler $m_Oil, Steigung $m_Slope1, Niveau $m_Level1, EcoMode $m_EcoMode1, Interne Pumpe $m_IntPump, Pumpe HK1 $m_HeatPump1"

sql_string="$i_unixtime,$m_TempA,$m_TempAg,$m_TempAbg,$m_PumpeStatusSp,$m_TempWWsoll,$m_TempWW,$m_TempWWmin,$m_TempKsoll,$m_TempKist,$m_RoomTemp1,$m_BrennerStatus1,$m_BrennerStatus2,$m_BrennerStarts,$m_BrennerSekunden1,$m_BrennerSekunden2,$m_Oil,$m_Slope1,$m_Level1,$m_EcoMode1,$m_GenOpMode1,$m_HeatPump1,$m_IntPump,0"

log_info "$FUNCNAME $LINENO sqlite3 $i_db insert into $g_table values $sql_string"
# echo "sqlite3 $i_db \"insert into $i_table values($sql_string);\"" >>$redo_logfile_sql
	
eval "sqlite3 $i_db \"insert into $g_table values($sql_string);\""

# return 0
# device=$(echo "scale=1; $(cat $device_sens) / 1000" | bc)
# log_info "$FUNCNAME $LINENO device sensor $device_sens showed $device"

# sql_string=$timestamp_rounded_unix,$zone1,$zone2,$zone3,$air,$device,0
# log_info "$FUNCNAME $LINENO sqlite3 insert into rawdata_bee1 values $sql_string"
# eval "sqlite3 $i_db \"insert into rawdata_bee1 values($sql_string);\" | tee -a $logfile 2>&1"

log_info "$FUNCNAME $LINENO create html pages with current sensordata"
local l_helper=$(date -d @$i_unixtime +"%d.%m. %H:%M")
f_create_html_header "data/week_pos0.html" "$l_helper"
f_create_html_temp "data/week_pos1.html" "$m_TempA" "$(f_get_min_day_value $i_db $g_table TempA $i_unixtime)" "$(f_get_avg_day_value $i_db $g_table TempA $i_unixtime)" "$(f_get_max_day_value $i_db $g_table TempA $i_unixtime)" "Aussen [°C]"
f_create_html_temp "data/week_pos2.html" "$m_TempWW" "$(f_get_min_day_value $i_db $g_table TempWW $i_unixtime)" "$(f_get_avg_day_value $i_db $g_table TempWW $i_unixtime)" "$(f_get_max_day_value $i_db $g_table TempWW $i_unixtime)" "Warmw. [°C]"
f_create_html_temp "data/week_pos3.html" "$m_RoomTemp1" "$(f_get_min_day_value $i_db $g_table RoomTemp1 $i_unixtime)" "$(f_get_avg_day_value $i_db $g_table RoomTemp1 $i_unixtime)" "$(f_get_max_day_value $i_db $g_table RoomTemp1 $i_unixtime)" "Raum [°C]"
f_create_html_temp "data/week_pos4.html" "$m_TempKist" "$(f_get_min_day_value $i_db $g_table TempKist $i_unixtime)" "$(f_get_avg_day_value $i_db $g_table TempKist $i_unixtime)" "$(f_get_max_day_value $i_db $g_table TempKist $i_unixtime)" "Kessel [°C]"

log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function f_do_jsondata_month()
{
# creates json file for transfer to webserver with current temp data
# input parameter 1: sqlite database
# input parameter 2: datatable to be used
# input parameter 3-6: fields with temperature data

local -r i_db="$1"
local -r i_table="$2"
local -r i_field1="$3"
local -r i_field2="$4"
local -r i_field3="$5"
local -r i_field4="$6"

log_info "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

if [[ "$i_db" = "" ]]; then
	log_error "$FUNCNAME $LINENO database file not specified"
	return 1
fi

# current month, year with day "15", e.g. 15.08.2014
# later used for calculating last and first day of months
local l_graph_start_15=$(date -d "$(date "+%Y%m"15)" +%Y%m%d)

local l_ref=$(date -d "$l_graph_start_15" +%Y%m%d)
local l_begin=$(date -d "$(date -d "$l_ref" +%Y%m01)" +%s)
local l_end=$(date -d "$l_ref +1 month -$(date +%d -d "$l_ref") days" +%Y%m%d)
local l_end2=$(date -d "$(date -d "$l_end" +%Y%m%d) 23:59:59" +%s)

local l_month_count=0

# now create 7 json files and 7 opt files for current month + 5 months in the past
while [[ $l_month_count < 6 ]]; do
	log_info "$FUNCNAME $LINENO processing month $(date -d "@$l_begin")"
	local l_filename=$pool_env/data/current_month_$l_month_count.json
	local l_filename2="$pool_env/data/current_month_classic_""$l_month_count"".opt"
	if [[ $l_month_count > 0 ]]; then
		l_datestring_check=$(date -d @$l_begin +%Y,)$(( $(date -d @$l_begin +%-m) - 1 ))
		if [[ -e $l_filename ]]; then
			if [[ $(grep -c "$l_datestring_check" $l_filename) > 0 ]]; then
				log_debug "$FUNCNAME $LINENO grep -c \"$l_datestring_check\" $l_filename result is $(grep -c "$l_datestring_check" $l_filename)"
				log_debug "$FUNCNAME $LINENO filename $l_filename already exists with correct data"
				# this detects already existing datafile
				# no need to create datafile again
				
				# prepare new iteration
				l_month_count=$(( $l_month_count + 1 ))
				l_graph_start_15=$(date -d "$(date "+%Y%m"15) -$l_month_count month" +%Y%m%d)
				l_ref=$(date -d "$l_graph_start_15" +%Y%m%d)
				l_begin=$(date -d "$(date -d "$l_ref" +%Y%m01)" +%s)
				l_end=$(date -d "$l_ref +1 month -$(date +%d -d "$l_ref") days" +%Y%m%d)
				l_end2=$(date -d "$(date -d "$l_end" +%Y%m%d) 23:59:59" +%s)
				continue
			else
				log_info "$FUNCNAME $LINENO no suitable json data found in $l_filename - creating it"
			fi
		else
			log_info "$FUNCNAME $LINENO no json file $l_filename found - creating it"
		fi
	fi
	f_create_opt_month2 "$l_filename2" "$(LC_ALL=de_DE.utf8 date -d @$l_begin +'%B %Y')"

	cat > $l_filename << do_jsondata_month_EOF
	{
	  "cols": [
			{"id": "A", "label": "Zeitpunkt", "type": "date"},
			{"id": "B", "label": "Aussen [°C]", "type": "number"},
			{"id": "C", "label": "Warmwasser [°C]", "type": "number"},
			{"id": "D", "label": "Wohnzimmer [°C]", "type": "number"},
			{"id": "E", "label": "Kessel [°C]", "type": "number"}
		  ],
	  "rows": [
do_jsondata_month_EOF

	# this loop will get an average value for each day of a month
	local i=$l_begin
	while true; do
		# echo Test Processing $(date -d @$i) $(date -d @$i +%Y,%m,%d,%H,%M,%S)
		log_debug "$FUNCNAME $LINENO proceccing day $(date -d @$i) $(date -d @$i +%Y,%m,%d,%H,%M,%S)"
		l_temp1=$(f_get_avg_2h_value $i_db $i_table $i_field1 $i)
		l_rc=$?
		if [[ "$l_rc" = "1" ]]; then
			log_debug "$FUNCNAME $LINENO NO DATA for $(date -d @$i) $(date -d @$i +%Y,%m,%d,%H,%M,%S)"
		else
			# correct month: javascript month January = 0, Feb = 1, ...
			l_datestring=$(date -d @$i +%Y,)$(( $(date -d @$i +%-m) - 1 ))$(date -d @$i +,%d,%H,%M,%S)
			# echo corrected date $l_datestring
			printf "{\"c\":[">>$l_filename
			printf "{\"v\":\"Date($l_datestring)\"},">>$l_filename
			printf "{\"v\":\"$l_temp1\"},">>$l_filename
			printf "{\"v\":\"$(f_get_avg_2h_value $i_db $i_table $i_field2 $i)\"},">>$l_filename
			printf "{\"v\":\"$(f_get_avg_2h_value $i_db $i_table $i_field3 $i)\"},">>$l_filename
			printf "{\"v\":\"$(f_get_avg_2h_value $i_db $i_table $i_field4 $i)\"}">>$l_filename
			printf "]},\n">>$l_filename
		fi
		i=$(( $i + 7200 ))
		if [[ $i > $(date +%s) ]]; then
			break
		fi
		if [[ $i > $l_end2 ]]; then
		   break
		fi
	done
	l_last_line=$(tail -1 $l_filename)
	sed -i '$ d' $l_filename
	printf "$l_last_line"|sed 's/,$//'>>$l_filename
	printf "\n]}\n">>$l_filename

	# prepare new iteration
	l_month_count=$(( $l_month_count + 1 ))
	l_graph_start_15=$(date -d "$(date "+%Y%m"15) -$l_month_count month" +%Y%m%d)
	l_ref=$(date -d "$l_graph_start_15" +%Y%m%d)
	l_begin=$(date -d "$(date -d "$l_ref" +%Y%m01)" +%s)
	l_end=$(date -d "$l_ref +1 month -$(date +%d -d "$l_ref") days" +%Y%m%d)
	l_end2=$(date -d "$(date -d "$l_end" +%Y%m%d) 23:59:59" +%s)
done
log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function f_do_jsondata_week()
{
# creates json file for transfer to webserver with current temp data
# input parameter 1: sqlite database
# input parameter 2: datatable to be used
# input parameter 3-6: fields with temperature data

local -r i_db="$1"
local -r i_table="$2"
local -r i_field1="$3"
local -r i_field2="$4"
local -r i_field3="$5"
local -r i_field4="$6"

log_info "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

if [[ "$(LC_ALL=de_DE.utf8 date +%a)" = "Mo" ]]; then
	l_graph_start_monday_hlp=$(date +%Y%m%d)
	local l_graph_start_monday=$(date -d "$l_graph_start_monday_hlp" +%s)
else
	local l_graph_start_monday=$(date -d "last Monday" +%s)
fi

local l_begin=$l_graph_start_monday
local l_end2=$(( $l_begin + 604799 ))

local l_week_count=0
log_debug "$FUNCNAME $LINENO $l_begin is $(date -d "@$l_begin")"

# now create 6 json files and 6 opt files for current week + 5 weeks in the past
while [[ $l_week_count < 6 ]]; do
	log_info "$FUNCNAME $LINENO processing week starting on $(date -d "@$l_begin")"
	local l_filename=$pool_env/data/current_week_$l_week_count.json
	local l_filename2="$pool_env/data/current_week_classic_""$l_week_count"".opt"
		log_debug "$FUNCNAME $LINENO here"
	if [[ $l_week_count > 0 ]]; then
		l_datestring_check=$(date -d @$l_begin +%Y,)$(( $(date -d @$l_begin +%-m) - 1 ))$(date -d @$l_begin +,%d,%H,%M,%S)
		if [[ -e $l_filename ]]; then
		log_debug "$FUNCNAME $LINENO here"
			if [[ $(grep -c "$l_datestring_check" $l_filename) > 0 ]]; then
				log_debug "$FUNCNAME $LINENO grep -c \"$l_datestring_check\" $l_filename result is $(grep -c "$l_datestring_check" $l_filename)"
				log_debug "$FUNCNAME $LINENO filename $l_filename already exists with correct data"
				# this detects already existing datafile
				# no need to create datafile again
				
				# prepare new iteration
				l_week_count=$(( $l_week_count + 1 ))
				l_begin=$(( $l_begin - 604800 ))
				l_end2=$(( $l_end2 - 604800 ))
				continue
			fi
		log_debug "$FUNCNAME $LINENO here"
		fi
	fi
	l_text="Woche von "$(LC_ALL=de_DE.utf8 date -d @$l_begin '+%A, den %d.%m.%Y')" bis "$(LC_ALL=de_DE.utf8 date -d @$l_end2 '+%A, den %d.%m.%Y')
	log_debug "$FUNCNAME $LINENO here"
	f_create_opt_week "$l_filename2" "$l_text" "$l_begin"
	log_debug "$FUNCNAME $LINENO here"
	cat > $l_filename << do_jsondata_week_EOF
	{
	  "cols": [
			{"id": "A", "label": "Zeitpunkt", "type": "date"},
			{"id": "B", "label": "Aussen [°C]", "type": "number"},
			{"id": "C", "label": "Wohnzimmer [°C]", "type": "number"},
			{"id": "D", "label": "Brenner1 [s]", "type": "number"},
			{"id": "E", "label": "Brenner2 [s]", "type": "number"}
		  ],
	  "rows": [
do_jsondata_week_EOF

	local i=$l_begin
		log_debug "$FUNCNAME $LINENO here"
	while true; do
		log_debug "$FUNCNAME $LINENO proceccing hour $(date -d @$i +%H:%S) $(date -d @$i +%Y,%m,%d,%H,%M,%S)"
		l_temp1=$(f_get_avg_hour_value $i_db $i_table $i_field1 $i)
		l_rc=$?
		if [[ "$l_rc" = "1" ]]; then
			log_debug "$FUNCNAME $LINENO NO DATA for $(date -d @$i) $(date -d @$i +%Y,%m,%d,%H,%M,%S)"
		else
			# correct month: javascript month January = 0, Feb = 1, ...
			l_datestring=$(date -d @$i +%Y,)$(( $(date -d @$i +%-m) - 1 ))$(date -d @$i +,%d,%H,%M,%S)
			# echo corrected date $l_datestring
			printf "{\"c\":[">>$l_filename
			printf "{\"v\":\"Date($l_datestring)\"},">>$l_filename
			printf "{\"v\":\"$l_temp1\"},">>$l_filename
			printf "{\"v\":\"$(f_get_avg_hour_value $i_db $i_table $i_field2 $i)\"},">>$l_filename
			if [ "$(date -d @$i +%H%M)" = "0000" ]; then
				log_debug "$FUNCNAME $LINENO bar value for $(date --date @$i)"
				printf "{\"v\":\"$(f_get_delta_day_value $i_db $i_table $i_field3 $i)\"},">>$l_filename
				printf "{\"v\":\"$(f_get_delta_day_value $i_db $i_table $i_field4 $i)\"}">>$l_filename
			else
				printf "{\"v\":null}">>$l_filename
			fi
			printf "]},\n">>$l_filename
		fi
		i=$(( $i + 3600 ))
		if [[ $i > $(date +%s) ]]; then
			break
		fi
		if [[ $i > $l_end2 ]]; then
		   break
		fi
	done
	l_last_line=$(tail -1 $l_filename)
	sed -i '$ d' $l_filename
	printf "$l_last_line"|sed 's/,$//'>>$l_filename
	printf "\n]}\n">>$l_filename

	# prepare new iteration
	l_week_count=$(( $l_week_count + 1 ))
	l_begin=$(( $l_begin - 604800 ))
	l_end2=$(( $l_end2 - 604800 ))
done
log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function f_do_jsondata_day()
{
# creates json file for transfer to webserver with current temp data
# also creates "option" file for google chart display on webpage
# input parameter 1: sqlite database
# input parameter 2: datatable to be used
# input parameter 3-6: fields with temperature data

local -r i_db="$1"
local -r i_table="$2"
local -r i_field1="$3"
local -r i_field2="$4"
local -r i_field3="$5"
local -r i_field4="$6"
local -r i_field5="$7"
local -r i_field6="$8"

log_info "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

# Obtain current date, but with time "00:00"; output e.g. 20160601
local l_ref=$(date -d "@$(date +%s)" +%Y%m%d)

#  convert date + "00:00" time to unixepoch
local l_begin=$(date -d "$l_ref" +%s)

# add 24h
local l_end2=$(( $l_begin + 86400 ))

local l_day_count=0

# now create 7 json files and 7 opt files for current day + 6 days in the past
while [[ $l_day_count < 7 ]]; do
	log_info "$FUNCNAME $LINENO processing day $(date -d "@$l_begin")"
	local l_filename=$pool_env/data/current_day_$l_day_count.json
	local l_filename2="$pool_env/data/current_day_classic_""$l_day_count"".opt"
	local l_filename_iphone="$pool_env/data/current_day_iphone_""$l_day_count"".opt"
	if [[ $l_day_count > 0 ]]; then
		l_datestring_check=$(date -d @$l_begin +%Y,)$(( $(date -d @$l_begin +%-m) - 1 ))$(date -d @$l_begin +,%d)
		if [[ -e $l_filename ]]; then
			if [[ $(grep -c "$l_datestring_check" $l_filename) > 0 ]]; then
				log_debug "$FUNCNAME $LINENO grep -c \"$l_datestring_check\" $l_filename result is $(grep -c "$l_datestring_check" $l_filename)"
				log_debug "$FUNCNAME $LINENO filename $l_filename already exists with correct data"
				# this detects already existing datafile
				# no need to create datafile again
				
				# prepare new iteration
				l_day_count=$(( $l_day_count + 1 ))
				l_begin=$(( $l_begin - 86400 ))
				l_end2=$(( $l_end2 - 86400 ))
				continue
			else
				log_info "$FUNCNAME $LINENO no suitable json data found in $l_filename - creating it"
			fi
		else	
			log_info "$FUNCNAME $LINENO no json file $l_filename found - creating it"
		fi
	fi
	f_create_opt_day "$l_filename2" "$(LC_ALL=de_DE.utf8 date -d @$l_begin +'%A, %d. %B %Y')" "$l_begin"
	f_create_opt_day_iphone "$l_filename_iphone" "$(LC_ALL=de_DE.utf8 date -d @$l_begin +'%A, %d. %B %Y')" "$l_begin"
	# f_create_opt_day_iphone "$l_filename_iphone" "$(LC_ALL=de_DE.utf8 date -d @$l_begin +'%A, %d. %B %Y')"

	cat > $l_filename << do_jsondata_day_EOF
	{
	  "cols": [
			{"id": "A", "label": "Zeitpunkt", "type": "date"},
			{"id": "B", "label": "Aussen [°C]", "type": "number"},
			{"id": "C", "label": "Warmwasser [°C]", "type": "number"},
			{"id": "D", "label": "Wohnzimmer [°C]", "type": "number"},
			{"id": "E", "label": "Kessel [°C]", "type": "number"},
			{"id": "F", "label": "Brenner1 [s]", "type": "number"},
			{"id": "F", "label": "Brenner2 [s]", "type": "number"}
		  ],
	  "rows": [
do_jsondata_day_EOF

	l_datapoints_count=$(sqlite3 $i_db "select count(1) from $i_table where unixtime>=$l_begin and unixtime<=$l_end2;")
	l_datapoints=$(sqlite3 $i_db "select unixtime from $i_table where unixtime>=$l_begin and unixtime<=$l_end2;")
	log_info "$FUNCNAME $LINENO creating json with $l_datapoints_count values from $(date -d @$l_begin) to $(date -d @$l_end2)"
	log_debug "$FUNCNAME $LINENO sqlite3 $i_db \"select unixtime from $i_db where unixtime>=$l_begin and unixtime<=$l_end2;\""
	if [[ "$l_datapoints_count" = "0" ]]; then
		log_info "$FUNCNAME $LINENO no data found for $l_begin $(date -d "@$l_begin" +%Y%m%d)"
	else
		log_debug "$FUNCNAME $LINENO found $l_datapoints_count datapoints for $l_begin $(date -d "@$l_begin" +%Y%m%d)"
	fi
	
	log_debug "$FUNCNAME $LINENO Datapoint to process $l_datapoints"
	for l_datapoint in $l_datapoints
	do 
		log_debug "$FUNCNAME $LINENO Processing $(date -d @$l_datapoint) $(date -d @$l_datapoint +%Y,%m,%d,%H,%M,%S) Air $(f_get_single_value $i_db $i_table $i_field1 $l_datapoint) $l_datapoint"
		l_temp1=$(f_get_single_value $i_db $i_table $i_field1 $l_datapoint)
		# l_rc=$?
		# if [[ "$l_rc" = "1" ]]; then
			# echo NO DATA for $(date -d @$i) $(date -d @$i +%Y,%m,%d,%H,%M,%S)
		# else
			# correct month: javascript month January = 0, Feb = 1, ...
			l_datestring=$(date -d @$l_datapoint +%Y,)$(( $(date -d @$l_datapoint +%-m) - 1 ))$(date -d @$l_datapoint +,%d,%H,%M,%S)
			# echo corrected date $l_datestring
			printf "{\"c\":[">>$l_filename
			printf "{\"v\":\"Date($l_datestring)\"},">>$l_filename
			printf "{\"v\":\"$l_temp1\"},">>$l_filename
			printf "{\"v\":\"$(f_get_single_value $i_db $i_table $i_field2 $l_datapoint)\"},">>$l_filename
			printf "{\"v\":\"$(f_get_single_value $i_db $i_table $i_field3 $l_datapoint)\"},">>$l_filename
			printf "{\"v\":\"$(f_get_single_value $i_db $i_table $i_field4 $l_datapoint)\"},">>$l_filename
			if [ "$(date -d @$l_datapoint +%M)" = "00" ]; then
				printf "{\"v\":\"$(f_get_delta_hour_value $i_db $i_table $i_field5 $l_datapoint)\"},">>$l_filename
				printf "{\"v\":\"$(f_get_delta_hour_value $i_db $i_table $i_field6 $l_datapoint)\"}">>$l_filename
			else
				printf "{\"v\":null}">>$l_filename
			fi
				
			printf "]},\n">>$l_filename
		# fi
	done
	l_last_line=$(tail -1 $l_filename)
	sed -i '$ d' $l_filename
	printf "$l_last_line"|sed 's/,$//'>>$l_filename
	printf "\n]}\n">>$l_filename
	
	l_day_count=$(( $l_day_count + 1 ))
	l_begin=$(( $l_begin - 86400 ))
	l_end2=$(( $l_end2 - 86400 ))
done

log_info "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
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
      	log_info "$FUNCNAME $LINENO $speed $speedunit"
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
	rsync -avzq data/* tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/$g_subdomain/php/data
fi
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}


function get_sensordata()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

log_debug "$FUNCNAME $LINENO sensor output $bee_zone1_sens $(f_get_temp $bee_zone1_sens)"
f_get_temp $bee_zone1_sens
# this fuction gets sensor data and stores it
# into global variables water, air, roof, flow, return_t
   	local temp=$(grep t= $water_sens|cut -d= -f2)
   	water=$(echo "scale=1; $temp / 1000" | bc | awk '{printf "%2.2f", $0}')

   	local temp=$(grep t= $air_sens|cut -d= -f2)
   	air=$(echo "scale=1; $temp / 1000" | bc | awk '{printf "%2.2f", $0}')

    local temp=$(grep t= $roof_sens|cut -d= -f2)
	roof=$(echo "scale=1; $temp / 1000" | bc | awk '{printf "%2.2f", $0}')

# modify roof temp for testing
# roof=$(echo "scale=1; $water + 6.3" | bc)

    local temp=$(grep t= $flow_sens|cut -d= -f2)
	flow=$(echo "scale=1; $temp / 1000" | bc)

    local temp=$(grep t= $return_sens|cut -d= -f2)
	return_t=$(echo "scale=1; $temp / 1000" | bc)

#	Very first reading on the day might give negative value
#	for heating since measurement was before valve is fully closed. 
# 	We wait 60sec and measure again.
	if [ $(echo "scale=2;$return_t-$flow+0.5 < 0"|bc) -eq 1 ]; then
		log_warning "$FUNCNAME $LINENO Flow $flow minus Return $return_t negative, waiting 120sec"
		sleep 120
		local temp=$(grep t= $flow_sens|cut -d= -f2)
		flow=$(echo "scale=1; $temp / 1000" | bc)
		local temp=$(grep t= $return_sens|cut -d= -f2)
		return_t=$(echo "scale=1; $temp / 1000" | bc)
		log_warning "$FUNCNAME $LINENO new value Flow $flow Return $return_t after 120sec"
	fi
	
	local temp=$(cat $device_sens)
    device=$(echo "scale=1; $temp / 1000" | bc)

    log_info "$FUNCNAME $LINENO water $water, air $air, roof $roof, flow $flow, return_t $return_t, device $device"

log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_switch()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
# this fuction determines, wether or not the water should
# circulate through the heat mat
# it also switches on or off the pump and the heat valve
# now determine todays / current pump status according to time schedule
        temp="$(date "+%Y%m%d") $(echo $pump_from)"
        pump_from_unix=$(date --date "$temp" +%s)
        temp="$(date "+%Y%m%d") $(echo $pump_to)"
        pump_to_unix=$(date --date "$temp" +%s)
		
		declare -i heat_flag_before=$(sqlite3 $database_sql "select heat_db_value from rawdata_pool where unixtime=$timestamp_rounded_unix - 900;")
		l_gain=$(echo "scale=2;$return_t-$flow"|bc)
		log_debug "$FUNCNAME $LINENO Heat status 900 sec ago was $heat_flag_before"
		
        pump_flag=AUS
        if (( timestamp_rounded_unix >= pump_from_unix && timestamp_rounded_unix < pump_to_unix && winter_mode_pump == 0 ))
		then
			log_info "$FUNCNAME $LINENO Time is between $pump_from_unix and $pump_to_unix"
        	pump_flag=AN
        else
			if [[ $(echo "$roof-$temp_diff > $water"|bc) -eq 1 && "$heat_priority" == "1" ]]; then
				log_debug "$FUNCNAME $LINENO Pool Heating possible and heat_priority is on - switch on pump, although outside pump hours"
				log_debug "$FUNCNAME $LINENO $roof $temp_diff $water $heat_priority"
				pump_flag=AN
			fi
			log_debug "$FUNCNAME $LINENO heat flag before $heat_flag_before gain $l_gain"
			if [[ $heat_flag_before -eq 1 && $(echo "$l_gain > 0.5"|bc) -eq 1 ]]; then
				# No Wintermode and we are NOT within PUMP hours
				# however, heat was on, so we had a sunny day 15min before
				log_info "$FUNCNAME $LINENO Heat 900 sec ago was $heat_flag_before - current gain is $return_t - $flow = $l_gain > 0.5"
				pump_flag=AN
			fi
		fi
        log_info "$FUNCNAME $LINENO determined pump should be $pump_flag"
		log_info "$FUNCNAME $LINENO Heat 900 sec ago was $heat_flag_before - current gain is $return_t - $flow = $(echo "scale=2;$return_t-$flow"|bc)"

	if [ "$winter_mode_pump" = "0" ]; then
		if [ "$pump_flag" = "AN" ]; then
			$send_cmd $pump_power 1
			log_info "$FUNCNAME $LINENO switched pump $pump_power to $pump_flag"
		else
			$send_cmd $pump_power 0
			log_info "$FUNCNAME $LINENO switched pump $pump_power to $pump_flag"
		fi
	else
		log_info "$FUNCNAME $LINENO winter mode pump is active - pump stays off"
		$send_cmd $pump_power 0
	fi

# Now turn heat on, if prerequisites are fulfilled

	if [ "$winter_mode_heat" = "0" ]; then
		if [ "$pump_flag" = "AN" ]; then
			if [[ $(echo "$roof-$temp_diff > $water"|bc) -eq 1 ]]; then
			# if [[ $(echo "$roof-$temp_diff > $water"|bc) -eq 1 || $heat_flag_before -eq 1 && $(echo "$l_gain > 0.5"|bc) -eq 1 ]]; then
				heat_flag=AN
				$send_cmd $heat_power 1
				log_info "$FUNCNAME $LINENO switched heat $heat_power to $heat_flag delta roof-water is  $(echo "$roof-$water"|bc)"
				log_debug "$FUNCNAME $LINENO Heat Flag Before: $heat_flag_before; Gain: $l_gain; Roof $roof Water $water"
			else
				log_info "$FUNCNAME $LINENO roof/temp difference not high enough"
				if [[ $heat_flag_before = 1 && $(echo "$l_gain > 0.5"|bc) -eq 1 ]]; then
					log_info "$FUNCNAME $LINENO extend heating time due to positive gain = $l_gain"
					heat_flag=AN
				else
					heat_flag=AUS
					$send_cmd $heat_power 0
					log_info "$FUNCNAME $LINENO switched heat $heat_power to $heat_flag delta roof-water is $(echo "$roof-$water"|bc)"
				fi
			fi
		else
			$send_cmd $heat_power 0
			heat_flag=AUS
			log_info "$FUNCNAME $LINENO heat possibility not determined - pump is off - switched $heat_power to $heat_flag"
		fi
	else
		log_info "$FUNCNAME $LINENO winter mode heat is active - heat stays off"
		heat_flag=AUS
		$send_cmd $heat_power 0
	fi
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_switch2()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
# this fuction determines, wether or not the water should
# circulate through the heat mat
# it also switches on or off the pump and the heat valve
# now determine todays / current pump status according to time schedule
        temp="$(date "+%Y%m%d") $(echo $pump_from)"
        pump_from_unix=$(date --date "$temp" +%s)
        temp="$(date "+%Y%m%d") $(echo $pump_to)"
        pump_to_unix=$(date --date "$temp" +%s)
		
		declare -i heat_flag_before=$(sqlite3 $database_sql "select heat_db_value from rawdata_pool where unixtime=$timestamp_rounded_unix - 900;")
		l_gain=$(echo "scale=2;$return_t-$flow"|bc)
		
        pump_flag=AUS
		heat_flag=AUS
        if (( timestamp_rounded_unix >= pump_from_unix && timestamp_rounded_unix < pump_to_unix ))
		then
			log_info "$FUNCNAME $LINENO Time is between $(date -d "@$pump_from_unix" +%H:%M) and $(date -d "@$pump_to_unix" +%H:%M)"
        	pump_flag=AN
			if [[ $(echo "$roof-$temp_diff > $water"|bc) -eq 1 ]]; then
				log_info "$FUNCNAME $LINENO Pool Heating possible and within pump hours"
				heat_flag=AN
			fi
		fi
		if [[ $(echo "$roof-$temp_diff > $water"|bc) -eq 1 && "$heat_priority" == "1" && "$heat_flag" == "AUS" ]]; then
				log_debug "$FUNCNAME $LINENO Pool Heating possible and heat_priority is on - switch on pump, even outside of pump hours"
				pump_flag=AN
				heat_flag=AN
		fi
		if [[ $heat_flag_before -eq 1 && $(echo "$l_gain > 0.4"|bc) -eq 1 && "$heat_flag" == "AUS" ]]; then
				log_info "$FUNCNAME $LINENO Heat 900 sec ago was $heat_flag_before - current gain is $return_t - $flow = $l_gain, leaving heat on"
				pump_flag=AN
				heat_flag=AN
		fi

        log_info "$FUNCNAME $LINENO determined pump should be $pump_flag"
        log_info "$FUNCNAME $LINENO determined heat should be $heat_flag"
		log_info "$FUNCNAME $LINENO Heat 900 sec ago was $heat_flag_before - current gain is $return_t - $flow = $l_gain and roof is $roof and water is $water"

# pump and heat destination status determined; now switching...		
	if [ "$winter_mode_pump" = "0" ]; then
		if [ "$pump_flag" = "AN" ]; then
			$send_cmd $pump_power 1
			log_info "$FUNCNAME $LINENO switched pump $pump_power to $pump_flag"
		fi
		if [ "$pump_flag" = "AUS" ]; then
			$send_cmd $pump_power 0
			log_info "$FUNCNAME $LINENO switched pump $pump_power to $pump_flag"
		fi
	else
		log_info "$FUNCNAME $LINENO winter mode pump is active - pump stays off"
		$send_cmd $pump_power 0
	fi

# Now turn heat on, if prerequisites are fulfilled

	if [ "$winter_mode_heat" = "0" ]; then
		if [ "$pump_flag" = "AN" ]; then
			if [ "$heat_flag" = "AN" ]; then
				$send_cmd $heat_power 1
				log_info "$FUNCNAME $LINENO switched heat $heat_power to $heat_flag delta roof-water is  $(echo "$roof-$water"|bc)"
			fi
			if [ "$heat_flag" = "AUS" ]; then
				$send_cmd $heat_power 0
				log_info "$FUNCNAME $LINENO switched heat $heat_power to $heat_flag delta roof-water is  $(echo "$roof-$water"|bc)"
			fi
		fi
	else
		log_info "$FUNCNAME $LINENO winter mode heat is active - heat stays off"
		$send_cmd $heat_power 0
	fi
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_storeDB()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

	if [ "$pump_flag" = "AN" ];
	then
		pump_db_value=1
	else	
		pump_db_value=0
# modifiy flow and return_t value and assign current water temp.
# The real sensors make no sense, because the pump is not working 
# (pump_db_value=0) and thus the water is not moving through the pipe. 
# and through the sensors.
# It is logically consistent to store the real water temperature
# here.
		flow=$water
		return_t=$water
	fi

	if [ "$heat_flag" = "AN" ];
	then
		   heat_db_value=1
	else
		   heat_db_value=0
# modifiy flow and return_t value and assign current water temp.
# Here we know, that the heat mat is currently off (heat_db_value=0)
# so there is no temperature increase possible.
# It is logically consistent to store the real water temperature
# here. This will also cause the difference between flow and return to be "0".
		   flow=$water
		   return_t=$water
	fi
 
	rrd_string=$timestamp_rounded_unix:$water:$air:$roof:$flow:$return_t:$pump_db_value:$heat_db_value:$device
	rrdtool update "$database" "$rrd_string"
	log_info "$FUNCNAME $LINENO rrdtool update $database $rrd_string"
	echo  rrdtool update $database $rrd_string >>$redo_logfile
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_storeSQL()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
	# sudo apt-get install sqlite3
	# sqlite3 temp_pool.sqlite "CREATE TABLE IF NOT EXISTS rawdata_pool (unixtime INTEGER PRIMARY KEY,water REAL,air REAL,roof REAL,flow REAL,return_t REAL,pump_db_value INT,heat_db_value INT,device REAL);"
	# Template for possible commands
	# sqlite3 temp_heating.sqlite "select BrennerStarts from rawdata_oil where unixtime >=10000"
	# sqlite3 temp_heating.sqlite "alter table rawdata_oil add COLUMN Slope1 REAL"
	# sqlite3 temp_heating.sqlite "alter table rawdata_oil add COLUMN Level1 INT"
	
	# Interesting SQL Statements:
	#  select datetime(unixtime, 'unixepoch', 'localtime'), RoomTemp1, EcoMode1, GenopMode1, heatpump1, intpump from rawdata_oil where unixtime >=1417993200;
	# Oil_last=$(sqlite3 $database_sql "select oil from rawdata_oil where unixtime=$timestamp_rounded_unix - 300;")


	sql_string=$timestamp_rounded_unix,$water,$air,$roof,$flow,$return_t,$pump_db_value,$heat_db_value,$device
	
	log_info "$FUNCNAME $LINENO sqlite3 insert into rawdata_pool values $sql_string"
		
	eval "sqlite3 $database_sql \"insert into rawdata_pool values($sql_string);\" | tee -a $logfile 2>&1"
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function f_do_control_heating()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

# performs heating control depending on time, livingroom temp
# input parameter 1: sqlite database
# input parameter 2: datatable to be used
# input parameter 3: current rounded time as unixtime

local -r i_db="$1"
local -r i_table="$2"
local -r i_timestamp="$3"
local -r i_field2="$4"

if [[ "$g_wintermode" == "0" ]]; then
	log_info "$FUNCNAME $LINENO Wintermode off, no heating control"
	return 0
fi

# this function tries to control the viessmann heating
# by using the data from the most important room
# and using the eco mode function once the desired values
# are reached.

# determine relevant setting from init_vars
# should the heating be on now? --> l_reduced_mode=0/1
# what is the desired temp now? --> l_relevant_target
temp="$(date "+%Y%m%d") $(echo ${g_livingroom_from[$(date +%u)]})"
declare -r -i l_livingroom_from_unix=$(date --date "$temp" +%s)

temp="$(date "+%Y%m%d") $(echo ${g_livingroom_to[$(date +%u)]})"
declare -r -i l_livingroom_to_unix=$(date --date "$temp" +%s)
	
if (( $timestamp_rounded_unix >= l_livingroom_from_unix && $timestamp_rounded_unix <= l_livingroom_to_unix ));
then
	# this is within the defined timerange
	declare -r l_relevant_target=$(echo "$g_livingroom_target - 0.5"|bc)
	declare -r l_reduced_mode=0
	log_debug "$FUNCNAME $LINENO within timerange - relevant target is $l_relevant_target"
else
	# this is outside of the defined timerange
	declare -r l_relevant_target=$(echo "$g_livingroom_reduced - 0.5"|bc)
	declare -r l_reduced_mode=1
	log_debug "$FUNCNAME $LINENO outside timerange - relevant target is $l_relevant_target"
fi

m_HeatPump1=$(f_get_single_value $i_db $i_table HeatPump1 $i_timestamp)
m_IntPump=$(f_get_single_value $i_db $i_table IntPump $i_timestamp)
m_TempA=$(f_get_single_value $i_db $i_table TempA $i_timestamp)
m_EcoMode1=$(f_get_single_value $i_db $i_table EcoMode1 $i_timestamp)
m_GenOpMode1=$(f_get_single_value $i_db $i_table GenOpMode1 $i_timestamp)
m_Level1=$(f_get_single_value $i_db $i_table Level1 $i_timestamp)
RoomTemp1=$(f_get_single_value $i_db $i_table RoomTemp1 $i_timestamp)
PumpeStatusSp=$(f_get_single_value $i_db $i_table PumpeStatusSp $i_timestamp)

log_info "$FUNCNAME $LINENO before case: m_HeatPump1 is $m_HeatPump1; m_IntPump is $m_IntPump; Speicherladepumpe is $PumpeStatusSp; AussenTemp is $m_TempA; case ${m_EcoMode1}${m_GenOpMode1}"

case "$m_EcoMode1""$m_GenOpMode1" in
	02) 
		# Heating is on; no EcoMode
		# Example: l_relevat_target is 21.0; 
		# room temp <21.0 do nothing
		# room temp >=21.0 and <21.5 set m_Ecomode1 to 1 ---> next situation will be "12"
		# room temp >=21.5 m_GenOpMode1 to 1 = switch heating off
		log_info "$FUNCNAME $LINENO case Situation 02 m_EcoMode1 is 0; m_GenOpMode1 is 2; RoomTemp is $RoomTemp1"
		if (( $(echo "$RoomTemp1 >= $l_relevant_target"|bc) == 1 )); then
			log_info "$FUNCNAME $LINENO case Situation 02 Roomtemp >= target $l_relevant_target - enable EcoMode"
			$g_vclient_cmd -h 127.0.0.1:3002 -c "setEcoMode1 1" | tee -a $logfile
		else
			log_info "$FUNCNAME $LINENO case Situation 02 Roomtemp < target $l_relevant_target"
			if [ "$m_Level1" != "5" ]; then
				log_info "$FUNCNAME $LINENO case Situation 02: setLevel1 to 5K"
				$g_vclient_cmd -h 127.0.0.1:3002 -c "setLevel1 5" | tee -a $logfile
			else
				log_info "$FUNCNAME $LINENO case Situation 02 reduce freeze protection problem: setLevel1 was already 5K"
			fi
		fi
	;;
	12)
		# Heating is on; EcoMode is on
		# Example: l_relevat_target is 21.0; 
		# room temp <21.0 do nothing
		# room temp >=21.0 and <21.5 set m_Ecomode1 to 1 ---> next situation will be "12"
		# room temp >=21.5 m_GenOpMode1 to 1 = switch heating off
		log_info "$FUNCNAME $LINENO case Situation 12 m_EcoMode1 is 1; m_GenOpMode1 is 2; RoomTemp is $RoomTemp1"
		if (( $(echo "$RoomTemp1 >= $l_relevant_target"|bc) == 1 )); then
			log_info "$FUNCNAME $LINENO case Situation 12 Roomtemp >= target $l_relevant_target"
		else
			log_info "$FUNCNAME $LINENO case Situation 12 Roomtemp < target $l_relevant_target"
		fi
	;;
	01)
		log_info "$FUNCNAME $LINENO case Situation m_EcoMode1 is 0; m_GenOpMode1 is 1; RoomTemp is $RoomTemp1"
		if (( $(echo "$RoomTemp1 >= $l_relevant_target"|bc) == 1 )); then
			log_info "$FUNCNAME $LINENO case Situation Roomtemp >= target $l_relevant_target"
			if [ "$m_HeatPump1" == "1" ]; then
				log_error "$FUNCNAME $LINENO case Situation 01 Roomtemp $RoomTemp1 >= target $l_relevant_target and m_HeatPump1 is $m_HeatPump1 - freeze protection?"
				if [ "$m_Level1" != "-10" ]; then
					$g_vclient_cmd -h 127.0.0.1:3002 -c "setLevel1 -10" | tee -a $logfile
					log_info "$FUNCNAME $LINENO case Situation 01 reduce freeze protection problem: setLevel1 to -10K"
				else
					log_info "$FUNCNAME $LINENO case Situation 01 reduce freeze protection problem: setLevel1 was already -10K"
				fi
			fi
		else
			log_info "$FUNCNAME $LINENO case Situation 01 Roomtemp < target $l_relevant_target"
			$g_vclient_cmd -h 127.0.0.1:3002 -c "setGenOpMode1 02 HeizWWTimer" | tee -a $logfile
			$g_vclient_cmd -h 127.0.0.1:3002 -c "setEcoMode1 1" | tee -a $logfile
		fi
	;;
	11)
		log_info "$FUNCNAME $LINENO case Situation 11 m_EcoMode1 is 1; m_GenOpMode1 is 1 - should never happen; RoomTemp is $RoomTemp1"
		if (( $(echo "$RoomTemp1 >= $l_relevant_target"|bc) == 1 )); then
			log_info "$FUNCNAME $LINENO case Situation 11 Roomtemp >= target $l_relevant_target"
		else
			log_info "$FUNCNAME $LINENO case Situation 11 Roomtemp < target $l_relevant_target"
		fi
	;;
	*)
		log_error "$FUNCNAME $LINENO case Situation m_EcoMode1 is $m_EcoMode1; m_GenOpMode1 is $m_GenOpMode1 - unexpected RoomTemp is $RoomTemp1"
	;;
esac

log_debug "$FUNCNAME $LINENO l_reduced_mode,m_EcoMode1,m_GenOpMode1,l_relevant_target,RoomTemp1 $l_reduced_mode,$m_EcoMode1,$m_GenOpMode1,$l_relevant_target,$RoomTemp1"

if (( $l_reduced_mode == 0 && $m_EcoMode1 == 0 && $m_GenOpMode1 == 2 )); then
	# normal heating operation; check if too hot
	if (( $(echo "$RoomTemp1 >= $l_relevant_target"|bc) == 1 )); then
		# room temp too hot, we have to set eco mode
		log_info "$FUNCNAME $LINENO Roomtemp $RoomTemp1 is too hot larger than $l_relevant_target, enable EcoMode1"
		$g_vclient_cmd -h 127.0.0.1:3002 -c "setEcoMode1 1" | tee -a $logfile
	fi
fi

if (( $l_reduced_mode == 0 && $m_EcoMode1 == 1 )); then
	# normal heating operation, but EcoMode enabled
	# because roomTemp was too hot before
	if (( $(echo "$RoomTemp1 <= $l_relevant_target - $g_hysteresis"|bc) == 1 )); then
		# room temp too cold, we have to disable eco mode
		log_info "$FUNCNAME $LINENO Roomtemp $RoomTemp1 is too cold less than $l_relevant_target - $g_hysteresis, disable EcoMode1"
		$g_vclient_cmd -h 127.0.0.1:3002 -c "setEcoMode1 0" | tee -a $logfile
	fi
fi

log_debug "$FUNCNAME $LINENO Check1 $m_GenOpMode1 $m_EcoMode1"
if (( $m_EcoMode1 == 1 && $m_GenOpMode1 == 2 )); then
	# normal heating operation, but EcoMode enabled
	# because roomTemp was too hot before
	if (( $(echo "$RoomTemp1 >= $l_relevant_target + $g_hysteresis"|bc) == 1 )); then
		# room temp way too hot, we have to disable heating 
		log_info "$FUNCNAME $LINENO Roomtemp $RoomTemp1 is too hot, more than $l_relevant_target + $g_hysteresis, disable Heating (only WW)"
		$g_vclient_cmd -h 127.0.0.1:3002 -c "setGenOpMode1 01 WWTimer" | tee -a $logfile
	fi
fi
log_debug "$FUNCNAME $LINENO Check2"

# if (( $l_reduced_mode == 1 && $m_GenOpMode1 == 1 )); then
if (( $m_GenOpMode1 == 1 )); then
	# reduced mode (timer Heating)
	# AND GenOpMode1 = 1 = only Warmwater Production, no heating
	# because roomTemp was too hot before
	# we switch to back to heating, if RoomTemp1 gets too cold
	if (( $(echo "$RoomTemp1 < $l_relevant_target"|bc) == 1 )); then
		# room temp too cold, we have to enable heating again
		log_info "$FUNCNAME $LINENO Roomtemp $RoomTemp1 is too cold less than $l_relevant_target, enable Heating again"
		$g_vclient_cmd -h 127.0.0.1:3002 -c "setGenOpMode1 02 HeizWWTimer" | tee -a $logfile
		# 2=WW+Heating
	fi
fi

if (( $l_reduced_mode == 1 && $m_GenOpMode1 == 2 )); then
	# reduced mode (timer Heating)
	# AND GenOpMode1 = 2 = Warmwater Production AND  heating
	# we switch off Heating, if RoomTemp1 is too hot
	if (( $(echo "$RoomTemp1 >= $l_relevant_target + $g_hysteresis"|bc) == 1 )); then
		# room temp too hot, we have to diable heating
		log_info "$FUNCNAME $LINENO Roomtemp $RoomTemp1 is too hot larger than $l_relevant_target + $g_hysteresis, disable Heating"
		$g_vclient_cmd -h 127.0.0.1:3002 -c "setGenOpMode1 01 WWTimer" | tee -a $logfile
		# 1=only WW
	fi
fi

log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}


function do_graphic_init()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

# current date, but with (local) time 00:00
graph_start_hlp=$(date --date "$(date "+%Y%m%d") 00:00" +%s)

# only for test / debug: set graph_start_hlp to desired date
# graph_start_hlp=$(date --date "20140826 00:00" +%s)


# current month, year with day "15", e.g. 15.08.2014
# later used for calculating last and first day of months
graph_start_15=$(date -d "$(date "+%Y%m"15)" +%Y%m%d)

graph_start_day=$graph_start_hlp
graph_start_yesterday=$(echo "scale=1; $graph_start_day - 86400" | bc)
graph_start_24h=$(echo "scale=1; $timestamp_rounded_unix - 86400" | bc)
graph_start_7d=$(echo "scale=1; $graph_start_hlp - 604800" | bc)
graph_start_4wk=$(echo "scale=1; $graph_start_hlp - 2419200" | bc)
graph_start_month=$(date --date "$(date "+%Y%m01") 00:00" +%s)


graph_start_monday=$(date --date "last Monday" +%s)
export LANG=de_DE.UTF8
if [ "$(date +%a)" = "Mo" ]; then
	graph_start_monday=$(($graph_start_monday + 604800))
fi
echo DEBUG aktueller Montag $graph_start_monday $(date -d "@$graph_start_monday") >>$logfile

# graph_defs='-w 1800 -h 1050 -D -a PNG -T 15 --slope-mode --vertical-label "Temperatur °C" --font DEFAULT:18: 
graph_defs='-w 900 -h 525 -D -a PNG -T 15 --slope-mode --font AXIS:10 --font LEGEND:12 --font UNIT:12 --font TITLE:14\
	DEF:water=temp_pool.rrd:water:AVERAGE \
	DEF:air=temp_pool.rrd:air:AVERAGE \
	DEF:delta=temp_pool.rrd:delta:AVERAGE \
	DEF:heat_flag=temp_pool.rrd:heat_flag:AVERAGE \
	DEF:pump_flag=temp_pool.rrd:pump_flag:AVERAGE \
	DEF:roof=temp_pool.rrd:roof:AVERAGE \
	DEF:roof24hmax=temp_pool.rrd:roof:MAX:step=86400 \
	DEF:roof24hmin=temp_pool.rrd:roof:MIN:step=86400 \
	DEF:air24hmax=temp_pool.rrd:air:MAX:step=86400 \
	DEF:air24hmin=temp_pool.rrd:air:MIN:step=86400 \
	VDEF:rooflast=roof,LAST \
	VDEF:roofmin=roof,MINIMUM \
	VDEF:roofmax=roof,MAXIMUM \
	VDEF:roofavg=roof,AVERAGE \
	VDEF:waterlast=water,LAST \
	VDEF:watermax=water,MAXIMUM \
	VDEF:watermin=water,MINIMUM \
	VDEF:wateravg=water,AVERAGE \
	VDEF:airlast=air,LAST \
	VDEF:airmax=air,MAXIMUM \
	VDEF:airmin=air,MINIMUM \
	VDEF:airavg=air,AVERAGE \
	VDEF:gainlast=delta,LAST \
	VDEF:gainmax=delta,MAXIMUM \
    CDEF:gain=delta,airmin,+ \
	CDEF:air24harea=air24hmax,air24hmin,- \
	CDEF:roof24harea=roof24hmax,roof24hmin,- \
	HRULE:20#000000 \
	CDEF:pumptime=pump_flag,1,EQ,INF,UNKN,IF \
	CDEF:heattime=heat_flag,1,EQ,INF,UNKN,IF \
	CDEF:pumptimeclean=pump_flag,UN,0,pump_flag,IF,$graph_hours,* \
	CDEF:heattimeclean=heat_flag,UN,0,heat_flag,IF,$graph_hours,* \
	VDEF:totalpumptimeclean=pumptimeclean,AVERAGE \
	VDEF:totalheattimeclean=heattimeclean,AVERAGE \
	CDEF:deltaclean=delta,UN,0,delta,IF,$(($graph_hours * 4)),*,totalheattimeclean,/,4,/ \
	CDEF:deltaminhlp=delta,0,EQ,UNKN,delta,IF \
	VDEF:gainmin=deltaminhlp,MINIMUM \
	VDEF:gainavg=deltaclean,AVERAGE'
	
graph_caption_current='COMMENT:"\t\t      Akt.      Max      Min     Mittel\n" \
    AREA:pumptime#10101010 \
    AREA:heattime#FF000015 \
	LINE2:water#0000FF:"Wasser" \
	AREA:delta#FF000025::STACK \
    GPRINT:waterlast:"%4.1lf°C " \
    GPRINT:watermax:"%4.1lf°C " \
    GPRINT:watermin:"%4.1lf°C " \
	GPRINT:wateravg:"%4.1lf°C " \
	COMMENT:"     Pumpe\:      $pump_flag \n" \
	LINE2:air#00FF00:"Luft  " \
	GPRINT:airlast:"%4.1lf°C " \
    GPRINT:airmax:"%4.1lf°C " \
	GPRINT:airmin:"%4.1lf°C " \
	GPRINT:airavg:"%4.1lf°C " \
	COMMENT:"     Heizung\:    $heat_flag  \n" \
	LINE2:roof#FF0000:"Dach  " \
	GPRINT:rooflast:"%4.1lf°C " \
	GPRINT:roofmax:"%4.1lf°C "  \
	GPRINT:roofmin:"%4.1lf°C " \
	GPRINT:roofavg:"%4.1lf°C " \
	GPRINT:totalpumptimeclean:"     Filterzeit\: %2.2lf h \n" \
	COMMENT:"  Gain  " \
	GPRINT:gainlast:"%4.1lfK  " \
	GPRINT:gainmax:"%4.1lfK "  \
	GPRINT:gainmin:" %4.1lfK " \
	GPRINT:gainavg:" %4.1lfK " \
	GPRINT:totalheattimeclean:"      Heizzeit\:   %2.2lf h \n"'


graph_caption_past='COMMENT:"\t\t      Max      Min      Mittel\n" \
		AREA:pumptime#10101010 \
		AREA:heattime#FF000015 \
        LINE2:water#0000FF:"Wasser" \
		AREA:delta#FF000025::STACK \
        GPRINT:watermax:"%4.1lf°C " \
        GPRINT:watermin:"%4.1lf°C " \
		GPRINT:wateravg:"%4.1lf°C " \
		GPRINT:totalpumptimeclean:"         Filterzeit\: %4.2lf h \n" \
        LINE2:air#00FF00:"Luft  " \
        GPRINT:airmax:"%4.1lf°C " \
        GPRINT:airmin:"%4.1lf°C " \
        GPRINT:airavg:"%4.1lf°C " \
		GPRINT:totalheattimeclean:"         Heizzeit\:   %4.2lf h \n" \
		COMMENT:"  Dach  " \
		GPRINT:roofmax:"%4.1lf°C "  \
		GPRINT:roofmin:"%4.1lf°C " \
		GPRINT:roofavg:"%4.1lf°C \n" \
		COMMENT:"  Gain  " \
		GPRINT:gainmax:"%4.1lfK  "  \
		GPRINT:gainmin:"%4.1lfK  " \
		GPRINT:gainavg:"%4.1lfK \n"'

# graph_caption_past='COMMENT:"\t\t      Max      Min                   Max     Min\n" \
		# AREA:pumptime#10101010 \
		# AREA:heattime#FF000015 \
        # LINE2:water#0000FF:"Wasser" \
		# AREA:delta#FF000025::STACK \
        # GPRINT:watermax:"%4.1lf°C " \
        # GPRINT:watermin:"%4.1lf°C     " \
        # LINE2:roof#FF0000:"Dach" \
        # GPRINT:roofmax:"%4.1lf°C"  \
        # GPRINT:roofmin:"%4.1lf°C \n" \
        # LINE2:air#00FF00:"Luft  " \
        # GPRINT:airmax:"%4.1lf°C " \
        # GPRINT:airmin:"%4.1lf°C \n" \
		# GPRINT:totalpumptimeclean:"Filterzeit\: %2.2lf h " \
		# GPRINT:totalheattimeclean:"Heizzeit\: %2.2lf h \n"'

		# DEBUG
		# GPRINT:totalpumptimeavgcln:"totalpumptimeavgcln\: %2.8lf per h " \
		# GPRINT:totalheattimeavgcln:"totalheattimeavgcln\: %2.8lf per h \n"'	

# graph_caption_past_month='COMMENT:"\t\t     Max      Min                   Max     Min\n" \
        # LINE2:roof24hmin#FF000020:"Dach  " \
        # AREA:roof24harea#FF000020::STACK \
		# LINE2:roof#FF0000 \
        # GPRINT:roofmax:"%4.1lf°C "  \
        # GPRINT:roofmin:"%4.1lf°C \n" \
        # LINE2:air24hmin#00FF0040:"Luft  " \
		# AREA:air24harea#00FF0040::STACK \
        # GPRINT:airmax:"%4.1lf°C " \
        # GPRINT:airmin:"%4.1lf°C \n" \
        # LINE2:water#0000FF:"Wasser" \
        # GPRINT:watermax:"%4.1lf°C " \
        # GPRINT:watermin:"%4.1lf°C \n" \
		# GPRINT:totalpumptime:"Filterzeit\: %3.2lf h   " \
		# GPRINT:totalheattime:"Heizzeit\: %3.2lf h \n"'

graph_caption_past_month='COMMENT:"\t\t      Max      Min                   Max     Min\n" \
        LINE2:roof#0000FF:"Dach norm" \
        LINE2:roof24hmin#FF0000:"Dachmin" \
		AREA:roof24harea#FF000020::STACK \
        LINE2:roof24hmax#00FF00:"Dachmax"'
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_graphic_daily()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

# http://www.thegeekstuff.com/2011/07/bash-for-loop-examples/	
# for ((i=1, j=10; i <= 5 ; i++, j=j+5))
# do
# echo "Number $i: $j"
# done

# $ ./for10.sh
# Number 1: 10
# Number 2: 15
# Number 3: 20
# Number 4: 25
# Number 5: 30	
export LANG=de_DE.UTF8
	# for calculation for hourly rates by rddtool
	# we have to specify the number of hours of the graph
	# there is a rddtool bug, which sometimes selects 0.25 h too much
	# graph_hours will be used in $graph_defs
	graph_hours="24"

	for ((i=1, j=$graph_start_yesterday; i <= 6 ; i++, j=j-86400))
	do
		echo dayloop $i $j $(($j + 86399)) tempday$i.png $(date --date="@$j") $(date --date="@$(($j + 86399))")
	    eval "rrdtool graph tempday$i.png \
        -t \"am $(date -d @$j '+%A, den %d.%m.%Y')\" \
        -e $(($j + 86399)) -s $j $graph_defs $graph_caption_past"
	done

	echo I110 $(date "+%Y%m%d %H:%M") graphics for last 6 days created >>$logfile

	graph_hours="168"
	graph_start_monday=$(($graph_start_monday - 604800))
	for ((i=1, j=$graph_start_monday; i <= 6 ; i++, j=j-604800))
	do
		echo weekloop $i $j $(($j + 604799)) $(date --date="@$j") $(date --date="@$(($j + 604799))")
	    eval "rrdtool graph temp7d$i.png \
        -t \"Woche von $(date -d @$j '+%A, den %d.%m.%Y') bis $(date -d @$(($j + 604799)) '+%A, den %d.%m.%Y')\" \
        -e $(($j + 604799)) -s $j $graph_defs $graph_caption_past"
	done
	
	echo I110 $(date "+%Y%m%d %H:%M:%S") graphics for last 6 weeks created >>$logfile
	
	for ((i=1; i <= 6 ; i++))
	do
		ref=$(date -d "$graph_start_15 -$i month" +%Y%m%d)
		begin=$(date -d "$(date -d "$ref" +%Y%m01)" +%s)
		end=$(date -d "$ref +1 month -$(date +%d -d "$ref") days" +%Y%m%d)
		end2=$(date -d "$(date -d "$end" +%Y%m%d) 23:59:59" +%s)
		echo monthloop $i $begin $end2 $(date -d "@$begin") $(date -d "@$end2")
	    eval "rrdtool graph tempmo$i.png \
        -t \"Monat $(date -d @$begin +"%B %Y")\" \
        -e $end2 -s $begin $graph_defs $graph_caption_past_month"
	done
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_graphic()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS

# this influences the rrdtool caption language; e.g. weekday "Montag" or "Monday"
	export LANG=de_DE.UTF8

# this function creates the nice graphics via rrdtool	
# create daily statistics
	graph_hours="24"
	eval "rrdtool graph tempday.png \
        -t \"Heute $(date '+%A, den %d.%m.%Y %H:%M') \" \
	-e $(($graph_start_hlp + 86399)) -s $graph_start_hlp $graph_defs $graph_caption_current"
	# -e $timestamp_rounded_unix -s $graph_start_hlp $graph_defs $graph_caption_current"

	echo I104 $(date "+%Y%m%d %H:%M") graphic for today created >>$logfile


# create weekly statistics

	export LANG=de_DE.UTF8	
	graph_hours="168"
	eval "rrdtool graph temp7d.png \
        -t \"Aktuelle Woche, Status vom $(date '+%A, den %d.%m.%Y %H:%M') \" \
	-e $(($graph_start_monday + 604799))  -s $graph_start_monday $graph_defs $graph_caption_current"
	
	
    echo I104 $(date "+%Y%m%d %H:%M") graphic for current week created >>$logfile

# create monthly statistics

	ref=$(date -d "$graph_start_15" +%Y%m%d)
	begin=$(date -d "$(date -d "$ref" +%Y%m01)" +%s)
	end=$(date -d "$ref +1 month -$(date +%d -d "$ref") days" +%Y%m%d)
	end2=$(date -d "$(date -d "$end" +%Y%m%d) 23:59:59" +%s)

    eval "rrdtool graph tempmo$i.png \
        -t \"Monat $(date -d @$end2 +"%B %Y")\" \
        -e $end2 -s $begin $graph_defs $graph_caption_current"
    
	echo I104 $(date "+%Y%m%d %H:%M:%S") graphic for current month created >>$logfile
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_jsondata()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
# creates json file for transfer to webserver with current temp data

# this calculates the power of the heating in [kW]
# we need to know the amount of heated water (pump_flowrate) and the temperature delta
heat=$(echo "scale=4; ($return_t - $flow) * $pump_flowrate / 860" | bc | awk '{printf "%2.2f", $0}')
cat > current_temp.json << EOF
{
  "cols": [
        {"id":"","label":"Label","pattern":"","type":"string"},
        {"id":"","label":"Value","pattern":"","type":"number"}
      ],
  "rows": [
        {"c":[{"v":"Wasser","f":null},{"v":$water,"f":null}]},
        {"c":[{"v":"Luft","f":null},{"v":$air,"f":null}]},
        {"c":[{"v":"Heiz(kW)","f":null},{"v":$heat,"f":null}]},
        {"c":[{"v":"pump_db_value","f":null},{"v":$pump_db_value,"f":null}]},
        {"c":[{"v":"heat_db_value","f":null},{"v":$heat_db_value,"f":null}]},
        {"c":[{"v":"$(date "+%d.%m.%Y %H:%M")","f":null},{"v":0,"f":null}]}
      ]
}
EOF
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_jsondata_month()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
# creates json file for transfer to webserver with current temp data

# current month, year with day "15", e.g. 15.08.2014
# later used for calculating last and first day of months
local l_graph_start_15=$(date -d "$(date "+%Y%m"15)" +%Y%m%d)

local l_ref=$(date -d "$l_graph_start_15" +%Y%m%d)
local l_begin=$(date -d "$(date -d "$l_ref" +%Y%m01)" +%s)
local l_end=$(date -d "$l_ref +1 month -$(date +%d -d "$l_ref") days" +%Y%m%d)
local l_end2=$(date -d "$(date -d "$l_end" +%Y%m%d) 23:59:59" +%s)

# local l_datapoints=$(sqlite3 $database_sql "select unixtime from rawdata_pool where unixtime>=1462053600 and unixtime<=1466027999;")

local l_month_count=0

# now create 7 json files and 7 opt files for current month + 5 months in the past
while [[ $l_month_count < 6 ]]; do
	log_debug "$FUNCNAME $LINENO processing month $(date -d "@$l_begin")"
	local l_filename=$pool_env/current_month_$l_month_count.json
	local l_filename2="$pool_env/current_month_classic_""$l_month_count"".opt"
	if [[ $l_month_count > 0 ]]; then
		l_datestring_check=$(date -d @$l_begin +%Y,)$(( $(date -d @$l_begin +%-m) - 1 ))
		log_debug "$FUNCNAME $LINENO grep -c \"$l_datestring_check\" $l_filename result is $(grep -c "$l_datestring_check" $l_filename)"
		if [[ $(grep -c "$l_datestring_check" $l_filename) > 0 ]]; then
			log_debug "$FUNCNAME $LINENO filename $l_filename already exists with correct data"
			# this detects already existing datafile
			# no need to create datafile again
			
			# prepare new iteration
			l_month_count=$(( $l_month_count + 1 ))
			l_graph_start_15=$(date -d "$(date "+%Y%m"15) -$l_month_count month" +%Y%m%d)
			l_ref=$(date -d "$l_graph_start_15" +%Y%m%d)
			l_begin=$(date -d "$(date -d "$l_ref" +%Y%m01)" +%s)
			l_end=$(date -d "$l_ref +1 month -$(date +%d -d "$l_ref") days" +%Y%m%d)
			l_end2=$(date -d "$(date -d "$l_end" +%Y%m%d) 23:59:59" +%s)
			continue
		fi
	fi
	f_create_opt_month2 "$l_filename2" "$(LC_ALL=de_DE.utf8 date +'%B %Y')"

	cat > $l_filename << do_jsondata_month_EOF
	{
	  "cols": [
			{"id": "A", "label": "Zeitpunkt", "type": "date"},
			{"id": "B", "label": "Zone 1 [°C]", "type": "number"},
			{"id": "C", "label": "Zone 2 [°C]", "type": "number"},
			{"id": "D", "label": "Zone 3 [°C]", "type": "number"}
		  ],
	  "rows": [
do_jsondata_month_EOF

	# this loop will get an average value for each day of a month
	local i=$l_begin
	while true; do
		# echo Test Processing $(date -d @$i) $(date -d @$i +%Y,%m,%d,%H,%M,%S)
		log_debug "$FUNCNAME $LINENO proceccing day $(date -d @$i) $(date -d @$i +%Y,%m,%d,%H,%M,%S)"
		l_air=$(f_get_avg_day_value $database_sql rawdata_pool air $i)
		l_rc=$?
		if [[ "$l_rc" = "1" ]]; then
			log_debug "$FUNCNAME $LINENO NO DATA for $(date -d @$i) $(date -d @$i +%Y,%m,%d,%H,%M,%S)"
		else
			# correct month: javascript month January = 0, Feb = 1, ...
			l_datestring=$(date -d @$i +%Y,)$(( $(date -d @$i +%-m) - 1 ))$(date -d @$i +,%d)
			# echo corrected date $l_datestring
			printf "{\"c\":[">>$l_filename
			printf "{\"v\":\"Date($l_datestring)\"},">>$l_filename
			printf "{\"v\":\"$l_air\"},">>$l_filename
			printf "{\"v\":\"$(f_get_avg_day_value $database_sql rawdata_pool water $i)\"},">>$l_filename
			printf "{\"v\":\"$(f_get_avg_day_value $database_sql rawdata_pool roof $i)\"}">>$l_filename
			printf "]},\n">>$l_filename
		fi
		i=$(( $i + 86400 ))
		if [[ $i > $(date +%s) ]]; then
			break
		fi
		if [[ $i > $l_end2 ]]; then
		   break
		fi
	done
	l_last_line=$(tail -1 $l_filename)
	sed -i '$ d' $l_filename
	printf "$l_last_line"|sed 's/,$//'>>$l_filename
	printf "\n]}\n">>$l_filename

	# prepare new iteration
	l_month_count=$(( $l_month_count + 1 ))
	l_graph_start_15=$(date -d "$(date "+%Y%m"15) -$l_month_count month" +%Y%m%d)
	l_ref=$(date -d "$l_graph_start_15" +%Y%m%d)
	l_begin=$(date -d "$(date -d "$l_ref" +%Y%m01)" +%s)
	l_end=$(date -d "$l_ref +1 month -$(date +%d -d "$l_ref") days" +%Y%m%d)
	l_end2=$(date -d "$(date -d "$l_end" +%Y%m%d) 23:59:59" +%s)
done
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_jsondata_week()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
# creates json file for transfer to webserver with current temp data

local l_graph_start_monday=$(date -d "last Monday" +%s)

local l_begin=$l_graph_start_monday
local l_end2=$(( $l_begin + 604799 ))

local l_week_count=0

# now create 6 json files and 6 opt files for current week + 5 weeks in the past
while [[ $l_week_count < 6 ]]; do
	log_debug "$FUNCNAME $LINENO processing week starting on $(date -d "@$l_begin")"
	local l_filename=$pool_env/current_week_$l_week_count.json
	local l_filename2="$pool_env/current_week_classic_""$l_week_count"".opt"
	if [[ $l_week_count > 0 ]]; then
		l_datestring_check=$(date -d @$l_begin +%Y,)$(( $(date -d @$l_begin +%-m) - 1 ))$(date -d @$l_begin +,%d,%H,%M,%S)
		log_debug "$FUNCNAME $LINENO grep -c \"$l_datestring_check\" $l_filename result is $(grep -c "$l_datestring_check" $l_filename)"
		if [[ $(grep -c "$l_datestring_check" $l_filename) > 0 ]]; then
			log_debug "$FUNCNAME $LINENO filename $l_filename already exists with correct data"
			# this detects already existing datafile
			# no need to create datafile again
			
			# prepare new iteration
			l_week_count=$(( $l_week_count + 1 ))
			l_begin=$(( $l_begin - 604800 ))
			l_end2=$(( $l_end2 - 604800 ))
			continue
		fi
	fi
	l_text="Woche von "$(LC_ALL=de_DE.utf8 date -d @$l_begin '+%A, den %d.%m.%Y')" bis "$(LC_ALL=de_DE.utf8 date -d @$l_end2 '+%A, den %d.%m.%Y')
	f_create_opt_week "$l_filename2" "$l_text" "$l_begin"

	cat > $l_filename << do_jsondata_week_EOF
	{
	  "cols": [
			{"id": "A", "label": "Zeitpunkt", "type": "date"},
			{"id": "B", "label": "Zone 1 [°C]", "type": "number"},
			{"id": "C", "label": "Zone 2 [°C]", "type": "number"},
			{"id": "D", "label": "Zone 3 [°C]", "type": "number"}
		  ],
	  "rows": [
do_jsondata_week_EOF

	local i=$l_begin
	while true; do
		log_debug "$FUNCNAME $LINENO proceccing hour $(date -d @$i +%H:%S) $(date -d @$i +%Y,%m,%d,%H,%M,%S)"
		l_air=$(f_get_avg_hour_value $database_sql rawdata_pool air $i)
		l_rc=$?
		if [[ "$l_rc" = "1" ]]; then
			log_debug "$FUNCNAME $LINENO NO DATA for $(date -d @$i) $(date -d @$i +%Y,%m,%d,%H,%M,%S)"
		else
			# correct month: javascript month January = 0, Feb = 1, ...
			l_datestring=$(date -d @$i +%Y,)$(( $(date -d @$i +%-m) - 1 ))$(date -d @$i +,%d,%H,%M,%S)
			# echo corrected date $l_datestring
			printf "{\"c\":[">>$l_filename
			printf "{\"v\":\"Date($l_datestring)\"},">>$l_filename
			printf "{\"v\":\"$l_air\"},">>$l_filename
			printf "{\"v\":\"$(f_get_avg_hour_value $database_sql rawdata_pool water $i)\"},">>$l_filename
			printf "{\"v\":\"$(f_get_avg_hour_value $database_sql rawdata_pool roof $i)\"}">>$l_filename
			printf "]},\n">>$l_filename
		fi
		i=$(( $i + 3600 ))
		if [[ $i > $(date +%s) ]]; then
			break
		fi
		if [[ $i > $l_end2 ]]; then
		   break
		fi
	done
	l_last_line=$(tail -1 $l_filename)
	sed -i '$ d' $l_filename
	printf "$l_last_line"|sed 's/,$//'>>$l_filename
	printf "\n]}\n">>$l_filename

	# prepare new iteration
	l_week_count=$(( $l_week_count + 1 ))
	l_begin=$(( $l_begin - 604800 ))
	l_end2=$(( $l_end2 - 604800 ))
done
log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_jsondata_day()
{
log_debug "$FUNCNAME $LINENO start"
local -r -i l_runtime=$SECONDS
# creates json file for transfer to webserver with current temp data
# also creates "option" file for google chart display on webpage

# Obtain current date, but with time "00:00"; output e.g. 20160601
local l_ref=$(date -d "@$(date +%s)" +%Y%m%d)

#  convert date + "00:00" time to unixepoch
local l_begin=$(date -d "$l_ref" +%s)

# add 24h
local l_end2=$(( $l_begin + 86400 ))

local l_day_count=0

# now create 7 json files and 7 opt files for current day + 6 days in the past
while [[ $l_day_count < 7 ]]; do
	local l_filename=$pool_env/current_day_$l_day_count.json
	local l_filename2="$pool_env/current_day_classic_""$l_day_count"".opt"
	if [[ $l_day_count > 0 ]]; then
		l_datestring_check=$(date -d @$l_begin +%Y,)$(( $(date -d @$l_begin +%-m) - 1 ))$(date -d @$l_begin +,%d)
		log_debug "$FUNCNAME $LINENO grep -c \"$l_datestring_check\" $l_filename result is $(grep -c "$l_datestring_check" $l_filename)"
		if [[ $(grep -c "$l_datestring_check" $l_filename) > 0 ]]; then
			log_debug "$FUNCNAME $LINENO filename $l_filename already exists with correct data"
			# this detects already existing datafile
			# no need to create datafile again
			
			# prepare new iteration
			l_day_count=$(( $l_day_count + 1 ))
			l_begin=$(( $l_begin - 86400 ))
			l_end2=$(( $l_end2 - 86400 ))
			continue
		fi
	fi
	f_create_opt_day "$l_filename2" "$(LC_ALL=de_DE.utf8 date -d @$l_begin +'%A, %d. %B %Y')"

	cat > $l_filename << do_jsondata_day_EOF
	{
	  "cols": [
			{"id": "A", "label": "Zeitpunkt", "type": "date"},
			{"id": "B", "label": "Zone 1 [°C]", "type": "number"},
			{"id": "C", "label": "Zone 2 [°C]", "type": "number"},
			{"id": "D", "label": "Zone 3 [°C]", "type": "number"}
		  ],
	  "rows": [
do_jsondata_day_EOF

	l_datapoints_count=$(sqlite3 $database_sql "select count(1) from rawdata_pool where unixtime>=$l_begin and unixtime<$l_end2;")
	l_datapoints=$(sqlite3 $database_sql "select unixtime from rawdata_pool where unixtime>=$l_begin and unixtime<$l_end2;")

	log_debug "sqlite3 $database_sql \"select unixtime from rawdata_pool where unixtime>=$l_begin and unixtime<$l_end2;\""
	if [[ "$l_datapoints_count" = "0" ]]; then
		log_warning "$FUNCNAME $LINENO no data found for $l_begin $(date -d "@$l_begin" +%Y%m%d)"
	else
		log_info "$FUNCNAME $LINENO found $l_datapoints_count datapoints for $l_begin $(date -d "@$l_begin" +%Y%m%d)"
	fi
	
	for l_datapoint in $l_datapoints
	do 
		log_debug "$FUNCNAME $LINENO Processing $(date -d @$l_datapoint) $(date -d @$l_datapoint +%Y,%m,%d,%H,%M,%S) Air $(f_get_single_value $database_sql rawdata_pool air $l_datapoint) $l_datapoint"
		l_air=$(f_get_single_value $database_sql rawdata_pool air $l_datapoint)
		# l_rc=$?
		# if [[ "$l_rc" = "1" ]]; then
			# echo NO DATA for $(date -d @$i) $(date -d @$i +%Y,%m,%d,%H,%M,%S)
		# else
			# correct month: javascript month January = 0, Feb = 1, ...
			l_datestring=$(date -d @$l_datapoint +%Y,)$(( $(date -d @$l_datapoint +%-m) - 1 ))$(date -d @$l_datapoint +,%d,%H,%M,%S)
			# echo corrected date $l_datestring
			printf "{\"c\":[">>$l_filename
			printf "{\"v\":\"Date($l_datestring)\"},">>$l_filename
			printf "{\"v\":\"$l_air\"},">>$l_filename
			printf "{\"v\":\"$(f_get_single_value $database_sql rawdata_pool water $l_datapoint)\"},">>$l_filename
			printf "{\"v\":\"$(f_get_single_value $database_sql rawdata_pool roof $l_datapoint)\"}">>$l_filename
			printf "]},\n">>$l_filename
		# fi
	done
	l_last_line=$(tail -1 $l_filename)
	sed -i '$ d' $l_filename
	printf "$l_last_line"|sed 's/,$//'>>$l_filename
	printf "\n]}\n">>$l_filename
	
	l_day_count=$(( $l_day_count + 1 ))
	l_begin=$(( $l_begin - 86400 ))
	l_end2=$(( $l_end2 - 86400 ))
done

log_debug "$FUNCNAME $LINENO stop after $(( $SECONDS - $l_runtime )) seconds"
}

function do_transfer()
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

#check if displaypi is online
ping=$(ping -c 3 $displaypi_ip | grep received | cut -d ',' -f3 |cut -d ' ' -f2)
    if [ "$ping" = "0%" ]; then
        displaypi=online
        log_info "$FUNCNAME $LINENO displaypi.local is $displaypi"
    else
        displaypi=offline
        log_error "$FUNCNAME $LINENO displaypi.local is $displaypi"
    fi

# remove me, when fixed; DISPLAYPI currently not used
displaypi=offline
	
#transfer data for displaypi - if online
if [ "$displaypi" = "online" ]; then
        echo $timestamp_rounded_unix, water $water, air $air, roof $roof, flow $flow, return $return_t, device $device, pump_flag $pump_db_value, heatflag $heat_db_value >interface.out
        scp interface.out pi@$displaypi_ip:/production
        echo I107 $timestamp_real interface file for displaypi transferred >>$logfile
#       scp tempday_320240.png pi@displaypi.local:/home/pi
#       ssh -l pi displaypi.local "con2fbmap 1 1 & ~/show_pooltemp.sh"
#       echo I107 $timestamp_real graphic for raspi display transferred >>$logfile
fi
log_info "$FUNCNAME $LINENO"

# determine internet connection & speed
wget -q --tries=1 --timeout=10 --delete-after http://google.com
if [[ $? -eq 0 ]]; then
		log_info "$FUNCNAME $LINENO"
        wget http://$subdomain/img/dummy --tries=1 --timeout=10 --delete-after 2> speedtest.out
        speed=$(grep saved speedtest.out |cut -d' ' -f3|cut -d'(' -f2)
        speedunit="$(grep saved speedtest.out |cut -d' ' -f4|cut -d')' -f1)"
#"
      	log_info "$FUNCNAME $LINENO $speed $speedunit"
		if [ "$speedunit" = "B/s" ]; then
			internet=offline
			log_info "$FUNCNAME $LINENO"
			log_error "$FUNCNAME $LINENO $timestamp_real Internet slooooow $speed $speedunit - set script to offline" 
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
        if [ "$speedunit" = "MB/s" ]; then
			internet=online
			log_info "$FUNCNAME $LINENO Internet online and >50KB/s, that is $speed $speedunit"
        fi
else
        log_error "$FUNCNAME $LINENO did not reach Google, internet down"
        internet=offline
fi

# transfer files if internet is online
if [ "$internet" = "online" ]; then
    scp tempday.png tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/$subdomain/img
    log_info "$FUNCNAME $LINENO graphics for daily statistics tempday transferred to homepage"

    scp temp7d.png tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/$subdomain/img
    log_info "$FUNCNAME $LINENO graphics for current week transferred to homepage"

    scp tempmo.png tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/$subdomain/img
    log_info "$FUNCNAME $LINENO graphics for current month transferred to homepage"

    scp current_temp.json tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/$subdomain
    log_info "$FUNCNAME $LINENO current temp data transferred to homepage"

	if [ -e current_month_0.json ]; then
	  scp -C current_month_?.json tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/test.tober-kerken.de/php/data
	  scp -C current_week_?.json tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/test.tober-kerken.de/php/data
	  scp -C current_day_?.json tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/test.tober-kerken.de/php/data
	fi
	if [ -e current_month_classic_0.opt ]; then
	  scp -C current_month_classic_?.opt tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/test.tober-kerken.de/php/data
	  scp -C current_week_classic_?.opt tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/test.tober-kerken.de/php/data
	  scp -C current_day_classic_?.opt tober-kerken@h2144881.stratoserver.net:/var/www/vhosts/tober-kerken.de/test.tober-kerken.de/php/data
	fi
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
