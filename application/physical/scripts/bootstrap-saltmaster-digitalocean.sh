#!/usr/bin/env bash
#/** 
#  * This script sets up a new DitigalOcean instance with a SaltStack salt master.
#  * 
#  * Copyright (c) 2016 Christian Prior
#  * Licensed under the MIT License. See LICENSE file in the project root for full license information.
#  * 
#  * ToDo: When stable, put in bootstrap script with Jekyll to user-data call curl bootstrap.sh | sh
#  */

set -o nounset #exit on undeclared variable

if env | grep -q ^DIGITALOCEAN_ACCESS_TOKEN=
then
  __DIGITALOCEAN_ACCESS_TOKEN=${DIGITALOCEAN_ACCESS_TOKEN}
else
  __DIGITALOCEAN_ACCESS_TOKEN=''
fi

if env | grep -q ^DIGITALOCEAN_REGION=
then
  __DIGITALOCEAN_REGION=${DIGITALOCEAN_REGION}
else
  __DIGITALOCEAN_REGION='fra1' #r
fi

__DROPLETHOSTNAME='saltmaster'  #h
__DROPLETCREATERETVAL=''
__DROPLETCREATEID=''
__DROPLETCREATENAME=''
__VERBOSE='False'

__SILENTLOGIN="False"
__TMPFILE=$(mktemp _tmp_${__DROPLETHOSTNAME}.XXXXX) || exit 1
read -d '' __USER_DATA <<EOF
#!/bin/bash

if [ ! -f /swapfile ]; then
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
fi
if grep '/swapfile' /etc/fstab; then
echo "/swapfile already in fstab"
else
echo '/swapfile   none    swap    sw    0   0' >> /etc/fstab
fi

sed -i 's/# en_DK.UTF-8 UTF-8/en_DK.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/# de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

apt-get install python-pyinotify
curl -o bootstrap_salt.sh -L https://bootstrap.saltstack.com
# -M  Also install salt-master
# -L  Install the Apache Libcloud package if possible(required for salt-cloud)
# -P  Allow pip based installations.
# -U  If set, fully upgrade the system prior to bootstrapping salt
# -F  Allow copied files to overwrite existing(config, init.d, etc)
# -A  Pass the salt-master DNS name or IP. This will be stored under \${BS_SALT_ETC_DIR}/minion.d/99-master-address.conf
sh bootstrap_salt.sh -M -L -P -F -U -p vim -p screen git v2016.3.2

EOF
cat << EOF > ${__TMPFILE}
${__USER_DATA}
EOF

#http://stackoverflow.com/questions/18215973/how-to-check-if-running-as-root-in-a-bash-script
#The script needs root permissions to create the filesystem and manipulate the installation on the SD card
_SUDO=''
###########if (( $EUID != 0 )); then
###########  while true; do sudo ls;
###########  #clear;
###########  break; done
###########  _SUDO='sudo'
###########fi; #from now on this is possible: $SUDO some_command

trap do_cleanup EXIT

do_cleanup() {
  echo "cleanup() called"
  rm ${__TMPFILE}
}

while getopts "t:h:r:" opt; do
  case $opt in
    t) __DIGITALOCEAN_ACCESS_TOKEN=$OPTARG
    ;;
    h) __DROPLETHOSTNAME=$OPTARG
    ;;
    r) __DIGITALOCEAN_REGION=$OPTARG
    ;;
    v) __VERBOSE="true"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2; echo -n "continuing "; sleep 1; echo -n "."; sleep 1; echo -n "."; sleep 1; echo ".";
    ;;
  esac;
done


if [ "${#__DIGITALOCEAN_ACCESS_TOKEN}" -eq 64 ]; then
  accessstatus=$(curl -X GET                                                    \
                      -w %{http_code}                                           \
                      -H "Content-Type: application/json"                       \
                      -H "Authorization: Bearer ${__DIGITALOCEAN_ACCESS_TOKEN}" \
                      --silent                                                  \
                      --output /dev/null                                        \
                      "https://api.digitalocean.com/v2/account" );
  #echo "http status was: ${accessstatus}"
  if [ ${accessstatus:0:1} = "2" ]; then
    __SILENTTOKEN="True"
  else
    #no valid token was supplied silently by ENV or -t
    __SILENTTOKEN="False"
  fi
  accessstatus=''
