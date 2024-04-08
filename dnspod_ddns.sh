#!/usr/bin/env bash
#
# Dnspod DDNS with BashShell
# Github:https://github.com/kkkgo/dnspod-ddns-with-bashshell
# More: https://03k.org/dnspod-ddns-with-bashshell.html
# CONF START

if [ -z "$API_TOKEN" ]; then
  [ -f $HOME/.dnspod_token ] && API_TOKEN=$(cat $HOME/.dnspod_token)
fi

domain="example.com"
hosts=("@" "www")
#CHECKURL="https://ip.03k.org"
CHECKURL="https://ifconfig.me"
#CHECKURL="https://api-ipv4.ip.sb/ip"
#OUT="pppoe"
#CONF END

#. /etc/profile

msg_text="DDNS update result:\n"
update_flag="false"

date

for host in "${hosts[@]}"; do
  if (echo $CHECKURL | grep -q "://"); then
    IPREX='([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])'
    URLIP=$(curl -4 -k $(if [ -n "$OUT" ]; then echo "--interface $OUT"; fi) -s $CHECKURL | grep -Eo "$IPREX" | tail -n1)
    if (echo $URLIP | grep -qEvo "$IPREX"); then
      URLIP="Get $DOMAIN URLIP Failed."
    fi
    echo "[URL IP]:$URLIP"
    dnscmd="nslookup"
    type nslookup >/dev/null 2>&1 || dnscmd="ping -c1"
    if [ "$host" == "@" ]; then
      DNSTEST=$($dnscmd $domain)
    else
      DNSTEST=$($dnscmd $host.$domain)
    fi
    if [ "$?" != 0 ] && [ "$dnscmd" == "nslookup" ] || (echo $DNSTEST | grep -qEvo "$IPREX"); then
      DNSIP="Get $host.$domain DNS Failed."
    else
      DNSIP=$(echo $DNSTEST | grep -Eo "$IPREX" | tail -n1)
    fi
    echo "[DNS IP]:$DNSIP"
    if [ "$DNSIP" == "$URLIP" ]; then
      echo "IP SAME IN DNS, SKIP UPDATE."
      exit
    fi
  fi
  token="login_token=${API_TOKEN}&format=json&lang=en&error_on_empty=yes&domain=${domain}&sub_domain=${host}"
  Record="$(curl -4 -k $(if [ -n "$OUT" ]; then echo "--interface $OUT"; fi) -s -X POST https://dnsapi.cn/Record.List -d "${token}")"
  iferr="$(echo ${Record#*code} | cut -d'"' -f3)"
  if [ "$iferr" == "1" ]; then
    record_ip=$(echo ${Record#*value} | cut -d'"' -f3)
    echo "[API IP]:$record_ip"
    if [ "$record_ip" == "$URLIP" ]; then
      echo "IP SAME IN API, SKIP UPDATE."
      exit
    fi
    record_id=$(echo ${Record#*\"records\"\:\[\{\"id\"} | cut -d'"' -f2)
    record_line_id=$(echo ${Record#*line_id} | cut -d'"' -f3)
    echo "Start DDNS update for ${host} ..."
    ddns="$(curl -4 -k $(if [ -n "$OUT" ]; then echo "--interface $OUT"; fi) -s -X POST https://dnsapi.cn/Record.Ddns -d "${token}&record_id=${record_id}&record_line_id=${record_line_id}")"
    if [[ $? -eq "0" ]]; then
      update_flag="true"
    fi
    ddns_result="$(echo ${ddns#*message\"} | cut -d'"' -f2)"
    echo -n "DDNS update result: $ddns_result "
    msg_text="${msg_text}${host}: ${ddns_result}\n"
    echo $ddns | grep -Eo "$IPREX" | tail -n1
  else
    echo -n Get $host.$domain error :
    echo $(echo ${Record#*message\"}) | cut -d'"' -f2
  fi
done

if [[ ${update_flag} -eq "true" && $? -eq 0 ]]; then
  URL="https://gotify.example.com"
  TITLE="DDNS via DNSPod"
  PRIORITY="5"

  curl "$URL" \
    --silent --show-error \
    --data '{"message": "'"${msg_text}"'", "title": "'"${TITLE}"'", "priority":'"${PRIORITY}"', "extras": {"client::display": {"contentType": "text/markdown"}}}' \
    --header 'Content-Type: application/json'
fi
