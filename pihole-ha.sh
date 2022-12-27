#!/bin/bash

# This script is designed to be executed via cron on standby pihole instance

# User configurable options
# ----------------------------

# Configuration more likely to change is located in "pihole-ha-conf.sh" file that contains
# user credentials for notification services as well as details of 'master' PiHole instance
# Most configuration here would not need to be changed and are more 'hacky' waiting 
# for more smarter / dynamic ways to implement what they state.

# lifetime of DHCP leases when issued by 'backup' pihole instance
# number specified here is in hours. Recommend to keep shorter to allow for faster failing back to 2 DNS servers
dhcp_lifetime=1

# Location of pihole executable
#  specified as originally hacing issues executing pihole commands like 'restart'
#  could likely be improved but for time being it works!
pihole_app=/usr/local/bin/pihole

# folder where we store files
#dir=/home/pihole-gs # defaults to where script is running
#logfile=$dir/piholeha.log # log output managed in cron and logrotate.d
#logfileerr=/var/log/piholeha-err.log #future use
#logfilestd/var/log/piholeha.log #future use

# configuration file to import environment-specific settings.
# possibly for future use to allow changing from CLI?
configimport=pihole-ha-conf.sh

# servername to use in logs for current (backup) instance
# by default use hostname
servername=$(hostname)


# Start of script! Nothing to see down here...
# ------------------------------

# debug flag. if unset, debug is not active. changed by command line option
piholeha_debug=

# set debug mode if requested
if [ "$1" = "--debug" ] ; then
    piholeha_debug=true
fi

# finds directory of the script
dir="${BASH_SOURCE%/*}"
if [[ ! -d "$dir" ]]; then dir="$PWD"; fi

# import required functions
. "$dir/pihole-ha-func.sh"

# capture request for help/info
if [ "$1" == "--help" ] ; then
    helpoptions 
fi
if [ "$1" == "-h" ] ; then 
    helpoptions
fi
if [ "$1" == "/?" ] ; then
    helpoptions
fi

# checks if config file exists and if not creates a 'template'
configfile="${dir}/${configimport}"
if [ ! -z "$piholeha_debug" ] ; then echo "Using config file ${configfile}" ; fi

if [ ! -e ${configfile} ]
then 
    BuildDefaultConfig
    echo "Template configuration has been created at ${configfile}"
    echo "This script will not run until this has been updated"
    exit 1
fi

# imports the required dependent conf script (Secrets, IPs, etc)
. "$dir/pihole-ha-conf.sh"

if [ "$sampleconfig" == "true" ]
then
    echo "Detected sample/template configuration. ${configfile}"
    echo "Please make any required changes to the configuration and try again."
    exit 1
fi

#heading
echo ""
echo "======================================"
echo Pi-hole HA sync update for ${servername}
date
echo "--------------------------------------"


# check local status
# -------------------------------------------------------------
echo ""
echo "Performing self-test to confirm health..."
selftest
if [ ! -z "$piholeha_debug" ] ; then echo "${selfprobe1}" ; fi
echo "...Done!"

if [ -z "$selfcheck" ]
then
    if [ -e ${dir}/FTL.err ]
    then
        echo "...FTL error file present. Exiting!"
        exit_success
    else 
        echo "...Local FTL in error state."
        echo ""
        echo "Running additional check ..."
        sleep 2
        selftest
        if [ -z "$selfcheck" ]
        then
            echo "...FTL still in error mode."
            echo ""
            echo "Creating lock file for local error state..."
            touch ${dir}/FTL.err
            echo ""
            
            # send notification
            notificationmessage="Internet redundancy failure for Pi-hole"
            sendnotification
            exit_success
        else
            echo ""
            echo "Second check. FTL up and running."
        fi
    fi
else
    echo "...Local FTL up and running!"
    echo ""
    if [ -e ${dir}/FTL.err ]
    then
        echo "Clearing local error lock file..."
        rm -f ${dir}/FTL.err
        echo "...Done!"
        
        # send notification
        notificationmessage='Internet redundancy resolved for Pi-hole'
        sendnotification
    else
        # if in debug, explicit notification
        if [ ! -z "$piholeha_debug" ] ; then echo "FTL flag file doesn't exist. No action performed." ; fi
    fi
fi
# -------------------------------------------------------------


# check partner status - ping
# -------------------------------------------------------------
echo ""
echo "Performing ping test to remote Pihole instance at ${targetname}..."
partnerping
if [ ! -z "$piholeha_debug" ] ; then echo "${count}" ; fi
echo "...Done!"

# detect if number of returned pings are less than what was requested
if [ $count -lt $countping ] 
then
    
    # provide feedback regarding the number of pings lost
    if [ $count -eq 0 ]
    then
        echo "${targetname} is not pinging!"
    else
        echo "${targetname} is not reliable! $count of $countping pings replied"
    fi
    
    # determine if already in failover state or if need to set flag and fail over
    if [ -e ${dir}/dhcp.on ]
    then
        echo ""
        echo "DHCP server already enabled. No changes or notifications performed."
        exit_success
    else
        # activate DHCP server
        dhcp_enable
        
        # create flag file to inform subsequent runs already failed over
        flag_dhcpon

        # send notification
        notificationmessage='Internet failover for Pi-hole has started'
        sendnotification
    fi
else
    # if in debug mode explicitly notify
    if [ ! -z "$piholeha_debug" ] ; then echo "${targetname} is responding to pings" ; fi

    # we do not clear any error states here until passes application tests
fi
# -------------------------------------------------------------



# check partner status - app status
# -------------------------------------------------------------
echo ""
echo "Performing application tests to remote Pi-hole instance at ${targetname}..."
partneractivetest
if [ ! -z "$piholeha_debug" ] ; then echo "${partnerprobe1}" ; fi
echo "...Done!"

# detect if check failed
if [ -z "$partnercheck" ]
then
    # if in debug mode explicitly notify
    if [ ! -z "$piholeha_debug" ] ; then echo "${targetname} is NOT operational" ; fi

    if [ -e ${dir}/dhcp.on ]
    then
        echo "DHCP server already enabled. No changes or notifications performed."
        exit_success
    else
        echo "${targetname} is not in a good state!"

        # create flag file to inform subsequent runs already failed over
        flag_dhcpon

        # activate DHCP server
        dhcp_enable

        # send notification
        notificationmessage='Internet failover for Pi-hole has started'
        sendnotification
    fi

else
    # if in debug mode explicitly notify
    if [ ! -z "$piholeha_debug" ] ; then echo "${targetname} is operational" ; fi

    if [ -e ${dir}/dhcp.on ]
    then
        echo "${targetname} is Alive!"

        # deactivate DHCP server
        dhcp_disable      

        # clear dhcp active flag
        flag_dhcpoff

        # send notification
        notificationmessage='Internet failover for Pi-hole has finished'
        sendnotification
    else
        # if in debug, explicit notification
        if [ ! -z "$piholeha_debug" ] ; then echo "DHCP flag file doesn't exist. No action performed." ; fi
    fi

    echo ""
    echo "Sync from primary Pi-hole instance ${targetname}..."
    # pull current leases off primary pihole
    dhcp_backupconf
    echo "...done!"

fi
# -------------------------------------------------------------

# if script didn't bomb out, exit nicely and poll healthcheck.io instance to confirm successful run
exit_success