fi

if [ "${__SILENTTOKEN}" = "False" ]; then
  while true; do
    read -e -p "Which valid DigitalOcean access token to use? " -i "${__DIGITALOCEAN_ACCESS_TOKEN}" __DIGITALOCEAN_ACCESS_TOKEN
    if [ "${#__DIGITALOCEAN_ACCESS_TOKEN}" -eq 64 ]; then
      accessstatus=$(curl --silent -X GET -w %{http_code} -H "Content-Type: application/json" -H "Authorization: Bearer ${__DIGITALOCEAN_ACCESS_TOKEN}" --output /dev/null "https://api.digitalocean.com/v2/account" )
      if [ ${accessstatus:0:1} = "2" ]; then
        echo "Token valid."; sleep 1
        break;
      else
        echo "Not valid, try again."; sleep 1
      fi
      accessstatus=''
    else
      echo "${__DIGITALOCEAN_ACCESS_TOKEN} is not valid, should be 64 characters"
    fi
  done
fi

#ask for (confirmation of) hostname
while true; do
  read -e -p "Which hostname shall the saltmaster have? " -i "${__DROPLETHOSTNAME}" __DROPLETHOSTNAME
  if [ ! -z ${__DROPLETHOSTNAME} ]; then break; fi
done

#ask for (confirmation of) region
while true; do
  read -e -p "Which datacenter region should be used? " -i "${__DIGITALOCEAN_REGION}" __DIGITALOCEAN_REGION
  if [ ! -z ${__DIGITALOCEAN_REGION} ]; then break; fi
done

clear
echo "Test output:"
curl --silent -X GET -H "Content-Type: application/json" -H "Authorization: Bearer ${__DIGITALOCEAN_ACCESS_TOKEN}" "https://api.digitalocean.com/v2/account"
echo "";

cat $__TMPFILE;
echo ""
while true; do
  read -p "Do you want to edit the file? [yN] " yn
  [ -z "$yn" ] && yn="n"
  case $yn in
    [Yy]* ) vim $__TMPFILE;
              break;;
    [Nn]* ) echo "OK."; break;;
    * ) echo "Please answer yes or no";;
  esac
done
__USER_DATA="$(cat ${__TMPFILE}; printf -)"
__USER_DATA="${__USER_DATA%-}"
echo "${__USER_DATA}"

#make machine SSH key
#check for existing storage volume
needlevolumeid='';
needlevolume="volume-fra1-${__DROPLETHOSTNAME}";
volumeexists="False";

volumemetatotal=$(curl --silent -X GET -H "Content-Type: application/json" -H "Authorization: Bearer ${DIGITALOCEAN_ACCESS_TOKEN}" "https://api.digitalocean.com/v2/volumes" | jq '.meta.total'); echo ${volumemetatotal};

for i in $(seq 1 ${volumemetatotal}); do

  volume=$(curl --silent -X GET -H "Content-Type: application/json" -H "Authorization: Bearer ${DIGITALOCEAN_ACCESS_TOKEN}" "https://api.digitalocean.com/v2/volumes?per_page=1&page=${i}");
  volumeid=$(echo $volume | jq '.volumes[].id' | sed -e 's/^"//' -e 's/"$//'); echo $volumeid;
  volumename=$(echo $volume | jq '.volumes[].name' | sed -e 's/^"//' -e 's/"$//' ); echo $volumename;
  echo "-------"; echo "${needlevolume} - ${volumename}";

  if [ "$needlevolume" == "$volumename" ]; then volumeexists="True"; echo "Found ${volumename}!";
    needlevolumeid=${volumeid};
  fi;

done;

