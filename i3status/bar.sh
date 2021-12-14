#!/bin/bash

# global counter for wttr.in
COUNT_WEATHER=1

# global values for colors
BLUE="#0000FF"
GREEN="#00FF00"
PINK="#FF66E5"
RED="#FF0000"
WHITE="#FFFFFF"
YELLOW="#FFFF00"

# clean audio_activity.log at startup
echo "" > ~/.config/i3/i3status/audio_activity.log
# dbus-monitor to monitor audio activity status
exec dbus-monitor | grep --line-buffered -A2 -P 'xesam:title|xesam:artist' | grep --line-buffered -oP 'string "[^\n]+"' | grep --line-buffered -Pv 'xesam:title |xesam:artist' > ~/.config/i3/i3status/audio_activity.log &

# check if Spotify or Firefox are running
function check_spotifox () {
    if [[ $(ps -A | grep -c 'spotify') -ge 1 || $(ps -A | grep -c 'GeckoMain') -ge 1 ]]; then
        get_spotifox
    fi
}

# monitoring Spotify and Firefox for audio notifications
function get_spotifox () {
    echo -n "{\"name\":\"id_spotifox\",\"full_text\":"

    # get a snapshot of my log
    timeout 0.1s tail -f ~/.config/i3/i3status/audio_activity.log > ~/.config/i3/i3status/temp_audio_activity.log
    cat ~/.config/i3/i3status/temp_audio_activity.log | cut -d '"' -f2 | tail -3 > ~/.config/i3/i3status/res_audio_activity.log

    # if the first line is `xesam:title` then it's from Firefox, else from Spotify
    local ARTIST=$(cat ~/.config/i3/i3status/res_audio_activity.log | head -1 | sed 's/("|\\)/\\&/g')
    local SONG=$(cat ~/.config/i3/i3status/res_audio_activity.log | tail -1 | sed 's/("|\\)/\\&/g')
    if [[ $ARTIST == 'xesam:title' ]]; then
        local VIDEO=$(cat ~/.config/i3/i3status/res_audio_activity.log | awk 'NR==2')
        echo -n "\"$(echo $VIDEO | awk '{gsub(/("|\\)/,"");}1')\","
        echo -n "\"color\":\"$PINK\"},"
    else
        echo -n "\"$ARTIST ~ $SONG\","
        echo -n "\"color\":\"$PINK\"},"

    fi
}

# - if bluetooth is powered then:
#   - if a paired device exist and is connected, display it
#   - else no device is connected
# - else bluetooth is off
function get_blue () {
    echo -n "{\"name\":\"id_blue\",\"full_text\":"

    if [[ $(bluetoothctl show | grep 'Powered' | grep -co 'yes') -ge 1 ]]; then
        if [[ $(bluetoothctl paired-devices | head -1 | cut -d ' ' -f2 | xargs -I {} bluetoothctl info {} | grep -c 'Connected: yes') -eq 1 ]]; then
            RES=$(bluetoothctl paired-devices | head -1 | cut -d ' ' -f3-)
            echo -n "\"$RES\","
            echo -n "\"color\":\"$BLUE\"},"
        else
            echo -n "\"no bluetooth connection\","
            echo -n "\"color\":\"$YELLOW\"},"
        fi
    else
        echo -n "\"bluetooth off\","
        echo -n "\"color\":\"$RED\"},"
    fi

    $(bluetoothctl paired-devices | cut -d ' ' -f3-)
}

# if Master is on, get both L and R volume
function get_vol () {
    echo -n "{\"name\":\"id_vol\",\"full_text\":"

    RES="Vol: "

    local VOL1=$(amixer sget 'Master' | grep -Eo '[0-9]{1,3}%' | head -1)
    local VOL2=$(amixer sget 'Master' | grep -Eo '[0-9]{1,3}%' | tail -1)
    RES+="$VOL1 $VOL2"

    if [[ $(amixer sget 'Master'| grep -c 'off') -gt 0 ]]; then
        echo -n "\"muted volume\","
        echo -n "\"color\":\"$RED\"},"
    elif [[ ${VOL1::-1} -gt 100 || ${VOL2::-1} -gt 100 ]]; then
        echo -n "\"$RES\","
        echo -n "\"color\":\"$RED\"},"
    else
        echo -n "\"$RES\","
        echo -n "\"color\":\"$WHITE\"},"
    fi
}

# - get total CPU usage using ps
# - get totale cores
# -> real_cpu_usage = total_cpu_usage / cores
# - fetch °C from /sys/class/thermal/thermal_zone0/temp
function get_cpu () {
    echo -n "{\"name\":\"id_cpu\",\"full_text\":"

    local TOTAL_USG=$(ps -A -o %cpu | awk '{SUM+=$1}END{print SUM}' | cut -d '.' -f-1)
    local TEMP_CORES=$(lscpu | grep -E '^Core')
    local CORES=$(echo "${TEMP_CORES: -1}")
    local USG=$(expr $((TOTAL_USG / CORES)))
    RES="${USG}% "

    local TEMP=$(cat /sys/class/thermal/thermal_zone0/temp | cut -c -2)
    RES+="${TEMP}°C"

    echo -n "\"$RES\","

    if [[ $USG -ge 80 && $TEMP -ge 65 ]]; then
        echo -n "\"color\":\"$RED\"},"
    elif [[ $USG -ge 80 || $TEMP -ge 65 ]]; then
        echo -n "\"color\":\"$YELLOW\"},"
    else
        echo -n "\"color\":\"$WHITE\"},"
    fi
}

