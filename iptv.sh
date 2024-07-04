#!/usr/bin/env bash

step () { echo "[-] $1"; }

fatal () { echo "[!] $1"; exit 1; }

ensure_curl_is_installed () {
  if ! command -v curl &>/dev/null; then
    fatal "The cURL package that handles HTTP requests is not installed."
  fi
}

ensure_jq_is_installed () {
  if ! command -v jq &>/dev/null; then
    fatal "The jq package that handles HTTP JSON response is not installed."
  fi
}

ensure_openssl_is_installed () {
  if ! command -v openssl &>/dev/null; then
    fatal "The OpenSSL package that handles token computation is not installed."
  fi
}

categorize_by_channel_name () {
  result="720P"

  case "$1" in
    *4K*) result="4K" ;;
    *"超清"*|*"高清"*) result="1080P" ;;
  esac

  echo "$result"
}

make_epg () {
  # Check dependencies
  ensure_curl_is_installed
  ensure_jq_is_installed

  # Default variables
  output_file="epg.xml"
  endpoint="http://120.87.12.38:8083/epg/api/page/biz_59417088.json"
  curl_args=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -o | --output ) output_file="$2"; shift 2;;
      --endpoint ) endpoint="$2"; shift 2;;
      --curl ) curl_args="$2"; shift 2;;
      *) echo "Unknown option: $1"; exit 1;;
    esac
  done

  step "Request channel index"
  response=$(curl --silent $curl_args "$endpoint")

  step "Create the EPG XML file"
  echo '<?xml version="1.0" encoding="UTF-8"?>' > $output_file
  echo '<!DOCTYPE tv SYSTEM "xmltv.dtd">' >> $output_file
  echo "<tv date=\"$(date +"%Y%m%d%H%M%S %z")\">" >> $output_file

  while read -r item; do
    item_title=$(echo "$item" | jq -r '.itemTitle')
    item_type=$(echo "$item" | jq -r '.itemType')
    data_link=$(echo "$item" | jq -r '.dataLink')

    if [[ "$item_type" == "channel" ]]; then
      step "Process: $item_title"

      response=$(curl --silent --interface eth0 "$data_link")
      channel_icon=$(echo "$response" | jq -r '.channel.icon')
      channel_title=$(echo "$response" | jq -r '.channel.title')
      hwcode=$(echo "$response" | jq -r '.channel.params.hwcode')

      echo "  <channel id=\"$hwcode\">" >> $output_file
      echo "    <display-name lang=\"zh\">$channel_title</display-name>" >> $output_file
      echo "    <icon src=\"$channel_icon\"/>" >> $output_file
      echo "  </channel>" >> $output_file

      while read -r schedule; do
        schedule_title=$(echo "$schedule" | jq -r '.title')
        schedule_starttime=$(echo "$schedule" | jq -r '.starttime')
        schedule_endtime=$(echo "$schedule" | jq -r '.endtime')

        echo "  <programme start=\"$schedule_starttime +0800\" stop=\"$schedule_endtime +0800\" channel=\"$hwcode\">" >> $output_file
        echo "    <title lang=\"zh\">$schedule_title</title>" >> $output_file
        echo "  </programme>" >> $output_file
      done < <(echo "$response" | jq -c '.schedules[]')
    fi
  done < <(echo "$response" | jq -c '.areaDatas[].items[]')

  echo '</tv>' >> $output_file

  step "EPG built sucessfully!"

  exit 0
}

