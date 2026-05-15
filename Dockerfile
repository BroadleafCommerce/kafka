###############################################################################
#  Licensed to the Apache Software Foundation (ASF) under one
#  or more contributor license agreements.  See the NOTICE file
#  distributed with this work for additional information
#  regarding copyright ownership.  The ASF licenses this file
#  to you under the Apache License, Version 2.0 (the
#  "License"); you may not use this file except in compliance
#  with the License.  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

# Stage 1: Build Java Shared Archive (JSA)
FROM repository.broadleafcommerce.com:5001/broadleaf/kafka-kraft-base:wolfi-5 AS build-jsa

USER root

COPY docker/jvm/jsa_launch /etc/kafka/docker/jsa_launch

ARG DISTRO_NAME=kafka_2.13-3.9.2

COPY core/build/distributions/$DISTRO_NAME.tgz /

RUN set -eux ; \
    tar xfz /$DISTRO_NAME.tgz -C /opt/kafka --strip-components 1;

# Generate jsa files using dynamic CDS for kafka server start command and kafka storage format command
WORKDIR /
RUN /etc/kafka/docker/jsa_launch

# Stage 2: Extract Strimzi components from the official Strimzi Kafka image
# IMPORTANT: When updating Kafka - review Strimzi and Kafka compatibility matrix 
# to ensure appropriate strimzi source and image versions: https://strimzi.io/downloads/
FROM quay.io/strimzi/kafka:0.45.2-kafka-3.9.2 AS strimzi-source-extractor

USER root

# Create directories to copy content out
RUN mkdir -p /tmp/strimzi-extracted/scripts \
             /tmp/strimzi-extracted/kafka-exporter \
             /tmp/strimzi-extracted/prometheus-jmx-exporter \
             /tmp/strimzi-extracted/kafka-libs \
             /tmp/strimzi-extracted/cruise-control \
             /tmp/strimzi-extracted/usr-bin             

