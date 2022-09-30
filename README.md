# PiHole-HA

## Standing on the shoulders of Giants.

This script is built on and inspired by the following work
* https://discourse.pi-hole.net/t/good-solution-to-automatically-revert-to-normal-if-pi-hole-dies/10059/4
* https://www.reddit.com/r/pihole/comments/9gw6hx/sync_two_piholes_bash_script/

## Installation

to expand....
* Gravity Sync (link)
* Copy/install script
* Crontab steps

## ToDo / Enhancements

1) implement application checks against API web interface instead of admin interface
 /admin/api.php?status
    * bad state --> {"status":"disabled","FTLnotrunning":true}
    * good state --> {"status":"enabled"}
    * use JQ?
    *    https://stedolan.github.io/jq/tutorial/
    *    https://stackoverflow.com/questions/37926463/parse-json-string-in-bash
    * use BASH? Not best option
    *    https://unix.stackexchange.com/questions/531938/parse-a-string-in-bash-script#531943

2) integrate logging into script and to /var/log instead of within Cron call
3) Options to add/remove/adjust logrotate
4) Options to add/remove/adjust crontab
5) Check response back from push notification to see if successful
    * Telegram JSON response includes "ok":true or "ok":false
