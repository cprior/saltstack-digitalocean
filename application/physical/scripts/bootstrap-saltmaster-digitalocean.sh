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

curl -L https://cprior.github.io/saltstack-digitalocean/digitalocean-userdata.sh -M | sh

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











echo "${DIGITALOCEAN_ACCESS_TOKEN}"
needlename=''
needleid=''
name=''
id=''
count=0
exists="False"
__DROPLETHOSTNAME='saltmaster'
__DIGITALOCEAN_REGION='fra1'

function myGetCurl {
  if [ "$1" == "volume" -o "$1" == "droplet" -o "$1" == "key" ] && [  ! -z "$2" -a ${2:0:28} = "https://api.digitalocean.com" ] ; then
    curl --silent -X GET -H "Content-Type: application/json" -H "Authorization: Bearer ${DIGITALOCEAN_ACCESS_TOKEN}" "$2"
  else echo "No url given"; fi
}

function myPostCurl {

  if [ -f "./data.json" ]; then
    rm "./data.json" ;
  fi;

  if [ "$1" == "volume" ]; then
    sed 's/^[ ]*//' <<EOF | tee "./data.json" > /dev/null
    {
    "size_gigabytes":1,
    "name": "${1}-${__DIGITALOCEAN_REGION}-${__DROPLETHOSTNAME}",
    "description": "${1} for ${__DROPLETHOSTNAME} $(date +'%Y-%m-%d %H:%M:%S') by ${USER} $0",
    "region": "${__DIGITALOCEAN_REGION}"
    }
EOF
  elif [ "$1" == "droplet" ]; then
    sed 's/^[ ]*//' <<EOF | tee "./data.json" > /dev/null
    {
    "name":"${__DROPLETHOSTNAME}",
    "region": "${__DIGITALOCEAN_REGION}",
    "size":"512mb",
    "image":"ubuntu-16-04-x64",
    "backups":false,
    "ipv6":false,
    "private_networking":true,
    "user_data":"",
    "ssh_keys":[ "dc:44:9f:11:e6:8a:17:3b:70:cd:fb:22:d1:64:18:4a" ]
    }
EOF
  fi #end if $1 volume elif droplet

  if [ "$1" == "volume" -o "$1" == "droplet" -o "$1" == "key" ] && [ ! -z "$2" -a ${2:0:28} = "https://api.digitalocean.com" ]; then
    curl --silent -X POST -d @data.json -H "Content-Type: application/json" -H "Authorization: Bearer ${DIGITALOCEAN_ACCESS_TOKEN}" "$2"
  else
    echo "No url given or data empty";
  fi
}

#myPostCurl droplet https://api.digitalocean.com/v2/droplets
#myPostCurl volume https://api.digitalocean.com/v2/volumes 
#myGetCurl volume https://api.digitalocean.com/v2/volumes


#/**
# * Make call with curl to DigitalOcean API
# * 
# * reads and sets variables from global scope
# * 
# * createIfNotExists volume
# * createIfNotExists droplet
# */
function createIfNotExists {

  if [ "$1" == "volume" -o "$1" == "droplet" ]; then

    if [ "$1" == "volume" ]; then

      name="volume-${__DIGITALOCEAN_REGION}-${__DROPLETHOSTNAME}"
      count=$(myGetCurl volume https://api.digitalocean.com/v2/volumes | jq '.meta.total');
      url="https://api.digitalocean.com/v2/volumes"

    elif [ "$1" == "droplet" ]; then

      name="${__DROPLETHOSTNAME}"
      count=$(myGetCurl volume https://api.digitalocean.com/v2/droplets | jq '.meta.total');
      url="https://api.digitalocean.com/v2/droplets"

    fi

    resource=''
    exists="False";
    for i in $(seq 1 ${count}); do
      resource=$( myGetCurl ${1} "${url}?per_page=1&page=${i}");
      _id=$(echo $resource | jq ".${1}s[].id" | sed -e 's/^"//' -e 's/"$//');
      _name=$(echo $resource | jq ".${1}s[].name" | sed -e 's/^"//' -e 's/"$//' );
      if [ "$_name" == "$name" ]; then
        echo "${name} exists."
        exists="True";
        needleid=${_id};
        break;
      fi;
    done;

    if [ "${exists}" == "False" ]; then
      echo "Going to create $1:";
      eval $1=$( myPostCurl "$1" "$url" );
      return 0;
    else
      eval $1=$(myGetCurl "$1" "${url}/${needleid}");
      return 0;
    fi

  else
    echo "Wrong argument." ;
  fi
}



#/**
# * create volume if not exists
# */

createIfNotExists volume
echo $volume | jq '.volume.name'












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

