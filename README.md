# PiHole-HA

## What is this?
This script is designed to be run on a secondary instance of PiHole at regular intervals
(eg via Crontab) and sync configuration from a primary Pi-hole instance. On detection of primary 
failure, this script activates DHCP with last known leases and reservations backed up from primary.

It also has notification functionality built in via Telegram and IFTTT and (should, DNS resolution 
not-with-standing) send notifications on failure and restoration of primary PiHole instance.

## Standing on the shoulders of Giants.

This script's initial instance is built on and inspired by the following work
* https://discourse.pi-hole.net/t/good-solution-to-automatically-revert-to-normal-if-pi-hole-dies/10059/4
* https://www.reddit.com/r/pihole/comments/9gw6hx/sync_two_piholes_bash_script/

There have been a lot of changes since then, but wouldn't have even been able to start without these!

## Installation

See INSTALL.md

## Configuration

User-based configuration options are pulled out into a separate file, `pihole-ha-conf.sh` to enable easy 
access and separate possible private secrets.

This file is self documenting to help people through what needs to be configured. Bare minimum change would
be to change the `target` value which is the IP (or DNS but _highly_ recommend sticking with IP) address of
partner/primary Pi-hole server. 

## ToDo / Enhancements

1) integrate logging into script and to /var/log instead of within Cron call
2) Options to add/remove/adjust logrotate
3) Options to add/remove/adjust crontab
4) Check response back from push notification to see if successful
    * Telegram JSON response includes "ok":true or "ok":false
5) Automate addition of two DNS servers on primary pi-hole instance
6) set aggressiveness of failover (eg. none, hard down, primary unstable/unknown)
7) test-only cmd option to check health of primary and standby pihole instances