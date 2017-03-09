#/bin/bash

#Skript zum programmatischen Abschalten der PiUSV+
#gpio-tools müssen installiert sein
#Autor: raspiuser, 2015-08-10
#Benutzung auf eigenes Risiko !
#i2c-tools required: sudo apt-get install i2c-tools

echo "$(date +%Y-%m-%d" "%H:%M:%S) [NOTICE] Programmatic system shutdown!"|sudo tee -a /var/log/piupsmon.log
sudo /etc/init.d/piupsmon stop
sudo init 0 &
sudo i2cset -y 1 0x18 0x10
sudo i2cset -y 1 0x18 15
echo "$(date +%Y-%m-%d" "%H:%M:%S) [NOTICE] System halted!" |sudo tee -a /var/log/piupsmon.log

