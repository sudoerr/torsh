#!/bin/bash

# ===============================================================
# TinyTunnel, Transparent Tor proxy for full system TCP traffic
# ===============================================================

# Config

#!INFO ----------------------------------------------------------------
# id -u tor gets id of user "tor", which means the username "tor"
# must be owner of process -who runs tor-, if you install tor
# using any package manager, the chance that it has handled
# user creation automatically is high, otherwise you should
# add a new user yourself. the automatic username for tor
# service for systemctl in arch is tor and in debian is
# debian-tor
# ---------------------------------------------------------------------

#!INFO ----------------------------------------------------------------
# Also make sure you have configured torrc correctly, Configs below
# are necessary for correct startup :

# User tor
# VirtualAddrNetwork 10.192.0.0/10
# AutomapHostsOnResolve 1
# TransPort 9040
# DNSPort 5353
# ---------------------------------------------------------------------


TOR_USER="tor"
TOR_UID=$(id -u $TOR_USER)
TRANS_PORT=9040
DNS_PORT=5353
NON_TOR_NETS=("192.168.0.0/16" "10.0.0.0/8" "172.16.0.0/12" "127.0.0.0/8")


backup_iptables() {
    IPTABLES_BACKUP="/tmp/iptables.backup.$(date +%s)"
    iptables-save > "$IPTABLES_BACKUP"
    echo "Saved current iptables to $IPTABLES_BACKUP"
}


disable_ipv6() {
    # Disable IPv6 temporarily
    echo -e "Disabling IPv6 temporarily..."
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null
    sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1 > /dev/null
}


enable_ipv6() {
    echo -e "Enabling IPv6 again..."
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null
    sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0 > /dev/null
}


set_iptables_rules() {
    echo -e "Setting iptables rules..."

    # Flush current NAT rules
    iptables -F
    iptables -t nat -F
    # Exempt Tor process
    iptables -t nat -A OUTPUT -m owner --uid-owner "$TOR_UID" -j RETURN
    # Redirect DNS (both UDP & TCP) to Tor DNSPort
    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $DNS_PORT
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $DNS_PORT
    # Exempt local/non-Tor networks
    for NET in "${NON_TOR_NETS[@]}"; do
        iptables -t nat -A OUTPUT -d "$NET" -j RETURN
    done
    # Redirect all new TCP connections to Tor TransPort
    iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports $TRANS_PORT


    # Filter rules (optional safety)
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    # Allow traffic to non-Tor networks
    for NET in "${NON_TOR_NETS[@]}"; do
        iptables -A OUTPUT -d "$NET" -j ACCEPT
    done
    # Allow Tor process itself
    iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT


    echo -e "iptables rules set completed"
    echo -e "\n\n\033[1mTransparent Tor proxy is now active"
}


restore_iptables_rules() {
    echo -e "\n\nRestoring iptables..."
    iptables -t nat -F
    iptables-restore < "$IPTABLES_BACKUP"
}


check_ip_location() {
    # Initialize a flag
    local missing=false

    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "\033[33mTip: To get IP and Location information install curl to make HTTP requests\033[0m"
        missing=true
    fi
    # Check for jq
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "\033[33mTip: To get IP and Location information install jq to parse JSON\033[0m"
        missing=true
    fi

    # If both exist, run ip and location check
    if [ "$missing" = false ]; then
        echo -e "\033[33mGetting IP And Location Information...\033[0m\n"
        echo -e "\033[33mThis information may not be accurate\nbecause of Tor exit randomness policy...\033[0m\n"
        curl -s "http://ip-api.com/json/?fields=status,message,country,countryCode,region,regionName,city,zip,lat,lon,timezone,isp,org,as,query" | jq "."
    fi
}


cleanup() {
    restore_iptables_rules
    enable_ipv6
    echo -e "\n  Cleanup done.\n"
    exit 0
}


startup() {
    backup_iptables
    disable_ipv6
    trap cleanup SIGINT SIGTERM # Trap Ctrl+C and termination signals
    set_iptables_rules
    echo -e "Press \033[31mCtrl+C\033[0m to stop.\n\n"
    check_ip_location

}


# EXECUTE

echo -e ""
echo -e "   \033[31m░░░░░░░░░░░░░░░░░░░░░░░░\033[0m"
echo -e "   \033[31m░░▀█▀░█▀█░█▀▄░█▀▀░█░█░░░\033[0m"
echo -e "   \033[31m░░░█░░█░█░█▀▄░▀▀█░█▀█░░░\033[0m"
echo -e "   \033[31m░░░▀░░▀▀▀░▀░▀░▀▀▀░▀░▀░░░\033[0m"
echo -e "   \033[31m░░░░░░░░░░░░░░░░░░░░░░░░\033[0m\n"

echo -e "     \033[1mRunning Torsh V0.0.1\033[0m\n     \e[3mTor System Tunneling Script\e[0m\n"
echo -e "     \e[3mAuthor : Tony [ https://github.com/sudoerr ]"
echo -e "     Feel Free To Ask For Features, Report Issues"
echo -e "     And Contribute To Project :)\e[0m\n\n"

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[31mError: Torsh must be run as root. Please \n       run with sudo or as root user.\033[0m"
    exit 1
fi

# Run
startup


# Wait indefinitely until Ctrl+C
while true; do
    sleep 1
done

