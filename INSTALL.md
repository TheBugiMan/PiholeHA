## Requirements

### PiHole
This set up requires (despite the obviousness) two instances of PiHole running on whatever chosen platform. One 
instance to be delegated as 'master' or primary where configuration changes are made, then the slave or backup 
instance that will be retrieving it's configuration from the primary through this script (and GravitySync)

### GravitySync
While not technically a requirement for the script to work, does enable two PiHole instances to sync relevent 
data between them

### Remote login user
User running the script requires passwordless sudo access and key authentication on the remote/primary device. 
This is used for pulling files in DNSmasq etc directory to local copy for backup.
If you are already using Gravity Sync, the user created for that has the same requirements and so can be used 
here as well

On standby instance
1. type "ssh-keygen"
2. type "ssh-copy-id user@192.168.1.3" <- type user to sync with and IP of primary Pi-hole, this IP is specific 
to your network, 192.168.1.3 is an example only
3. type "yes" - YOU MUST TYPE "yes", not "y"
4. type the password of your secondary pihole


### jq
jq (json query shell app) while becoming more common to be installed 'by default' may not be in all instances. 
This little app is used to parse the Pi-hole API results to determine application state

### curl
App used to scrape API data for Pi-hole. Almost certainly pre-installed but listed here for completness.

## Installation

## Pihole

### The App
Installation process will depend on platform. See http://pi-hole.net

### HA DNS
if you want the DNS to hit both servers (which is the assumption since you are aiming for HA DHCP), on the 
primary instance of Pi-hole, you will need to add the IP address of the secondary pi-hole server. Alternative 
option is to have very short DHCP lease times however that is additional load and complexity on servers.

This round-robin DNS can be achieved by adding additional file (e.g. `03-pihole-dhcp-DNS.conf`) under 
`/etc/dnsmasq.d/` similar to the following (where 192.168.0.2 and 192.168.0.3 are your two pihole servers);
```
dhcp-option=6, 192.168.0.2, 192.168.0.3
```

## Gravity Sync (optional)
https://github.com/vmstan/gravity-sync

## This script
This is a bit rough and ready but

### Copy files
Copy _all_ script files to a directory. This includes configuration and function includes.
NB: The script does cater for missing configuration file and when detected will create a new one and warn the user.

### Schedule script to run on regular interval
Eventually will be looking to integrate this into a 'install' script or automated process within the script/app 
itself but for time being it is a manual process. Crontab user must have access to pihole/dnsmasq configuration 
directories for r/w operations.

1. type "crontab -e"
2. scroll to the bottom of the editor, and on a new blank line enter entry
3. save and exit

Example crontab entry would be
```
*/5 * * * * /home/pihole-gs/pihole-ha.sh >> /home/pihole-gs/pihole-ha.log 2>&1
```

Note that this example includes sending output to a log. Again an improvement item is to have this contained within 
the app. At the moment additional `logrotated` configuration is then required to support this.

Example for e.g. `/etc/logrotate.d/pihole-ha`
```
/home/pihole-gs/pihole-ha.log {
	rotate 7
	daily
	compress
	delaycompress
	notifempty
	extension log
	dateext
	su pihole-gs pihole-gs
	create 0664 pihole-gs sudo
}
```