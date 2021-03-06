#!/bin/bash

# This script is for setting up self healing infra.
# Steps as below:
# 1. Running RabbitMQ docker-compose file and fetching it IP

cd rabbitmq
docker network create isolated_nw
docker-compose up -d

#2. Updating RabbitMQ in docker-entrypoint.sh and building new alerta image
cd ../alerta
#VCS_REF=$(git rev-parse --short HEAD)
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VERSION=7.0.0
docker build . -t alerta-web:latest --build-arg VCS_REF=$VCS_REF --build-arg BUILD_DATE=$BUILD_DATE --build-arg VERSION=$VERSION

#3. Running Alerta in same network in which RabbitMQ is running
docker-compose up -d
docker exec -it rabbitmq_rabbitmq_q_1 bash -c "sleep 0.5;rabbitmqadmin -u guest -p guest declare exchange name=alerta-msg type=fanout;rabbitmqadmin -u guest -p guest declare queue name=alerta-msg;rabbitmqadmin -u guest -p guest declare binding source=alerta-msg destination=alerta-msg"

#4. Runnning stackstorm in same network and updating rabbitmq.yml file
cd ../stackstorm
make env
docker-compose up -d
docker exec -it stackstorm_stackstorm_1 bash -c "sleep 10;if [ ! -f "/opt/stackstorm/configs/rabbitmq.yaml" ]; then
  cat >"/opt/stackstorm/configs/rabbitmq.yaml" << EOF
---
sensor_config:
       host: 'rabbitmq_rabbitmq_q_1'
       username: 'guest'
       password: 'guest'
       rabbitmq_queue_sensor:
                queues:
                       - 'alerta-msg'
                deserialization_method: 'json'
EOF
fi;sleep 50;st2 pack install rabbitmq;sleep 100; st2ctl reload; sleep 10; st2ctl reload"
