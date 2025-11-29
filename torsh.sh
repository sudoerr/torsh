#!/usr/bin/env bash

# ===============================================================
# Torsh, Transparent Tor proxy for full system TCP traffic
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


COFNIG_DIR="/etc/torsh"
CONFIG_FILE="$COFNIG_DIR/torsh.conf"


# TODO: create a singleton way to run one instance of it and also
#       make sure to save iptables in a place better than /tmp and
#       be able to restore it after reboot or sudden power off...


require_root() {
    # Ensure the script is run as root
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[31mError: Torsh must be run as root. Please \n       run with sudo or as root user.\033[0m"
        exit 1
    fi
}


load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        echo -e "Loaded config from: $CONFIG_FILE"
    else
        echo -e "\033[31mConfig file not found: $CONFIG_FILE"
        echo -e "Run \"sudo $0 config\" to create/edit config file\033[0m"
        exit 1
    fi
}


edit_config() {
    require_root

    mkdir -p "$COFNIG_DIR"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
# TORSH CONFIGURATION FILE
TOR_UID=$(id -u tor 2> /dev/null || id -u debian-tor 2> /dev/null || echo 0)
TOR_DNS_PORT=5353
TOR_TRANS_PORT=9040
TOR_SOCKS_PORT=9050
NON_TOR_NETS=("192.168.0.0/16" "10.0.0.0/8" "172.16.0.0/12" "127.0.0.0/8")
EOF
        echo -e "Config file created at $CONFIG_FILE. Edit values as needed"
    fi

    ${EDITOR:-nano} "$CONFIG_FILE"
}



backup_iptables() {
    require_root
    IPTABLES_BACKUP="/tmp/iptables.backup.$(date +%s)"
    iptables-save > "$IPTABLES_BACKUP"
    echo "Saved current iptables to $IPTABLES_BACKUP"
}


disable_ipv6() {
    require_root
    # Disable IPv6 temporarily
    echo -e "Disabling IPv6 temporarily..."
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null
    sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1 > /dev/null
}


enable_ipv6() {
    require_root
    echo -e "Enabling IPv6 again..."
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null
    sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0 > /dev/null
}


set_iptables_rules() {
    require_root
    echo -e "Setting iptables rules..."

    # Flush current NAT rules
    iptables -F
    iptables -t nat -F

    # --- NAT rules ---
    # Exempt Tor process from NAT
    iptables -t nat -A OUTPUT -m owner --uid-owner "$TOR_UID" -j RETURN
    # Redirect DNS (UDP and TCP) to Tor DNSPort
    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $TOR_DNS_PORT
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $TOR_DNS_PORT
    # Exempt local/non-Tor networks from NAT
    for NET in "${NON_TOR_NETS[@]}"; do
        iptables -t nat -A OUTPUT -d "$NET" -j RETURN
    done
    # Redirect all new TCP connections to Tor TransPort
    iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports $TOR_TRANS_PORT

    # --- Filter rules ---
    # 1. Allow loopback (very first, prevents Tor warnings)
    iptables -A OUTPUT -o lo -j ACCEPT
    # 2. Allow DNS queries (UDP & TCP 53) before REJECT
    iptables -I OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -I OUTPUT -p tcp --dport 53 -j ACCEPT
    # 3. Allow traffic to Tor DNSPort (5353) after NAT
    iptables -I OUTPUT -p udp --dport $TOR_DNS_PORT -j ACCEPT
    iptables -I OUTPUT -p tcp --dport $TOR_DNS_PORT -j ACCEPT
    # 4. Allow systemd-resolved (127.0.0.53)
    iptables -I OUTPUT -d 127.0.0.53 -j ACCEPT
    # 5. Allow Tor process itself
    iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT
    # 6. Block all other UDP (prevents WebRTC/STUN leaks)
    iptables -A OUTPUT -p udp -j DROP # or REJECT for ICMP error
    # 7. Allow established/related connections
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    # 8. Allow traffic to non-Tor networks
    for NET in "${NON_TOR_NETS[@]}"; do
        iptables -A OUTPUT -d "$NET" -j ACCEPT
    done
    # # 9. Default policy: allow everything else (optional)
    # iptables -A OUTPUT -j ACCEPT

    echo -e "iptables rules set completed"
    echo -e "\n\n\033[1mTransparent Tor proxy is now active"
}


restore_iptables_rules() {
    require_root
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


check_tor_connectivity() {

    # Initialize a flag
    local missing=false

    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "\033[33mTip: To check Tor connectivity before connection install curl to make HTTP requests\033[0m"
        missing=true
    fi
    # Check for jq
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "\033[33mTip: To check Tor connectivity before connection install jq to parse JSON\033[0m"
        missing=true
    fi

    if [ "$missing" = false ]; then

        echo -e "Checking Tor conn before activating..."
        local url="https://check.torproject.org/api/ip"
        
        local response
        response=$(curl -s \
            --socks5-hostname "127.0.0.1:9050" \
            --max-time 10 \
            --connect-timeout 5 \
            "$url")
        
        curl_code=$?

        if [[ $curl_code -ne 0 ]]; then
            echo -e "Tor conn check failed (curl error: $curl_code)"
            echo -e "Tor is not accessable through port $TOR_SOCKS_PORT"
            exit 1
        fi

        echo -e "Tor Connection to check IP was successful\n"
        echo "$response" | jq "."
        echo -e "\nActivating Torsh..."
    fi
}



cleanup() {
    require_root
    restore_iptables_rules
    enable_ipv6
    echo -e "\n  Cleanup done.\n"
    exit 0
}


startup() {
    require_root
    
    load_config
    check_tor_connectivity

    backup_iptables
    disable_ipv6
    trap cleanup SIGINT SIGTERM # Trap Ctrl+C and termination signals
    set_iptables_rules
    echo -e "Press \033[31mCtrl+C\033[0m to stop.\n\n"
    check_ip_location

    # Wait indefinitely until Ctrl+C
    while true; do
        sleep 1
    done
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



# Get commands and do as wished.

case "$1" in
    connect)
        startup
        ;;
    config)
        edit_config
        ;;
    *)
        echo -e "\033[31mUsage: sudo $0 {connect|config}\033[0m"
        ;;
esac


