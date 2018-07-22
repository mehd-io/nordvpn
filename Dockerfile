FROM lsiobase/alpine:latest

LABEL maintainer="Alexander Zinchenko <alexander@zinchenko.com>"

ENV URL_NORDVPN_API="https://api.nordvpn.com/server" \
    URL_RECOMMENDED_SERVERS="https://nordvpn.com/wp-admin/admin-ajax.php?action=servers_recommendations" \
    URL_OVPN_FILES="https://downloads.nordcdn.com/configs/archives/servers/ovpn.zip" \
    MAX_LOAD=70

VOLUME ["/ovpn/"]

    # Install dependencies 
RUN \
    echo "**** install packages ****" && \
    apk --no-cache --no-progress update && \
    apk --no-cache --no-progress upgrade && \
    apk --no-cache --no-progress add bash curl unzip iptables ip6tables jq openvpn && \
    echo "**** create folders ****" && \
    mkdir -p /vpn/ \
    mkdir -p /ovpn/

COPY root/ /
