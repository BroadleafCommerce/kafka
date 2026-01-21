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
# Adapted from the official Apache Dockerfile
FROM eclipse-temurin:21.0.9_10-jre-alpine-3.23 AS build-jsa

USER root

COPY docker/jvm/jsa_launch /etc/kafka/docker/jsa_launch

ARG DISTRO_NAME=kafka_2.13-3.9.1

COPY core/build/distributions/$DISTRO_NAME.tgz /

RUN set -eux ; \
    apk update ; \
    apk upgrade ; \
    apk add --no-cache wget gcompat gpg gpg-agent procps bash; \
    mkdir opt/kafka; \
    tar xfz $DISTRO_NAME.tgz -C /opt/kafka --strip-components 1;

# Generate jsa files using dynamic CDS for kafka server start command and kafka storage format command
RUN /etc/kafka/docker/jsa_launch

# Stage 2: Extract Strimzi components from the official Strimzi Kafka image
# IMPORTANT: When updating Kafka - review Strimzi and Kafka compatibility matrix 
# to ensure appropriate strimzi source and image versions: https://strimzi.io/downloads/
FROM quay.io/strimzi/kafka:0.47.0-kafka-3.9.1 AS strimzi-source-extractor

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
# Strimzi Step 1: Copy Strimzi Kafka scripts (e.g., kafka_run.sh) from base image
# Exclude non-strimzi scripts (i.e we only need ones defined here https://github.com/strimzi/strimzi-kafka-operator/tree/0.47.0/docker-images/kafka-based/kafka/scripts)
#####
RUN cp -r /opt/kafka/* /tmp/strimzi-extracted/scripts
RUN rm -rf /tmp/strimzi-extracted/scripts/LICENSE /tmp/strimzi-extracted/scripts/NOTICE /tmp/strimzi-extracted/scripts/bin /tmp/strimzi-extracted/scripts/config /tmp/strimzi-extracted/scripts/libs /tmp/strimzi-extracted/scripts/licenses /tmp/strimzi-extracted/scripts/plugins /tmp/strimzi-extracted/scripts/site-docs

#####
# Exclude Kafka Exporter
# Strimzi Step 2: Strimzi comes with Kafka Exporter Scripts from base image
# However due to more strict security policies, we are opting to exclude this go-based dependency
# RUN cp -r /opt/kafka-exporter/* /tmp/strimzi-extracted/kafka-exporter
#####

#####
# Add Prometheus JMX Exporter
# Strimzi Step 3: Copy Prometheus JMX Exporter contents from base image
#####
RUN cp -r /opt/prometheus-jmx-exporter/* /tmp/strimzi-extracted/prometheus-jmx-exporter

#####
# Add Strimzi agents, 3rd party libs, & Other Kafka Libs
# Strimzi Step 4: Copy Strimzi Agents and other libraries from Kafka's libs directory in the base image
#####
RUN cp -r /opt/kafka/libs/* /tmp/strimzi-extracted/kafka-libs

#####
# Add Cruise Control
# Strimzi Step 5: Copy Cruise Control libraries and scripts
#####
RUN cp -r /opt/cruise-control/* /tmp/strimzi-extracted/cruise-control

# Verify the files were copied
RUN ls -la /tmp/strimzi-extracted/scripts /tmp/strimzi-extracted/kafka-exporter /tmp/strimzi-extracted/prometheus-jmx-exporter /tmp/strimzi-extracted/kafka-libs /tmp/strimzi-extracted/cruise-control

# Stage 3: Main Kafka image build
# Adapted from the official Apache Dockerfile
FROM eclipse-temurin:21.0.9_10-jre-alpine-3.23

# exposed ports
EXPOSE 9092

USER root

LABEL org.label-schema.name="kafka" \
      org.label-schema.description="Apache Kafka" \
      org.label-schema.vcs-url="https://github.com/apache/kafka" \
      maintainer="Apache Kafka"

ARG DISTRO_NAME=kafka_2.13-3.9.1

COPY core/build/distributions/$DISTRO_NAME.tgz /

# NOTE - because we aim to be compatible with both OpenShift (runs as random UID) and standard
# Kubernetes, we cannot have any user-specific configuration in our Dockerfile.
# We assume appuser UID for standard Kubernetes, and an arbitrary UID + root group (0)
# for OpenShift. Thus, grant both of those ownership here.
RUN set -eux ; \
    apk update ; \
    apk upgrade ; \
    apk add --no-cache wget gcompat gpg gpg-agent procps bash su-exec tini grep curl; \
    mkdir opt/kafka; \
    tar xfz $DISTRO_NAME.tgz -C /opt/kafka --strip-components 1; \
    mkdir -p /var/lib/kafka/data /etc/kafka/secrets; \
    mkdir -p /etc/kafka/docker /usr/logs /mnt/shared/config; \
    adduser -h /home/appuser -D --shell /bin/bash appuser; \
    chown appuser:0 -R /usr/logs /opt/kafka /mnt/shared/config; \
    chown appuser:0 -R /var/lib/kafka /etc/kafka/secrets /etc/kafka; \
    chmod -R ug+w /etc/kafka /var/lib/kafka /etc/kafka/secrets /opt/kafka; \
    cp /opt/kafka/config/log4j.properties /etc/kafka/docker/log4j.properties; \
    cp /opt/kafka/config/tools-log4j.properties /etc/kafka/docker/tools-log4j.properties; \
    rm $DISTRO_NAME.tgz; \
    apk del wget gpg gpg-agent; \
    apk cache clean;

#####
# Needed to support an adapted entrypoint in support of
# backwared-compatible BLC installations that may have been referencing
# a Confluent-based Kafka Image, with added support for initialization 
# via the Strimzi Operator for K8 installations (https://strimzi.io/)
#####    
COPY --from=build-jsa kafka.jsa /opt/kafka/kafka.jsa
COPY --from=build-jsa storage.jsa /opt/kafka/storage.jsa
COPY --chown=appuser:0 docker/resources/common-scripts /etc/kafka/docker
RUN chmod +x /etc/kafka/docker/copy-jars.sh
COPY --chown=appuser:0 docker/jvm/launch /etc/kafka/docker/launch

VOLUME ["/etc/kafka/secrets", "/var/lib/kafka/data", "/mnt/shared/config"]

RUN /etc/kafka/docker/hosts.sh

RUN mkdir /etc/confluent
RUN mkdir /etc/confluent/docker
COPY --chown=appuser:0 run.sh /etc/confluent/docker/run
RUN chmod 755 /etc/confluent/docker/run

# --- Start of Strimzi Support ---

ENV KAFKA_HOME=/opt/kafka
ENV KAFKA_VERSION=3.9.1
ENV STRIMZI_VERSION=0.47.0
ENV KAFKA_EXPORTER_HOME=/opt/kafka-exporter
ENV JMX_EXPORTER_HOME=/opt/prometheus-jmx-exporter
ENV CRUISE_CONTROL_HOME=/opt/cruise-control

# Create a symlink to tini in /usr/bin as referenced by strimzi scripts
RUN ln -s /sbin/tini /usr/bin/tini

# Create necessary directories for Strimzi components
RUN mkdir -p ${KAFKA_HOME}/strimzi-scripts \
             ${KAFKA_HOME}/strimzi-kafka-libs \
             ${KAFKA_EXPORTER_HOME} \
             ${CRUISE_CONTROL_HOME} \
             ${JMX_EXPORTER_HOME}

# Copy Strimzi Kafka scripts
COPY --from=strimzi-source-extractor --chown=appuser:root /tmp/strimzi-extracted/scripts ${KAFKA_HOME}/strimzi-scripts
RUN chmod -R +x ${KAFKA_HOME}/strimzi-scripts
RUN mv ${KAFKA_HOME}/strimzi-scripts/* ${KAFKA_HOME}
RUN rm -rf ${KAFKA_HOME}/strimzi-scripts

# Do Nothing with Kafka Exporter Directory
# As mentioned above, due to stricter security policies we are opting to exclude the kafka-exporter binary
# COPY --from=strimzi-source-extractor --chown=appuser:root /tmp/strimzi-extracted/kafka-exporter ${KAFKA_EXPORTER_HOME}
# RUN chmod -R +x ${KAFKA_EXPORTER_HOME}/kafka_exporter

# Copy Prometheus JMX Exporter directory
COPY --from=strimzi-source-extractor --chown=appuser:root /tmp/strimzi-extracted/prometheus-jmx-exporter ${JMX_EXPORTER_HOME}

# Copy Strimzi Agents and other Kafka libraries
# Use a bind mount to access files from the previous stage without copying them permanently into a layer first
RUN --mount=type=bind,from=strimzi-source-extractor,source=/tmp/strimzi-extracted/kafka-libs,target=/tmp/strimzi-kafka-libs-source \
    /etc/kafka/docker/copy-jars.sh /tmp/strimzi-kafka-libs-source ${KAFKA_HOME}/libs && \
    chown -R appuser:root ${KAFKA_HOME}/libs

# Copy Cruise Control libraries
# Use a bind mount to access files from the previous stage
# We copy libs using the deduplication script, and other files directly
RUN --mount=type=bind,from=strimzi-source-extractor,source=/tmp/strimzi-extracted/cruise-control,target=/tmp/cruise-control-source \
    bash -c '/etc/kafka/docker/copy-jars.sh /tmp/cruise-control-source/libs ${CRUISE_CONTROL_HOME}/libs ${KAFKA_HOME}/libs && \
    find /tmp/cruise-control-source -maxdepth 1 -mindepth 1 -not -name libs -exec cp -r {} ${CRUISE_CONTROL_HOME}/ \;' && \
    chown -R appuser:root ${CRUISE_CONTROL_HOME} && \
    chmod -R +x ${CRUISE_CONTROL_HOME}

# Important to set this to the kafka home as strimzi scripts have relative path references
WORKDIR $KAFKA_HOME

# --- End of Strimzi Support ---

# For compatibility with standard Kubernetes, we explicitly switch to a non-root UID. OpenShift
# will ignore these settings and run as an arbitrary UID in the root group.
USER appuser

#####
# Adapted Entrypoint in order to support 
# backwared-compatible BLC installations that may have been referencing
# a Confluent-based Kafka Image. Note that this entrypoint is not used
# when running this image via the Strimzi Operator as Strimzi
# provides its own entrypoint. See https://github.com/strimzi/strimzi-kafka-operator
#####
CMD ["/etc/confluent/docker/run"]