#####
# Add Kafka Scripts
#####
RUN cp -r /opt/kafka/* /tmp/strimzi-extracted/scripts
RUN rm -rf /tmp/strimzi-extracted/scripts/LICENSE /tmp/strimzi-extracted/scripts/NOTICE /tmp/strimzi-extracted/scripts/bin /tmp/strimzi-extracted/scripts/config /tmp/strimzi-extracted/scripts/libs /tmp/strimzi-extracted/scripts/licenses /tmp/strimzi-extracted/scripts/plugins /tmp/strimzi-extracted/scripts/site-docs

#####
# Add Prometheus JMX Exporter
#####
RUN if [ -d /opt/prometheus-jmx-exporter ]; then cp -r /opt/prometheus-jmx-exporter/* /tmp/strimzi-extracted/prometheus-jmx-exporter; fi

#####
# Add Strimzi agents, 3rd party libs, & Other Kafka Libs
#####
RUN if [ -d /opt/kafka/libs ]; then cp -r /opt/kafka/libs/* /tmp/strimzi-extracted/kafka-libs; fi

#####
# Add Cruise Control
#####
RUN if [ -d /opt/cruise-control ]; then cp -r /opt/cruise-control/* /tmp/strimzi-extracted/cruise-control; fi

#####
# Cleanup vulnerable jars
#####
RUN find /tmp/strimzi-extracted -name "commons-lang-2*.jar" -delete

# Stage 3: Main Kafka image build
FROM repository.broadleafcommerce.com:5001/broadleaf/kafka-kraft-base:wolfi-5

# exposed ports
EXPOSE 9092

USER root

LABEL org.label-schema.name="kafka" \
      org.label-schema.description="Apache Kafka" \
      org.label-schema.vcs-url="https://github.com/apache/kafka" \
      maintainer="Apache Kafka"

ARG DISTRO_NAME=kafka_2.13-3.9.2

COPY core/build/distributions/$DISTRO_NAME.tgz /

# NOTE - because we aim to be compatible with both OpenShift (runs as random UID) and standard
# Kubernetes, we cannot have any user-specific configuration in our Dockerfile.
# We assume appuser UID for standard Kubernetes, and an arbitrary UID + root group (0)
# for OpenShift. Thus, grant both of those ownership here.
RUN set -eux ; \
    # 1. Continue with Kafka installation and configuration
    tar xfz /$DISTRO_NAME.tgz -C /opt/kafka --strip-components 1; \
    chown appuser:0 -R /usr/logs /opt/kafka /mnt/shared/config; \
    chown appuser:0 -R /var/lib/kafka /etc/kafka/secrets /etc/kafka; \
    chmod -R ug+w /etc/kafka /var/lib/kafka /etc/kafka/secrets /opt/kafka; \
    cp /opt/kafka/config/log4j.properties /etc/kafka/docker/log4j.properties; \
    cp /opt/kafka/config/tools-log4j.properties /etc/kafka/docker/tools-log4j.properties; \
    rm /$DISTRO_NAME.tgz;

#####
# Needed to support an adapted entrypoint in support of
# backwared-compatible BLC installations that may have been referencing
# a Confluent-based Kafka Image, with added support for initialization 
# via the Strimzi Operator for K8 installations (https://strimzi.io/)
#####    
COPY --from=build-jsa /kafka.jsa /opt/kafka/kafka.jsa
COPY --from=build-jsa /storage.jsa /opt/kafka/storage.jsa
COPY --chown=appuser:0 docker/resources/common-scripts /etc/kafka/docker
RUN chmod +x /etc/kafka/docker/copy-jars.sh
COPY --chown=appuser:0 docker/jvm/launch /etc/kafka/docker/launch

VOLUME ["/etc/kafka/secrets", "/var/lib/kafka/data", "/mnt/shared/config"]

RUN /etc/kafka/docker/hosts.sh

COPY --chown=appuser:0 run.sh /etc/confluent/docker/run
RUN chmod 755 /etc/confluent/docker/run

# --- Start of Strimzi Support ---

ENV KAFKA_HOME=/opt/kafka
ENV KAFKA_VERSION=3.9.2
ENV STRIMZI_VERSION=0.45.2
ENV KAFKA_EXPORTER_HOME=/opt/kafka-exporter
ENV JMX_EXPORTER_HOME=/opt/prometheus-jmx-exporter
ENV CRUISE_CONTROL_HOME=/opt/cruise-control

# Create necessary directories for Strimzi components
RUN mkdir -p ${KAFKA_HOME}/strimzi-scripts \
             ${KAFKA_HOME}/strimzi-kafka-libs \
             ${KAFKA_EXPORTER_HOME} \
             ${CRUISE_CONTROL_HOME} \
             ${JMX_EXPORTER_HOME} \
             ${KAFKA_HOME}/cluster-ca-certs \
             ${KAFKA_HOME}/broker-certs \
             ${KAFKA_HOME}/client-ca-certs \
             ${KAFKA_HOME}/certificates \
             ${KAFKA_HOME}/custom-config && \
    chown -R appuser:0 ${KAFKA_HOME}/cluster-ca-certs \
                       ${KAFKA_HOME}/broker-certs \
                       ${KAFKA_HOME}/client-ca-certs \
                       ${KAFKA_HOME}/certificates \
                       ${KAFKA_HOME}/custom-config && \
    chmod -R ug+w ${KAFKA_HOME}/cluster-ca-certs \
                  ${KAFKA_HOME}/broker-certs \
                  ${KAFKA_HOME}/client-ca-certs \
                  ${KAFKA_HOME}/certificates \
                  ${KAFKA_HOME}/custom-config

# Copy Strimzi Kafka scripts
COPY --from=strimzi-source-extractor --chown=appuser:0 /tmp/strimzi-extracted/scripts ${KAFKA_HOME}/strimzi-scripts
RUN chmod -R +x ${KAFKA_HOME}/strimzi-scripts
RUN mv ${KAFKA_HOME}/strimzi-scripts/* ${KAFKA_HOME}
RUN rm -rf ${KAFKA_HOME}/strimzi-scripts

# Copy Prometheus JMX Exporter directory
COPY --from=strimzi-source-extractor --chown=appuser:0 /tmp/strimzi-extracted/prometheus-jmx-exporter ${JMX_EXPORTER_HOME}

# Copy Strimzi Agents and other Kafka libraries
RUN --mount=type=bind,from=strimzi-source-extractor,source=/tmp/strimzi-extracted/kafka-libs,target=/tmp/strimzi-kafka-libs-source \
    /etc/kafka/docker/copy-jars.sh /tmp/strimzi-kafka-libs-source ${KAFKA_HOME}/libs && \
    chown -R appuser:0 ${KAFKA_HOME}/libs

# Copy Cruise Control libraries
RUN --mount=type=bind,from=strimzi-source-extractor,source=/tmp/strimzi-extracted/cruise-control,target=/tmp/cruise-control-source \
    bash -c '/etc/kafka/docker/copy-jars.sh /tmp/cruise-control-source/libs ${CRUISE_CONTROL_HOME}/libs ${KAFKA_HOME}/libs && \
    find /tmp/cruise-control-source -maxdepth 1 -mindepth 1 -not -name libs -exec cp -r {} ${CRUISE_CONTROL_HOME}/ \;' && \
    chown -R appuser:0 ${CRUISE_CONTROL_HOME} && \
    chmod -R +x ${CRUISE_CONTROL_HOME}

# Important to set this to the kafka home as strimzi scripts have relative path references
WORKDIR $KAFKA_HOME

# --- End of Strimzi Support ---

USER appuser

#####
# Adapted Entrypoint in order to support 
# backwared-compatible BLC installations that may have been referencing
# a Confluent-based Kafka Image. Note that we use ENTRYPOINT + CMD
# to allow Kubernetes/Strimzi to override the command via 'args' 
# while still utilizing 'tini' for signal handling.
#####
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/etc/confluent/docker/run"]
