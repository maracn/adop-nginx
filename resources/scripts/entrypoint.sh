#!/bin/bash
set -e

cp -R /resources/configuration/* /etc/nginx/
cp -R /resources/release_note/* /usr/share/nginx/html/

#If SSL is enabled and the cert doesn't already exist, we'll generate one.
#We will also disable the old HTTP config, forcing all traffic over HTTPS.

#Removing case sensitivity
shopt -s nocasematch

if [ "$SSL_ENABLED" == "TRUE" ] ; then 
    mv /etc/nginx/sites-enabled/tools-context.conf /etc/nginx/sites-enabled/tools-context.off ;
    if [ ! -a /etc/nginx/ssl/adop-nginx.crt ]; then 
      openssl req -x509 -nodes -days 1095 -newkey rsa:2048 -keyout /etc/nginx/ssl/adop-nginx.key -out /etc/nginx/ssl/adop-nginx.crt -subj "/C=IE/ST=Co. Dublin/L=Dublin/O=Accenture" ;
    fi
fi

# Auto populate the release note page with the blueprints
/resources/scripts/reload_release_notes.sh

# Copy and replace tokens
perl -p -i -e 's/###([^#]+)###/defined $ENV{$1} ? $ENV{$1} : $&/eg' < "/templates/configuration/nginx.conf" 2> /dev/null 1> "/etc/nginx/nginx.conf"

# wait for all downstream services to be up and running
# This is a temporary solution that allows NGINX to wait for all dependencies and after start, this should be removed when 
# the depends_on see https://github.com/docker/compose/pull/686 and https://github.com/docker/compose/issues/2682 is introduced
# on docker compose
SLEEP_TIME=2
declare -a DEPENDENCIES=( "kibana:5601" "gerrit:8080/gerrit" "jenkins:8080" "sonar:9000" "sensu-uchiwa:3000" "nexus:8081" )
for d in ${DEPENDENCIES[@]}; do 
  echo "waiting for $d to be available";
  # use wget as already installed... 
  # We are checking for response codes that are not of class 5xx the most common are below, the list does not 
  # try to be exaustive, it only consider the response code that will guarantee NGINX to start when all dependencies are 
  # available.
  until wget -S -O - http://$d 2>&1 | grep "HTTP/" | awk '{print $2}' | grep "200\|404\|403\|401\|301\|302" &> /dev/null
  do
      echo "$d unavailable, sleeping for ${SLEEP_TIME}"
      sleep "${SLEEP_TIME}"
  done
done

/usr/sbin/nginx
