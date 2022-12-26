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

function flag_dhcpon {
    echo ""
    echo "Generating lock file for DHCP state"
    touch ${dir}/dhcp.on
    echo "...Done!"
}

function flag_dhcpoff {
    echo ""
    echo "Clearing lock file..."
    rm -f ${dir}/dhcp.on
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
    #rsync -ai ${syncuser}@${target}:/etc/dnsmasq.d/* ${dir}/dnsmasq/ #anything dnsmasq seems to be covered by GravitySync now
    #rsync -ai ${syncuser}@${target}:/etc/pihole/* ${dir}/pihole  #FTL DB too big to sync this way, plus already managed through GravitySync
    
    # sync active DHCP leases, wrapped to detect any file changes
    # this may be removed in future depending on outcomes of testing
    RSYNC_COMMAND=$(rsync -ai ${syncuser}@${target}:/etc/pihole/dhcp.leases ${dir}/pihole)

    if [ $? -eq 0 ]; then
        # Success do some more work!

        if [ -n "${RSYNC_COMMAND}" ]; then
            # Stuff to run, because rsync has changes

            # @@ set flag to refresh DNSmasq with SIGHUP or restart FTL?
        else
            # No changes were made by rsync
        fi
    else
        # Something went wrong!
        exit 1
    fi
}

# Enable DHCP on local PiHole instance
function piholedhcp_enable {
    echo ""
    echo "Enable DHCP on local PiHole instance..."
    $pihole_app -a enabledhcp $piholedhcpparam
    echo "...Done!"   
}
# Disable DHCP on local PiHole instance
function piholedhcp_disable {
    echo ""
    echo "Disabling DHCP on local PiHole instance..."
    $pihole_app -a disabledhcp
    echo "...Done!"   
}