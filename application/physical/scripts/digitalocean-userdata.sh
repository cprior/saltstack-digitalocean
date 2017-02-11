#!/usr/bin/env bash
#/**
# * This script is served with Jekyll from GitHub Pages
# * and used as "user-data" for DigitalOcean droplets
# *
# * @use #!/bin/bash
# * @use curl -L https://cprior.github.io/saltstack-digitalocean/digitalocean-userdata.sh | sh -s -- -M
# *
# * @see https://www.digitalocean.com/community/tutorials/an-introduction-to-droplet-metadata
# *
# *
# * Copyright (c) 2016 Christian Prior
# * Licensed under the MIT License. See LICENSE file in the project root for full license information.
# */

__SALTMASTER="False"

while getopts "Mv" opt; do
  case $opt in
    M) __SALTMASTER="True"
    ;;
    v) __VERBOSE="true"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2;
    ;;
  esac;
done

apt-get -y update

export HOSTNAME=$(curl -s http://169.254.169.254/metadata/v1/hostname)
export PUBLIC_IPV4=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
export PRIVATE_IPV4=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)

if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
fi
if ! grep '/swapfile' /etc/fstab >/dev/null; then
  echo '/swapfile   none    swap    sw    0   0' >> /etc/fstab
fi

sed -i 's/# en_DK.UTF-8 UTF-8/en_DK.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/# de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen
locale-gen


if [ "${__SALTMASTER}" == 'True' ]; then

apt-get -y install python-pyinotify python-pygit2


if [ ! -d /etc/salt/master.d ]; then mkdir -p /etc/salt/master.d ; fi
tee /etc/salt/master.d/90_fileserver_backend.conf <<EOF >/dev/null
fileserver_backend:
  - roots
  - git
EOF
tee /etc/salt/master.d/90_gitfs_remotes.conf <<EOF >/dev/null
gitfs_remotes:
  - https://github.com/cprior/saltstack-digitalocean.git:
    - root: application/physical/saltstack/states
    - base: master
EOF
# -M  Also install salt-master
# -L  Install the Apache Libcloud package if possible(required for salt-cloud)
# -P  Allow pip based installations.
# -U  If set, fully upgrade the system prior to bootstrapping salt
# -F  Allow copied files to overwrite existing(config, init.d, etc)
# -A  Pass the salt-master DNS name or IP.
curl -L https://bootstrap.saltstack.com | sudo sh -s -- -M -A ${PRIVATE_IPV4} -L -P -F -U -i "${HOSTNAME}" -p vim -p screen git v2016.11.2

#sleep 30;

#while true; do
#  if grep ${HOSTNAME} <(salt-key -L); then
#    salt-key -y -a ${HOSTNAME}
#    break;
#  else
#    sleep 1;
#  fi;
#done

else

curl -L https://bootstrap.saltstack.com | sudo sh -s -- -L -P -F -U -i "${HOSTNAME}" -p vim -p screen git v2016.11.2

fi

touch /tmp/finished.txt
