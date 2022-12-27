#!/bin/bash
# This file contains all the configuraiton that is best kept away from prying eyes

# target IP/DNS & friendly name of monitored Pi-hole
target=pihole.local
targetname=pi-hole

# how many pings to test against target (3 should be sufficent)
countping=3

# User to connect to target Pihole as. Same requirements as Gravity-Sync requirement so same user is ideal.
#  - SSH key authentication to be used
#  - Configured as paswordless sudo
syncuser=pi

# HealthCheck.io Integration
#   URI/UUID to enable, blank disables
healthcheckuri=https://hc-ping.com/CHANGEME
# User notifications
# -----
# Telegram
telegram_enable=false
telegram_key=CHANGEME:CHANGEME
telegram_groupid=-CHANGEME
# IFTTT
ifttt_enable=false 
ifttt_trigger=CHANGEME
ifttt_token=CHANGEME