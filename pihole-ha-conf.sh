#!/bin/bash
# This file contains all the configuraiton that is best kept away from prying eyes

# delete or change this line once you have configured the settings. The script will not run otherwise
sampleconfig=true

# target IP/DNS & friendly name of monitored Pi-hole
#   target is ip/DNS of 'primary' instance
#   targetname is friendly name of device shown in logs/output
target=pihole.local
targetname=pi-hole

# API keys for local and remote PiHole instances. used for health/status checks
# Please note the script gracefully handles empty strings and will not attempt to auth if no key provided
#   however modern versions of Pihole are now enforcing API auth so status polling will likely fail
targetAPIkey=CHANGEME
localAPIkey=CHANGEME

# how many pings to test against target. 3 should be ample.
# pings to send
countping=3
# minimum expected to consider connection 'good'. In 99% of networks, this should be the same as above
expectping=3

# User to connect to target Pihole as. Same requirements as Gravity-Sync requirement so same user is ideal.
#  - SSH key authentication to be used
#  - Configured as paswordless sudo
syncuser=pi

# HealthCheck.io Integration
#   URI to enable, blank disables
#healthcheck_enable=false #not yet configured
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