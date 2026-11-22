#!/bin/bash
# Runs inside zdemo-ctrl: a small company network for the Access Canvas demo.
set -e
Z=/var/openziti/ziti-bin/ziti
until $Z edge login https://zdemo-ctrl:1280 -u admin -p "$ZITI_PWD" -y >/dev/null 2>&1; do sleep 2; done
until $Z edge list edge-routers -j 2>/dev/null | grep -Eq "\"isOnline\": ?true"; do sleep 2; done
mkdir -p /tmp/ids && cd /tmp/ids
$Z edge create edge-router-policy all-endpoints-all-routers --identity-roles '#all' --edge-router-roles '#all' >/dev/null
$Z edge create service-edge-router-policy all-services-all-routers --service-roles '#all' --edge-router-roles '#all' >/dev/null

svc() { # name attrs host port intercept
  $Z edge create config "$1.intercept.v1" intercept.v1 "{\"protocols\":[\"tcp\"],\"addresses\":[\"$5\"],\"portRanges\":[{\"low\":$4,\"high\":$4}]}" >/dev/null
  $Z edge create config "$1.host.v1" host.v1 "{\"protocol\":\"tcp\",\"address\":\"$3\",\"port\":$4}" >/dev/null
  $Z edge create service "$1" --configs "$1.intercept.v1,$1.host.v1" --role-attributes "$2" >/dev/null
}
svc wiki-https web 127.0.0.1 443 wiki.ziti
svc grafana web,monitoring 127.0.0.1 3000 grafana.ziti
svc billing-db-postgres databases 127.0.0.1 5432 billing-db.ziti
svc file-share-smb files 127.0.0.1 445 files.ziti

ident() { # name attrs enroll?
  if [ -n "$2" ]; then $Z edge create identity "$1" --role-attributes "$2" -o "$1.jwt" >/dev/null; else $Z edge create identity "$1" -o "$1.jwt" >/dev/null; fi
  if [ "$3" = yes ]; then $Z edge enroll "$1.jwt" -o "$1.json" >/dev/null 2>&1; fi
}
ident alice-laptop engineering yes
ident bob-laptop engineering yes
ident carol-laptop finance yes
ident erin-laptop engineering,finance yes
ident dave-laptop "" no
ident web-01 web-hosts yes
ident db-01 db-hosts yes
ident files-01 file-hosts yes

$Z edge create service-policy web-bind Bind --identity-roles '#web-hosts' --service-roles '#web' >/dev/null
$Z edge create service-policy engineering-dial-web Dial --identity-roles '#engineering' --service-roles '#web' >/dev/null
$Z edge create service-policy databases-bind Bind --identity-roles '#db-hosts' --service-roles '#databases' >/dev/null
$Z edge create service-policy dbas-dial-databases Dial --identity-roles '#dbas' --service-roles '#databases' >/dev/null
$Z edge create service-policy files-bind Bind --identity-roles '#file-hosts' --service-roles '#files' >/dev/null

# Hosting identities online: a host-only tunneler for each server.
for h in web-01 db-01 files-01; do nohup $Z tunnel host --identity "$h.json" >/tmp/$h.log 2>&1 & done
sleep 6
echo seeded
