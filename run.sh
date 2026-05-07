#!/usr/bin/env bash

# If we're running in Strimzi, we should delegate to the Strimzi-provided entrypoint
# Strimzi sets various environment variables. STRIMZI_KAFKA_GC_LOG_OPTS is a common one
# set by the operator. STRIMZI_BROKER_ID is specific to the broker.
if [[ -n "${STRIMZI_BROKER_ID-}" || -n "${STRIMZI_KAFKA_GC_LOG_OPTS-}" || -n "${STRIMZI_KAFKA_JVM_PERFORMANCE_OPTS-}" || -n "${STRIMZI_KAFKA_LOG4J_OPTS-}" ]]; then
  if [[ -f "/opt/kafka/kafka_run.sh" ]]; then
    echo "===> Strimzi detected, delegating to /opt/kafka/kafka_run.sh"
    exec /opt/kafka/kafka_run.sh "$@"
  fi
fi

if [[ -n "${KAFKA_ZOOKEEPER_CONNECT-}" ]]; then
  cp /opt/kafka/config/server.properties /etc/kafka/docker/server.properties;
else
  cp /opt/kafka/config/kraft/server.properties /etc/kafka/docker/server.properties;
fi

exec /etc/kafka/docker/run "$@"