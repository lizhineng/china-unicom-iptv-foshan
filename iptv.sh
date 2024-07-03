#!/usr/bin/env bash

# Default values
ip_address="127.0.0.1"
udpxy_endpoint="http://127.0.0.1:4022"
output_file="iptv.M3U8"
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

##
## Validate user input
##

if [[ -z "$user_id" ]]; then
  echo "Requires an IPTV user ID with -u or --user"
  exit 1
fi

if [[ -z "$password" ]]; then
  echo "Requires an IPTV password with -p or --password"
  exit 1
fi

if [[ -z "$device_id" ]]; then
  echo "Requires a device ID with -d or --device"
  exit 1
fi

if [[ -z "$mac_address" ]]; then
  echo "Requires a device MAC address with --mac"
  exit 1
fi

##
## Execute the main script
##

echo "[-] Authenticate"

##
## Retreive Authentication URL
##

response=$(curl --silent $curl_args \
  "$endpoint/EDS/jsp/AuthenticationURL?Action=Login&UserID=$user_id&return_type=1")

epgurl=$(echo "$response" | jq -r '.epgurl')
host="${epgurl#*//}"
host="${host%%/*}"

##
## Retreive token
##

response=$(curl --silent $curl_args \
  "http://$host/EPG/oauth/v2/authorize?response_type=EncryToken&client_id=jiulian&userid=$user_id")

encry_token=$(echo "$response" | jq -r '.EncryToken')

##
## Authenticate
##

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

echo "[-] Request channel metas"

declare -A logos

response=$(curl --silent $curl_args \
  http://120.87.12.38:8083/epg/api/custom/getAllChannel.json)

while read -r channel; do
  hwcode=$(echo "$channel" | jq -r '.params.hwcode')
  icon=$(echo "$channel" | jq -r '.icon')

  logos["$hwcode"]="$icon"
done < <(echo "$response" | jq -c '.channels[]')

echo "[-] Request channels from the batch API"

response=$(curl --silent $curl_args \
    --data '{"channelcodes":""}' \
    --header 'Content-Type: application/json;charset=utf-8' \
    --header "Authorization: $access_token" \
    http://$host/EPG/interEpg/channellist/batch)

echo "[-] Decode channels from the HTTP response"

echo "#EXTM3U" > $output_file
echo "#EXT-X-VERSION:3" >> $output_file

echo "$response" | jq -c '.channellist[]' | while read -r channel; do
  channelcode=$(echo "$channel" | jq -r '.channelcode')
  channelname=$(echo "$channel" | jq -r '.channelname')
  channelurl=$(echo "$channel" | jq -r '.channelurl')
  IFS='|' read -ra channelurls <<< "$channelurl"

  echo "[-] Process: $channelname"

  pattern="://([^/]+)"
  if [[ "${channelurls[0]}" =~ $pattern ]]; then
    host=${BASH_REMATCH[1]}

    group="720P"
    case "$channelname" in
      *"4K"*)
        group="4K"
        ;;
      *"超清"*|*"高清"*)
        group="1080P"
        ;;
      \?)
        group="720P"
        ;;
    esac

    echo "#EXTINF:-1 tvg-id=\"$channelcode\" tvg-name=\"$channelname\" tvg-logo=\"${logos[$channelcode]}\" group-name=\"$group\",$channelname" >> $output_file
    echo "$udpxy_endpoint/udp/$host" >> $output_file
  fi
done

echo "[-] Extract IPTV channels successfully!"
