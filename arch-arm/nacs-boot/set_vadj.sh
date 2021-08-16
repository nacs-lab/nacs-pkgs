#!/bin/bash

UCD='/sys/devices/soc0/amba/e0004000.i2c/i2c-0/i2c-8/8-0035/hwmon/hwmon1'
echo 3500 > $UCD/in2_crit
echo 3400 > $UCD/in2_max
echo 3450 > $UCD/in2_vout_max
echo 3300 > $UCD/in2_vout_cmd
echo 3200 > $UCD/in2_min
echo 3100 > $UCD/in2_lcrit
echo "VADJ = $(cat $UCD/in2_input) mV"
