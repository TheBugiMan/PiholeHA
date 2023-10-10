#!/bin/bash
# This file contains all common functions called to main script to keep things 'clean'

# help menu
function helpoptions {
    echo "Pi-hole HA support script"
    echo ""
    echo "This script is built to mirror DHCP configuration from a active PiHole instance and copy to a holding location on standby instance."
    echo "In the event that the primary instance in unavailable, it will activate the configuration it has duplciated to maintain leases."
    echo "DHCP configuration is statically configure in script. DNS/Blackhole synchronisation is maintained by GravitySync."
    echo ""
    echo "  $0 [options]"
    echo ""
    echo " --debug       provide debug output"
    echo ""
    exit 0
}


# manage script end
#  relies on
#     - %healthcheckuri%
function exit_success {
    # phone home to healthcheck.io to confirm successful run if configured
    if [ "$ifttt_enable" == "true" ] ; then
        if [ -n "$healthcheckuri" ] ; then
            echo ""
            echo Polling Healthcheck to confirm run...
            curl -s -m 10 --retry 5 $healthcheckuri
            echo ""
            echo "===================================="
        else
            echo Healthcheck polling enabled but no URI! Please update config.
        fi
    fi

    # goodbye
    exit 0
}


# count the pings to partner
#  updates
#     - %count% with number of successful pings
#  relies on
#     - %countping% for number of pings
#     - %target% as target device to ping
function partnerping {
    count=$( ping -c ${countping} -W 1 $target | grep time= | wc -l )
}


# function to call Pi-hole API on a device and determine state
#  updates
#     - %checkvalue% for nul value compare on failure
#  relies on
#     - %testtarget% to do API call against
function pihole_apitest {
    # explicitly clear to ensure 'clean' testing env
    checkvalue=
    checkstate=

    # pulls api status for parsing many times
    # Identify if polling local instance or remote and use appropriate key
    if [ "$testtarget" == "127.0.0.1" ]; then
        APIkey=$localAPIkey
    else
        APIkey=$targetAPIkey
    fi

    # if no API key provided, assume one not required. This will most likely fail in recent pihole versions
    if [ ! -z "$APIkey" ] ; then
        checkprobe_raw=$(curl -s http://${testtarget}/admin/api.php?status\&auth=${localAPIkey})
    else
        checkprobe_raw=$(curl -s http://${testtarget}/admin/api.php?status)
    fi

    #debug print status string
    if [ ! -z "$piholeha_debug" ] ; then echo "${checkprobe_raw}" ; fi

    # check to see got values, if '[]' assume auth key incorrect
    if [ "$checkprobe_raw" == "[]" ] ; then
        checkvalue=INVALID
        return
    fi

    # check to see if blocking is enabled or disabled
    checkprobe_status=$(jq -r '.status' <<< "$checkprobe_raw")
    case $checkprobe_status in
        enabled)
            if [ ! -z "$piholeha_debug" ] ; then echo "Pi-hole ${testtarget} status enabled" ; fi 
            checkstate="enabled";;
        disabled)
            if [ ! -z "$piholeha_debug" ] ; then echo "Pi-hole ${testtarget} status disabled" ; fi 
            checkstate="disabled";;
        *)
            if [ ! -z "$piholeha_debug" ] ; then echo "Pi-hole ${testtarget} status unknown - ${checkprobe_status}" ; fi
            checkstate="BAD" ;;
    esac

    # check FTL status
    partnerprobe_ftl=$(jq -r '.FTLnotrunning' <<< $partnerprobe_raw)
    case $checkprobe_ftl in
        true)
            if [ ! -z "$piholeha_debug" ] ; then echo "Pi-hole ${testtarget} FTL not functioning" ; fi 
            # some example calls I have seen it disabled as FTL not running. This is to catch those cases though seems deprecated API response now
            if [ "$checkstate" == "disabled" ] ; then checkstate="BAD" ; fi 
            ;;
        *)
            if [ ! -z "$piholeha_debug" ] ; then echo "Pi-hole ${testtarget} FTL running ${partnerprobe_ftl}" ; fi ;;
    esac

    # sanatised version for checking. zero length indicates failure
    checkvalue=$(echo $checkstate)
}