volumecreateretval=''
volumeretval=''
if [ "${volumeexists}" == "False" ]; then echo "Going to create ${needlevolume}!";
  volumecreateretval=$(curl --silent -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${DIGITALOCEAN_ACCESS_TOKEN}" -d '{"size_gigabytes":1, "name": "'${needlevolume}'", "description": "Block store for '${__DROPLETHOSTNAME}'", "region": "fra1"}' "https://api.digitalocean.com/v2/volumes");
  echo ${volumecreateretval} | jq '.'
else
  echo "${needlevolume} already exists!";
  echo "Not creating a volume."
  volumeretval=$(curl --silent -X GET -H "Content-Type: application/json" -H "Authorization: Bearer ${DIGITALOCEAN_ACCESS_TOKEN}" "https://api.digitalocean.com/v2/volumes/${needlevolumeid}");
  echo ${volumeretval} | jq '.'
fi
#attach storage volume
echo "todo: attach ${needlevolumeid}"




#get droplet hostnames
#check if intended hostname is existing

dropletmetatotal=0;
needledroplet=${__DROPLETHOSTNAME}
needledropletid=''
dropletexists="False";
dropletmetatotal=$(curl --silent -X GET -H "Content-Type: application/json" -H "Authorization: Bearer ${DIGITALOCEAN_ACCESS_TOKEN}" "https://api.digitalocean.com/v2/droplets" | jq '.meta.total');
echo "droplets total: ${dropletmetatotal}";

for i in $(seq 1 ${dropletmetatotal}); do
droplet=$(curl --silent -X GET -H "Content-Type: application/json" -H "Authorization: Bearer ${DIGITALOCEAN_ACCESS_TOKEN}" "https://api.digitalocean.com/v2/droplets?per_page=1&page=${i}");
dropletid=$(echo $droplet | jq '.droplets[].id' | sed -e 's/^"//' -e 's/"$//'); echo $dropletid;
dropletname=$(echo $droplet | jq '.droplets[].name' | sed -e 's/^"//' -e 's/"$//' ); echo $dropletname;
echo "-------"; echo "${needledroplet} - ${dropletname}";

if [ "$needledroplet" == "$dropletname" ]; then
dropletexists="True";
echo "Found ${dropletname}!";
needledropletid=${dropletid};
echo "needledropletid: ${needledropletid}"
fi;
done;


dropletcreateretval=''
dropletretval=''
if [ "${dropletexists}" == "False" ]; then echo "Going to create ${needledroplet}!";
  dropletcreateretval=$(curl --silent -X POST https://api.digitalocean.com/v2/droplets \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${__DIGITALOCEAN_ACCESS_TOKEN}" \
      -d '{ "name":"'${__DROPLETHOSTNAME}'",
            "region":"fra1", "size":"512mb",
            "image":"ubuntu-16-04-x64",
            "backups":false,
            "ipv6":false,
            "private_networking":true,
            "user_data":
"'"$(cat ${__TMPFILE} | sed -e 's/"/\\"/g' )"'",
"ssh_keys":[ "dc:44:9f:11:e6:8a:17:3b:70:cd:fb:22:d1:64:18:4a" ]}'
);
  echo ${dropletcreateretval} | jq '.'
else
  echo "${needledroplet} already exists!";
  echo "Not creating a volume."
  dropletretval=$(curl --silent -X GET -H "Content-Type: application/json" -H "Authorization: Bearer ${DIGITALOCEAN_ACCESS_TOKEN}" "https://api.digitalocean.com/v2/droplets/${needledropletid}");
  echo ${dropletretval} | jq '.'
fi


echo "needledropletid: ${needledropletid}"
echo "needlevolumeid: ${needlevolumeid}"
echo "token: ${DIGITALOCEAN_ACCESS_TOKEN}"

echo "attached volumes:"
dropletvolumeids=$(echo $dropletretval | jq '.droplet.volume_ids[]')
if [ -z "${dropletvolumeids}" ]; then
  echo "no volumes attached."
  curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${DIGITALOCEAN_ACCESS_TOKEN}" -d '{"type": "attach", "droplet_id": '${needledropletid}', "region": "fra1"}' "https://api.digitalocean.com/v2/volumes/${needlevolumeid}/actions"
else
  echo "some volume(s) attached"
fi