make_playlist () {
  # Check dependencies
  ensure_curl_is_installed
  ensure_jq_is_installed
  ensure_openssl_is_installed

  # Default values
  ip_address="127.0.0.1"
  udpxy_endpoint="http://127.0.0.1:4022"
  output_file="playlist.M3U8"
  curl_args=""
  endpoint="http://eds1.unicomgd.com:8082"

  while [ $# -gt 0 ]; do
    case "$1" in
      -u | --user) user_id="$2"; shift 2;;
      -p | --password) password="$2"; shift 2;;
      -d | --device) device_id="$2"; shift 2;;
      --ip) ip_address="$2"; shift 2;;
      --mac) mac_address="$2"; shift 2;;
      --udpxy) udpxy_endpoint="$2"; shift 2;;
      -o | --output) output_file="$2"; shift 2;;
      --curl) curl_args="$2"; shift 2;;
      *) echo "Unknown option: $1"; exit 1;;
    esac
  done

  # Validate user input
  if [[ -z "$user_id" ]]; then
    fatal "Requires an IPTV user ID with -u or --user"
  fi

  if [[ -z "$password" ]]; then
    fatal "Requires an IPTV password with -p or --password"
  fi

  if [[ -z "$device_id" ]]; then
    fatal "Requires a device ID with -d or --device"
  fi

  if [[ -z "$mac_address" ]]; then
    fatal "Requires a device MAC address with --mac"
  fi

  # Retreive Authentication URL
  step "Authenticate"

  response=$(curl --silent $curl_args \
    "$endpoint/EDS/jsp/AuthenticationURL?Action=Login&UserID=$user_id&return_type=1")

  epgurl=$(echo "$response" | jq -r '.epgurl')
  host="${epgurl#*//}"
  host="${host%%/*}"

  # Retreive challenge token
  response=$(curl --silent $curl_args \
    "http://$host/EPG/oauth/v2/authorize?response_type=EncryToken&client_id=jiulian&userid=$user_id")

  encry_token=$(echo "$response" | jq -r '.EncryToken')

  # Authenticate
  pass=$(printf "%-024s" "$password" | tr ' ' 0 | xxd -p)

  authinfo=(
      $(shuf -i 1-99999999 -n 1) $encry_token
      $user_id $device_id
      $ip_address $mac_address
      "Reserved" "OTT"
  )

  authinfo=$(IFS='$'; echo "${authinfo[*]}")

  authinfo=$(echo -n $authinfo | \
    openssl enc -e -des-ede3 -K $pass -nosalt 2>/dev/null | \
    xxd -p -u -c 0)

  response=$(curl --silent $curl_args \
    "http://$host/EPG/oauth/v2/token?grant_type=EncryToken&client_id=jiulian&UserID=$user_id&DeviceType=UNT400G&DeviceVersion=5.5.021&authinfo=$authinfo&issmarthomestb=1&tvdesktopid=")

  access_token=$(echo "$response" | jq -r '.access_token')

  step "Request channel metas"
  declare -A logos

  response=$(curl --silent $curl_args \
    http://120.87.12.38:8083/epg/api/custom/getAllChannel.json)

  while read -r channel; do
    hwcode=$(echo "$channel" | jq -r '.params.hwcode')
    icon=$(echo "$channel" | jq -r '.icon')

    logos["$hwcode"]="$icon"
  done < <(echo "$response" | jq -c '.channels[]')

  step "Request channels from the batch API"
  response=$(curl --silent $curl_args \
    --data '{"channelcodes":""}' \
    --header 'Content-Type: application/json;charset=utf-8' \
    --header "Authorization: $access_token" \
    http://$host/EPG/interEpg/channellist/batch)

  step "Decode channels from the HTTP response"
  echo "#EXTM3U" > $output_file
  echo "#EXT-X-VERSION:3" >> $output_file

  echo "$response" | jq -c '.channellist[]' | while read -r channel; do
    channelcode=$(echo "$channel" | jq -r '.channelcode')
    channelname=$(echo "$channel" | jq -r '.channelname')
    channelurl=$(echo "$channel" | jq -r '.channelurl')
    IFS='|' read -ra channelurls <<< "$channelurl"

    step "Process: $channelname"

    pattern="://([^/]+)"
    if [[ "${channelurls[0]}" =~ $pattern ]]; then
      host=${BASH_REMATCH[1]}

      group=$(categorize_by_channel_name "$channelname")

      echo "#EXTINF:-1 tvg-id=\"$channelcode\" tvg-name=\"$channelname\" tvg-logo=\"${logos[$channelcode]}\" group-name=\"$group\",$channelname" >> $output_file
      echo "$udpxy_endpoint/udp/$host" >> $output_file
    fi
  done

  step "Extract IPTV channels successfully!"

  exit 0
}

##
## Main
##

while [ $# -gt 0 ]; do
  case "$1" in
    make:playlist) shift 1; make_playlist "$@";;
    make:epg) shift 1; make_epg "$@";;
    *) echo "Unknown command: $1"; exit 1;;
  esac
done