# run selftest (this is on the Pi-hole instance that will take over in case the main one is offline/in error state)
#  updates
#     - %selfcheck% sanitised for nul compare
function selftest {
    testtarget=127.0.0.1
    pihole_apitest
    selfcheck=$(echo $checkvalue)
}


# check for partner active state
#  relies on
#     - %target% as target device to poll
#  updates
#     - %partnercheck% sanitised for nul compare
function partneractivetest {
    testtarget=$target
    pihole_apitest
    partnercheck=$(echo $checkvalue)
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
    curl -s --retry 5 https://maker.ifttt.com/trigger/$ifttt_trigger/with/key/$ifttt_token?state=$notificationmessage
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
    echo "Enable DHCP on local Pi-hole instance..."
    if [ ! -z "$piholeha_debug" ] ; then echo "executing ${pihole_app} -a enabledhcp ${piholedhcpparam}" ; fi
    sudo $pihole_app -a enabledhcp ${piholedhcpparam}
    echo "...Done!"
}


# Disable DHCP on local PiHole instance
function dhcp_disable {
    echo ""
    echo "Disabling DHCP on local Pi-hole instance..."
    if [ ! -z "$piholeha_debug" ] ; then echo "executing ${pihole_app} -a disabledhcp ${piholedhcpparam}" ; fi
    sudo $pihole_app -a disabledhcp
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
    piholedhcpparam="${dhcpscope_min} ${dhcpscope_max} ${dhcprouter} ${dhcp_lifetime} ${dhcpdomain}"
    # debug output
    if [ ! -z "$piholeha_debug" ]
    then
        echo "Configuration parsed from primary Pi-hole instance backup"
        echo "DCHP Domain: $dhcpdomain"
        echo "Default Gateway: $dhcprouter"
        echo "DHCP Scope Min: $dhcpscope_min"
        echo "DHCP Scope Max: $dhcpscope_max"
        echo ""
        echo "PiHole DHCP config string: ${piholedhcpparam}"
        echo ""
    fi
}


# this function is to validate configuration file
function ConfigFileCheck {

    # ---------------------------
    # check for valid ping counts
    #ensure we have a non-zero ping count
    if [ ! -z "$countping" ]
    then
        echo no valid number of pings to send. defaulting to 3
        countping = 3
    fi
    
    #ensure we have a non-zero number of pings expected
    if [ ! -z "$expectping" ]
    then
        echo no valid number of expected pings. defaulting to ${countping}
        countping = $countping
    fi
    
    # ensure to expect same or less responses than we requested
    if [ $countping -lt $expectping ] 
    then
        echo expectping is invalid/larger than countpint. Resetting to same
        expectping = $countping
    fi

}


# if configuration file doesn't exist, create a template for users
function BuildDefaultConfig {
    cat << EOF > $configfile
#!/bin/bash
# This file contains all the configuraiton that is best kept away from prying eyes

# delete or change this line once you have configured the settings. The script will not run otherwise
sampleconfig=true

# target IP or DNS of 'primary' Pi-hole, & friendly name of monitored Pi-hole
#   target is ip/DNS of 'primary' instance
#   targetname is friendly name of device shown in logs/output
target=CHANGEME.local
targetname=PiHole

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

# User to connect to target Pi-hole as. Same requirements as Gravity-Sync requirement so same user is ideal.
#  - SSH key authentication to be used
#  - Configured as paswordless sudo
syncuser=pi

# Simple GET request for to confirm successful run of script
#   URI to enable, blank disables
# Compatible with HealthCheck.io or Uptime Kuma
healthcheckuri=https://hc-ping.com/CHANGEME

# User notifications
# -----
# Telegram
telegram_enable=false
telegram_key=CHANGEME:CHANGEME
telegram_groupid=CHANGEME
# IFTTT
ifttt_enable=false
ifttt_trigger=CHANGEME
ifttt_token=CHANGEME    
EOF
}