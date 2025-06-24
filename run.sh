#!/usr/bin/env bash

if [[ -n "${KAFKA_ZOOKEEPER_CONNECT-}" ]] then
  cp /opt/kafka/config/server.properties /etc/kafka/docker/server.properties;
else
  cp /opt/kafka/config/kraft/server.properties /etc/kafka/docker/server.properties;
fi

exec /etc/kafka/docker/run