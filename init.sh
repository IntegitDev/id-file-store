#!/bin/bash

systemctl-exists() {
  [ $(systemctl list-unit-files "${1}*" | wc -l) -gt 3 ]
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

params="/etc/wireguard/params"

if [ ! -f ${params} ]
    then

    apt update && apt upgrade -y
    apt install -y curl gawk

    if [ ! -f './wireguard-install.sh' ]
        then echo 'Downloading wireguard-install.sh script...'
        curl -LO https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh
    fi

    if [ ! -f './wireguard-install.sh' ]
        then echo "Cannot download wireguard-install.sh. You can try to make it manualy by link: https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh"
        exit
    fi

    echo 'Running wireguard-install.sh script...'
    chmod +x wireguard-install.sh
    ./wireguard-install.sh
    echo ''
    echo 'Done with wireguard-install.sh script!'
fi


if [ ! -f ${params} ]
    then echo "Error while wireguard-install.sh script execution"
fi

if [ ! -f 'wireguard-ui' ] || [[ $1 == "-ui" ]]
    then echo 'Downloading custom WireGuard-UI dist...'
    curl -LO https://raw.githubusercontent.com/IntegitDev/id-file-store/main/wireguard-ui.tar.gz
    tar zxvf wireguard-ui.tar.gz
    rm wireguard-ui.tar.gz
    chmod +x wireguard-ui
fi

if [ ! -f 'wireguard-ui' ]
    then echo "Cannot download WireGuard-UI executable file. Please, try to load it manually"
    exit
fi

WIREGUARD_UI_EXECUTABLE=$(realpath wireguard-ui)
WIREGUARD_UI_WORKDIR=$(realpath .)

if ! systemctl-exists wireguard-ui
    then read -p 'Do you want to add WireGuard-UI to systemctl? (default yes): ' addToSystemCtl

    if [[ addToSystemCtl != 'n' ]] && [[ addToSystemCtl != 'N' ]]
        then

        echo "[Unit]
Description=WireGuard UI Server
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=${WIREGUARD_UI_EXECUTABLE}
WorkingDirectory=${WIREGUARD_UI_WORKDIR}

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wireguard-ui.service
        systemctl enable wireguard-ui
        systemctl daemon-reload
    fi
fi

echo 'Loading wireguard-install.sh params...'
source ${params}

if ! systemctl-exists wgui
    then read -p 'Do you want to add config changes tracker? (default yes): ' addConfigTracker
    
    if [[ addConfigTracker != 'n' ]] && [[ addConfigTracker != 'N' ]]
        then echo "[Unit]
Description=Restart WireGuard
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart wg-quick@${SERVER_WG_NIC}.service

[Install]
RequiredBy=wgui.path" > /etc/systemd/system/wgui.service
        echo "[Unit]
Description=Watch /etc/wireguard/wg0.conf for changes

[Path]
PathModified=/etc/wireguard/wg0.conf

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wgui.path
        systemctl enable wgui.{path,service}
        systemctl start wgui.{path,service}
    fi
fi

if [ -d './db' ]
    then read -p "The WireGuard UI already inited. Do you want to remove all data and reinitialize it? (WARNING! ALL DATA WILL BE REMOVED) (Y/n) (default: n): " removeAll
    echo

    if [[ $removeAll == 'y' ]] || [[ $removeAll == 'Y' ]]
        then rm -rf ./db
        echo 'Done!'
    else
        echo 'Forced initialization cancelled. Exit...'
        exit
    fi
fi

WG_CONF="/etc/wireguard/${SERVER_WG_NIC}.conf"
POST_UP=$(gawk 'match($0, /PostUp\s*=\s*([^\n]+)/, m) {print m[1]}' ${WG_CONF})
POST_DOWN=$(gawk 'match($0, /PostDown\s*=\s*([^\n]+)/, m) {print m[1]}' ${WG_CONF})

echo "WireGuard initialization process. Please, enter admin user credentials /"

read -p "Enter username (leave blank for \"admin\"): " username
read -p "Enter password (leave blank for \"admin\"): " -s password

echo 'Setup environment variables'

username=${username:-admin}
password=${password:-admin}

export WGUI_USERNAME="$username"
export WGUI_PASSWORD="$password"
export WGUI_ENDPOINT_ADDRESS="${SERVER_PUB_IP}"
export WGUI_DNS="${CLIENT_DNS_1},${CLIENT_DNS_2}"
export WGUI_FORWARD_MARK=""
export WGUI_CONFIG_FILE_PATH="${WG_CONF}"

export WGUI_SERVER_INTERFACE_ADDRESSES="${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64"
export WGUI_SERVER_POST_UP_SCRIPT="${POST_UP}"
export WGUI_SERVER_POST_DOWN_SCRIPT="${POST_DOWN}"
export WGUI_SERVER_LISTEN_PORT="${SERVER_PORT}"
export WGUI_SERVER_PRIVATE_KEY="${SERVER_PRIV_KEY}"

export WGUI_DEFAULT_CLIENT_ALLOWED_IPS="0.0.0.0/0,::/0"
export WGUI_DEFAULT_CLIENT_USE_SERVER_DNS=1
export WGUI_DEFAULT_CLIENT_ENABLE_AFTER_CREATION=1

read -p 'Almost done! Please, tap enter and wait until server will be runned. After that, press Ctrl+C and restart server from scheduler'

if systemctl-exists wireguard-ui
    then systemctl stop wireguard-ui
fi

./wireguard-ui