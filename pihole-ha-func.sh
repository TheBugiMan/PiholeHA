#!/bin/bash
# This file contains all common functions called to main script to keep things 'clean'

# help menu
function helpoptions {
    echo "PiHole HA support script"
    echo ""
    echo "This script is built to mirror DHCP configuration from a active PiHole instance and copy to a holding location on standby instance."
    echo "In the event that the primary instance in unavailable, it will activate the configuration it has duplciated to maintain leases."
    echo "DHCP configuration is statically configure in script. DNS/Blackhole synchronisation is maintained by GravitySync."
    echo ""
    exit 0
}

# manage script end
#  relies on
#     - %healthcheckuri%
function exit_success {
    # phone home to healthcheck.io to confirm successful run if configured
    if [ -n "$healthcheckuri" ] ; then
        echo ""
        echo Polling Healthcheck to confirm run...
        curl -s -m 10 --retry 5 $healthcheckuri
        echo ""
        echo "===================================="
    fi

    # goodbye
    exit 0
}

# run selftest (this is on the Pi-hole instance that will take over in case the main one is offline/in error state)
#  updates
#     - %selfprobe1%
#     - %selfcheck1%
function selftest {
    selfprobe1=$(curl -s http://127.0.0.1/admin/api.php?status | grep "enabled")
    selfcheck1=$(echo $selfprobe1)
}

# count the pings to partner
#  updates
#     - %count% with number of successful pings
#  relies on
#     - %countping% for number of pings
#     - %target% as target device to ping
function partnerping {
    count=$( ping -c ${countping} -w 3 $target | grep time= | wc -l )
}

# check for partner active state - Active
#  relies on
#     - %target% as target device to poll
#  updates
#     - %partnerprobe1% raw data after grep
#     - %partnercheck1% sanitised for nul compare
function partneractivetest {
    partnerprobe1=$(curl -s http://${target}/admin/api.php?status | grep "enabled")
    partnercheck1=$(echo $partnerprobe1)
}

# different methods of sending notification
function sendnotification {
    echo ""
    echo "Sending notification..."
    if [ "$ifttt_enable" == "true" ] ; then sendnotification_ifttt ; fi
    if [ "$telegram_enable" == "true" ]  ; then sendnotification_telegram ; fi
    echo "... done!"
}
function sendnotification_telegram {
    curl -s --retry 5 --data "text=$notificationmessage" --data "chat_id=$telegram_groupid" 'https://api.telegram.org/bot'$telegram_key'/sendMessage'
}
function sendnotification_ifttt {
    curl -s --retry 5 https://maker.ifttt.com/trigger/pihole_ha/with/key/$ifttt_token?state=$notificationmessage
}

# create file to flag DHCP has been activated
function flag_dhcpon {
    echo ""
    echo "Generating lock file for DHCP state"
    touch ${dir}/dhcp.on
    echo "...Done!"
}

# remove file to flag DHCP has been deactivated
function flag_dhcpoff {
    echo ""
    echo "Clearing lock file..."
    rm -f ${dir}/dhcp.on
    echo "...Done!"
}

# Enable DHCP on local PiHole instance
function dhcp_enable {
    # copy last backup of leases to this instance
    if [ ! -z "$piholeha_debug" ] ; then echo "Copying config/leases to active instance" ; fi
    dhcp_copyconf
    
    # build DHCP options from backup
    dhcp_parseconf

    # enable DHCP on local standby instance 
    echo ""
    echo "Enable DHCP on local PiHole instance..."
    $pihole_app -a enabledhcp $piholedhcpparam
    echo "...Done!"
}
# Disable DHCP on local PiHole instance
function dhcp_disable {
    echo ""
    echo "Disabling DHCP on local PiHole instance..."
    $pihole_app -a disabledhcp
    echo "...Done!"   
}

# copy DNSmasq configuration from backup location to live configuration
function dhcp_copyconf {
    #cp ${dir}/dnsmasq/02-pihole-dhcp.conf /etc/dnsmasq.d/ # don't believe this is required?
    #cp ${dir}/dnsmasq/03-pihole-dhcp-DNS.conf # no need to activate redundant DNS server config as only one instance currently active
    #cp ${dir}/dnsmasq/04-pihole-static-dhcp.conf /etc/dnsmasq.d/ # managed with GravitySync
    #cp ${dir}/dnsmasq/05-pihole-custom-cname.conf /etc/dnsmasq.d/ # managed through GravitySync

    #copy existing leases
    cp ${dir}/pihole/dhcp.leases /etc/pihole/
}

# import DNSmasq configuration from partner PiHole instance
function dhcp_backupconf {
    # copy dnsmasq config, primarily for DHCP scope information for activating on local instance when required
    rsync -ai ${syncuser}@${target}:/etc/dnsmasq.d/* ${dir}/dnsmasq/
    #FTL DB too big to sync this way, plus already managed through GravitySync
    #rsync -ai ${syncuser}@${target}:/etc/pihole/* ${dir}/pihole  
    
    # sync active DHCP leases, wrapped to detect any file changes
    RSYNC_COMMAND=$(rsync -ai ${syncuser}@${target}:/etc/pihole/dhcp.leases ${dir}/pihole)

    if [ -n "${RSYNC_COMMAND}" ]
    then
        # rsync has changes
        if [ ! -z "$piholeha_debug" ] ; then echo "Changes in dnsmasq files detected and synced" ; fi
        # possibly in future set flag to refresh DNSmasq with SIGHUP or restart FTL?
        #   would be required to try and resolve current DHCP leases on other pi, rely on GravitySync and client database?
    else
        # No changes were made by rsync
        if [ ! -z "$piholeha_debug" ] ; then echo "No changes in dnsmasq files" ; fi
    fi
}

# This parses configuration from DNSMASQ to compile values required to enable DHCP on pihole CLI
#    currently unimplemented/incomplete
function dhcp_parseconf {
    # read line from dnsmasq from file for the domain name
    dhcpdomain_raw=$(cat ${dir}/dnsmasq/02-pihole-dhcp.conf | grep domain=)
    # break it into an array with '=' delimiter
    IFS="=" read -a dhcpdomain_array <<< $dhcpdomain_raw
    # take second value (0 indexed) which is the value we want
    dhcpdomain=${dhcpdomain_array[1]}

    # read line from dnsmasq from file for the default gateway (router)
    dhcprouter_raw=$(cat ${dir}/dnsmasq/02-pihole-dhcp.conf | grep option:router)
    # break it into an array with '=' delimiter
    IFS="," read -a dhcprouter_array <<< $dhcprouter_raw
    # take second value (0 indexed) which is the value we want
    dhcprouter=${dhcprouter_array[1]}

    # read line from dnsmasq from file for the DHCP scope
    dhcpscope_raw=$(cat ${dir}/dnsmasq/02-pihole-dhcp.conf | grep dhcp-range=)
    # break it into an array with '=' delimiter, this gives us the options
    IFS="=" read -a dhcpscope_array1 <<< $dhcpscope_raw
    # break it into another array with ',' delimiter, this gives us the min, max and lifetime
    IFS="," read -a dhcpscope_array2 <<< ${dhcpscope_array1[1]}
    # pull the wanted values
    dhcpscope_min=${dhcpscope_array2[0]}
    dhcpscope_max=${dhcpscope_array2[1]}

    # build parameter to pass to PiHole to activate DHCP
    piholedhcpparam="'${dhcpscope_min}' '${dhcpscope_max}' '${dhcprouter}' '${dhcp_lifetime}' '${dhcpdomain}'"

    # debug output
    if [ ! -z "$piholeha_debug" ]
    then
        echo "Configuration parsed from primary PiHole instance backup"
        echo "DCHP Domain: $dhcpdomain"
        echo "Default Gateway: $dhcprouter"
        echo "DHCP Scope Min: $dhcpscope_min"
        echo "DHCP Scope Max: $dhcpscope_max"
        echo ""
        echo "PiHole DHCP config string: ${piholedhcpparam}"
        echo ""
    fi
}