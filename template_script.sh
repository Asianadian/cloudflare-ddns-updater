#!/bin/bash

##### Config #####
API_KEY=""
EMAIL=""
ZONE_ID=""
RECORD_NAME=""
DISCORD_WEBHOOK=""


##### Retrieve current IP #####
REGEX_IPV4="^((25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})$"

IP_SERVICES=(
  "https://api.ipify.org"
  "https://ipv4.icanhazip.com"
  "https://ipinfo.io/ip"
)

for ip_service in ${IP_SERVICES[@]}; do
  ip_response=$(curl -s $ip_service)
  if [[ $ip_response =~ $REGEX_IPV4 ]]; then
    current_ip=$BASH_REMATCH
    logger -s "DDNS Updater: Fetched current IP $current_ip"
    break
  else
    logger -s "DDNS Updater: Failed to retrieve current IP from $service"
  fi
done

if [[ -z $current_ip ]]; then
  logger -s "DDNS Updater: Failed to find current IP"
  exit 2
fi

##### Check for Cloudflare A record #####
logger -s "DDNS Updater: Starting check for A record"

email_auth_header="X-Auth-Email: $EMAIL"
token_auth_header="Authorization: Bearer $API_KEY"

record_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$RECORD_NAME" \
                      -H "$email_auth_header" \
                      -H "$token_auth_header" \
                      -H "Content-Type: application/json")


if [[ $(echo $record_response | jq ".result_info.count") == 0 ]]; then
  logger -s "DDNS Updater: No existing record for $RECORD_NAME"
  exit 1
fi

##### Check if IP update needs to be performed #####
old_ip=$(echo $record_response | jq ".result[0].content")
old_ip="${old_ip%\"}"
old_ip="${old_ip#\"}"

if [[ $current_ip == $old_ip ]]; then
  logger -s "DDNS Updater: A record IP does not need to be updated"
  exit 0
fi

##### Update Cloudflare A record #####
record_id=$(echo $record_response | jq ".result[0].id")
record_id="${record_id%\"}"
record_id="${record_id#\"}"

update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
                     -H "$email_auth_header" \
                     -H "$token_auth_header" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$current_ip\"}")

##### Send update status #####
success=$(echo $update | jq ".success")

if [[ $success == true ]]; then
  logger -s "DDNS Updater: Successfully updated IP in A record"

  if [[ $DISCORD_WEBHOOK != "" ]]; then
    curl -s -X POST $DISCORD_WEBHOOK \
                -H "Accept: application/json" \
                -H "Content-Type:application/json" \
                --data "{
                  \"content\" : \"Updated: '$RECORD_NAME' IP address to '$current_ip'\"
                }"
  fi
else
  logger -s "DDNS Updater: Failed to update IP in A record"

  if [[ $DISCORD_WEBHOOK != "" ]]; then
    curl -s -X POST $DISCORD_WEBHOOK \
                -H "Accept: application/json" \
                -H "Content-Type:application/json" \
                --data "{
                  \"content\" : \"Failed: Updating '$RECORD_NAME' IP address to '$current_ip'\"
                }"
  fi
  exit 1
fi








