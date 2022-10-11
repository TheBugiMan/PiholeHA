to expand....
* Gravity Sync (link)
* Copy/install script
* Crontab steps

## Requirements

### PiHole
This set up requires (despite the obviousness) two instances of PiHole running on whatever chosen platform. One instance to be delegated as 'master' or primary where configuration changes are made, then the slave or backup instance that will be retrieving it's configuration from the primary through this script (and GravitySync)

### GravitySync
While not technically a requirement for the script to work, does enable two PiHole instances to sync relevent data between them

### Passwordless sudo
User running the script requires passwordless sudo access due to changing files in DNSmasq etc directory

## Installation

## Pihole
Installation process will depend on platform. See http://pi-hole.net

## Gravity Sync (optional)
https://github.com/vmstan/gravity-sync