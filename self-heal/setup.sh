#!/bin/bash

# This script is for setting up self healing infra.
# Steps as below:
# 1. Running RabbitMQ docker-compose file and fetching it IP

cd rabbitmq
docker network create isolated_nw
docker-compose up -d
rabbit_container_id=$(docker ps -aqf "name=rabbitmq_q")
echo $rabbit_container_id
rabbitmq_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $rabbit_container_id)
echo $rabbitmq_ip

#2. Updating RabbitMQ in docker-entrypoint.sh and building new alerta image
cd ../alerta
sed -i "s/rabbitmq_ip/$rabbitmq_ip/gi" docker-entrypoint.sh
#VCS_REF=$(git rev-parse --short HEAD)
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VERSION=7.0.0
docker build . -t alerta-web:latest --build-arg VCS_REF=$VCS_REF --build-arg BUILD_DATE=$BUILD_DATE --build-arg VERSION=$VERSION

#3. Running Alerta in same network in which RabbitMQ is running
docker-compose up -d

#4. Runnning stackstorm in same network and updating rabbitmq.yml file
cd ../stackstorm
make env
docker-compose up -d
docker exec -it stackstorm_stackstorm_1 bash -c "sleep 0.5; if [ ! -f "/opt/stackstorm/configs/rabbitmq.yaml" ]; then
  cat >"/opt/stackstorm/configs/rabbitmq.yaml" << EOF
---
sensor_config:
	host: '"rabbitmq_q"'
	username: '"guest"'
	password: '"guest"'
	rabbitmq_queue_sensor:
		queues:
			- '"alerta-msg"'
		deserialization_method: '"json"'
EOF
fi; sleep 100; st2ctl reload; sleep 10; st2ctl reload"
