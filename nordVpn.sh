#!/bin/bash

# Use api.nordvpn.com
servers=`curl -s https://api.nordvpn.com/server | jq -c '.[]'`

# Get NordVpn server recomendations
recomendations=`curl -s https://nordvpn.com/wp-admin/admin-ajax.php?action=servers_recommendations |\
                jq -r '.[] | .hostname' | shuf`

# Firewall everything has to go through the vpn
iptables  -F OUTPUT
ip6tables -F OUTPUT 2> /dev/null
iptables  -P OUTPUT DROP
ip6tables -P OUTPUT DROP 2> /dev/null
iptables  -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 
ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -o lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -o tun0 -j ACCEPT 
ip6tables -A OUTPUT -o tun0 -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -d `ip -o addr show dev eth0 | awk '$3 == "inet" {print $4}'` -j ACCEPT
ip6tables -A OUTPUT -d `ip -o addr show dev eth0 | awk '$3 == "inet6" {print $4; exit}'` -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -p udp --dport 53 -j ACCEPT
ip6tables -A OUTPUT -p udp --dport 53 -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -o eth0 -p udp --dport 1194 -j ACCEPT 
ip6tables -A OUTPUT -o eth0 -p udp --dport 1194 -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -o eth0 -p tcp --dport 1194 -j ACCEPT 
ip6tables -A OUTPUT -o eth0 -p tcp --dport 1194 -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -o eth0 -d nordvpn.com -j ACCEPT
ip6tables -A OUTPUT -o eth0 -d nordvpn.com -j ACCEPT 2> /dev/null

if [ ! -z $NETWORK ]; then
    gw=`ip route | awk '/default/ {print $3}'`
    ip route add to $NETWORK via $gw dev eth0
    iptables -A OUTPUT --destination $NETWORK -j ACCEPT
fi

if [ ! -z $NETWORK6 ]; then
    gw=`ip -6 route | awk '/default/ {print $3}'`
    ip -6 route add to $NETWORK6 via $gw dev eth0
    ip6tables -A OUTPUT --destination $NETWORK6 -j ACCEPT 2> /dev/null
fi

base_dir="/vpn"
ovpn_dir="$base_dir/ovpn"
auth_file="$base_dir/auth"

IFS=';'

if [[ -z "${COUNTRY}" ]]; then
    filtered="$servers"
else
    read -ra countries <<< "$COUNTRY"
    for country in "${countries[@]}"; do
        filtered="$filtered"`echo $servers | jq -c 'select(.country == "'$country'")'`
    done
fi

servers=`echo $filtered | jq -s -a 'unique[]'`
filtered="$servers"

if [[ "${CATEGORY}" ]]; then
    read -ra categories <<< "$CATEGORY"
    for category in "${categories[@]}"; do
        filtered=`echo $filtered | jq -c 'select(.categories[].name == "'$category'")'`
    done
fi

servers=`echo $filtered | jq -s -a 'unique[]'`
filtered=""

if [[ -z "${PROTOCOL}" ]]; then
    filtered=`echo $servers | jq -c 'select(.features.openvpn_udp == true)'\
        echo $servers | jq -c 'select(.features.openvpn_tcp == true)'`
else
    filtered=`echo $servers | jq -c 'select(.features.'$PROTOCOL' == true)'`
fi

servers=`echo $filtered | jq -s -c 'unique[]' | jq -s -c 'sort_by(.load)[]' | jq -r '.domain'`
IFS=$'\n'
read -ra filtered <<< "$servers"

for server in "${filtered[@]}"; do
    if [[ -z "${PROTOCOL}" ]] || [[ "${PROTOCOL}" == "openvpn_udp" ]]; then
        config_file="${ovpn_dir}/${server}.udp.ovpn"
        if [ -r "$config_file" ]; then
            config="$config_file"
            break
        fi
    fi
    if [[ -z "${PROTOCOL}" ]] || [[ "${PROTOCOL}" == "openvpn_tcp" ]]; then
        config_file="${ovpn_dir}/${server}.tcp.ovpn"
        if [ -r "$config_file" ]; then
            config="$config_file"
            break
        fi
    fi
done

if [ -z $config ]; then
    for server in ${recomendations}; do # Prefer UDP
        config_file="${ovpn_dir}/${server}.udp.ovpn"
        if [ -r "$config_file" ]; then
            config="$config_file"
            break
        fi
    done
    if [ -z $config ]; then # Use TCP if UDP not available
       for server in ${recomendations}; do
            config_file="${ovpn_dir}/${server}.tcp.ovpn"
            if [ -r "$config_file" ]; then
                config="$config_file"
                break
            fi
        done
    fi
fi

if [ -z $config ]; then
    config="${ovpn_dir}/`ls ${ovpn_dir} | shuf -n 1`"
fi

# Create auth_file
echo "$USER" > $auth_file 
echo "$PASS" >> $auth_file
chmod 0600 $auth_file

openvpn --cd $base_dir --config $config \
    --auth-user-pass $auth_file --auth-nocache \
    --script-security 2 --up /etc/openvpn/up.sh --down /etc/openvpn/down.sh