# list GPU brand
function get_gpu () {
    echo -n "{\"name\":\"id_gpu\",\"full_text\":"

    echo -n "\"$(lspci | grep VGA | cut -d ' ' -f5)\","
    echo -n "\"color\":\"$WHITE\"},"
}

# show used_ram/total_ram and used_swap/total_swap
function get_mem () {
    echo -n "{\"name\":\"id_mem\",\"full_text\":"

    local TOTAL_RAM=$(free -h | grep Mem | awk '{print $2}')
    local USED_RAM=$(free -h | grep Mem | awk '{print $3}')
    RES="$USED_RAM/$TOTAL_RAM "

    local TOTAL_SWAP=$(free -h | grep Swap | awk '{print $2}')
    local USED_SWAP=$(free -h | grep Swap | awk '{print $3}')
    RES+="$USED_SWAP/$TOTAL_SWAP"

    echo -n "\"$RES\","

    local FLAG1=$(free -m | grep Mem | awk '{print $4}')
    local FLAG2=$(free -m | grep Swap | awk '{print $4}')
    if [[ $FLAG1 -le 1000 && $FLAG2 -le 100 ]]; then
        echo -n "\"color\":\"$RED\"},"
    elif [[ $FLAG1 -le 1000 || $FLAG2 -le 100 ]]; then
        echo -n "\"color\":\"$YELLOW\"},"
    else
        echo -n "\"color\":\"$WHITE\"},"
    fi
}

# weather from wttr.in
function get_weather () {
    echo -n "{\"name\":\"id_weather\",\"full_text\":"

    if [[ $COUNT_WEATHER -eq 1 ]]; then
        local REQ=$(curl wttr.in?format="%c+%t+%w\n")
        echo $REQ > ~/.config/i3/i3status/weather.log
    fi

    if [[ $COUNT_WEATHER -ge 600 ]]; then
        COUNT_WEATHER=0
    fi

    RES=$(cat ~/.config/i3/i3status/weather.log)
    let COUNT_WEATHER=COUNT_WEATHER+1

    echo -n "\"$RES\","
    echo -n "\"color\":\"$WHITE\"},"
}

# if ethernet is on then show it, else `no eth connection`
function get_eth () {
    echo -n "{\"name\":\"id_eth\",\"full_text\":"

    if [[ $(ip address | grep -c 'state UP') -ge 1 ]]; then
        RES=$(ip address | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk 'NR==2')
        echo -n "\"$RES\","
        echo -n "\"color\":\"$GREEN\"},"
    else
        echo -n "\"no eth connection\","
        echo -n "\"color\":\"$RED\"},"
    fi
}

# i3status bar
echo '{ "version": 1, "click_events": true }'
echo '['
echo '[]'

# every function is repeated every second
( while : ; do
    echo -n ",["
    check_spotifox
    get_blue
    get_vol
    get_cpu
    get_gpu
    get_mem
    get_weather
    get_eth
    echo -n "{\"name\":\"id_time\",\"full_text\":\"$(date "+%H:%M")\",\"color\":\"$WHITE\"}"
    echo -n "]"

    # There's a 0.1s timeout in the spotifox function, so technically it is 1s
    sleep 0.9
done ) &

# diffrent use cases for when you click on the widgets
while read LINE; do
    if [[ $LINE == *"name"*"id_spotifox"* ]]; then
        if [[ $(ps -A | grep -c 'spotify') -ge 1 ]]; then
            wmctrl -x -R "Spotify"
        else
            wmctrl -x -R "Firefox"
        fi
    fi

    if [[ $LINE == *"name"*"id_blue"* ]]; then
        gnome-terminal --hide-menubar --title=statusbar_popup -- bash -c "bluetoothctl" &
    fi

    if [[ $LINE == *"name"*"id_vol"* ]]; then
        gnome-terminal --hide-menubar --title=statusbar_popup -- bash -c "alsamixer" &
    fi

    if [[ $LINE == *"name"*"id_cpu"* || $LINE == *"name"*"id_mem"* ]]; then
        gnome-terminal --hide-menubar --title=statusbar_popup -- bash -c "htop" &
    fi

    if [[ $LINE == *"name"*"id_gpu"* ]]; then
        gnome-terminal --hide-menubar --title=statusbar_popup -- bash -c "nvtop" &
    fi

    if [[ $LINE == *"name"*"id_weather"* ]]; then
        gnome-terminal --hide-menubar --title=statusbar_popup -- bash -c "curl v2.wttr.in; read -n 1; exit" &
    fi

    if [[ $LINE == *"name"*"id_eth"* ]]; then
        gnome-terminal --hide-menubar --title=statusbar_popup -- bash -c "speedtest-cli; read -n 1; exit" &
    fi

    if [[ $LINE == *"name"*"id_time"* ]]; then
        gnome-terminal --hide-menubar --title=statusbar_popup -- bash -c "ncal -b -M -y; read -n 1; exit" &
    fi
done

