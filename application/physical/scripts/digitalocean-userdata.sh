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
__SALTMASTERINSTALL="False"
__SALTMASTERHOSTNAME="salt"

while getopts "MvA:" opt; do
  case $opt in
    M) __SALTMASTERINSTALL="True"
    ;;
    A) __SALTMASTERHOSTNAME=$OPTARG
    ;;
    v) __VERBOSE="true"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2;
    ;;
  esac;
done

apt-get -y update #&& apt-get -y upgrade

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


#if [ "${__SALTMASTERINSTALL}" == 'True' ]; then #bash
if test "${__SALTMASTERINSTALL}" = 'True' ; then #bourne shell

ssh-keygen -q -t rsa -N '' -f /root/.ssh/id_${HOSTNAME}

#https://www.linkedin.com/pulse/saltstacks-gitfs-ubuntu-denis-kalinin
apt-get install -y libcurl4-gnutls-dev cmake python-pip wget pkg-config openssl libssl-dev libssl1.0.0 libhttp-parser-dev libssh2-1-dev apt-utils
pip install --upgrade pip && pip install pyyaml
#http://www.pygit2.org/install.html
wget --quiet https://github.com/libgit2/libgit2/archive/v0.25.0.tar.gz --directory-prefix /tmp
cd /tmp && tar xzf ./v0.25.0.tar.gz
cd /tmp/libgit2-0.25.0 && cmake . && make && make install && ldconfig
pip install cffi && pip install pygit2
cd

apt-get -y install python-pyinotify python-pygit2

if [ ! -d /etc/salt/master.d ]; then mkdir -p /etc/salt/master.d ; fi
tee /etc/salt/master.d/90_ext_pillar.conf <<EOF >/dev/null
ext_pillar:
  - git:
    - master git@bitbucket.org:cprior_/cpr.git:
      - root: application/physical/saltstack/assets/srv/pillar
      - pubkey: /root/.ssh/id_${HOSTNAME}.pub
      - privkey: /root/.ssh/id_${HOSTNAME}
EOF
tee /etc/salt/master.d/90_file_roots.conf <<EOF >/dev/null
file_roots:
  base:
    - /srv/salt
    - /srv/formulas/users-formula
EOF
tee /etc/salt/master.d/90_fileserver_backend.conf <<EOF >/dev/null
fileserver_backend:
  - roots
  - git
EOF
tee /etc/salt/master.d/90_gitfs_remotes.conf  <<EOF >/dev/null
gitfs_remotes:
  - https://github.com/cprior/saltstack-digitalocean.git:
    - root: application/physical/saltstack/states
    - base: master
  - git@bitbucket.org:cprior_/cpr.git:
    - root: application/physical/saltstack/assets/srv/salt
    - base: master
    - pubkey: /root/.ssh/id_${HOSTNAME}.pub
    - privkey: /root/.ssh/id_${HOSTNAME}
  - git@bitbucket.org:cprior_/cpr.git:
    - name: usersformula
    - root: application/physical/saltstack/assets/srv/formulas/users-formula
    - base: master
    - pubkey: /root/.ssh/id_${HOSTNAME}.pub
    - privkey: /root/.ssh/id_${HOSTNAME}
EOF
# -M  Also install salt-master
# -L  Install the Apache Libcloud package if possible(required for salt-cloud)
# -P  Allow pip based installations.
# -U  If set, fully upgrade the system prior to bootstrapping salt #####do not use because of some apt-get lock
# -F  Allow copied files to overwrite existing(config, init.d, etc)
# -A  Pass the salt-master DNS name or IP.
curl -L https://bootstrap.saltstack.com | sudo sh -s -- -M -A ${PRIVATE_IPV4} -L -P -F -i "${HOSTNAME}" -p vim -p screen git v2016.11.2

salt-call --local ssh.set_known_host root bitbucket.org

sleep 16
systemctl restart salt-master.service

for s in 5 5 10 20 60; do
  if [ -f /etc/salt/pki/master/minions_pre/${HOSTNAME} ]; then
    salt-key -y -a ${HOSTNAME}
    salt-run fileserver.clear_cache backend=git
    salt-run cache.clear_git_lock gitfs type=update
    salt-call --local saltutil.refresh_pillar
    break;
  else
    sleep ${s}
  fi
done


#test "${__SALTMASTERINSTALL}" = 'True'
else

curl -L https://bootstrap.saltstack.com | sudo sh -s -- -A ${__SALTMASTERHOSTNAME}-L -P -F -i "${HOSTNAME}" -p vim -p screen git v2016.11.2

fi

if [ ! -d /srv/salt ]; then mkdir -p /srv/salt.d ; fi
if [ ! -d /srv/pillar ]; then mkdir -p /srv/pillar ; fi
if [ ! -d /srv/formulas ]; then mkdir -p /srv/formulas ; fi

touch /tmp/finished.txt
