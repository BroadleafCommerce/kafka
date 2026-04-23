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
FROM repository.broadleafcommerce.com:5001/broadleaf/kafka-kraft-base:wolfi-1 AS build-jsa

USER root

COPY docker/jvm/jsa_launch /etc/kafka/docker/jsa_launch

ARG DISTRO_NAME=kafka_2.13-3.9.2

COPY core/build/distributions/$DISTRO_NAME.tgz /

RUN set -eux ; \
    tar xfz /$DISTRO_NAME.tgz -C /opt/kafka --strip-components 1;

# Generate jsa files using dynamic CDS for kafka server start command and kafka storage format command
WORKDIR /
RUN /etc/kafka/docker/jsa_launch

# Stage 2: Main Kafka image build
FROM repository.broadleafcommerce.com:5001/broadleaf/kafka-kraft-base:wolfi-1

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
# a Confluent-based Kafka Image.
#####    
COPY --from=build-jsa /kafka.jsa /opt/kafka/kafka.jsa
COPY --from=build-jsa /storage.jsa /opt/kafka/storage.jsa
RUN mkdir -p /etc/kafka/docker
COPY --chown=appuser:0 docker/resources/common-scripts/ /etc/kafka/docker/
RUN chmod +x /etc/kafka/docker/*.sh
COPY --chown=appuser:0 docker/jvm/launch /etc/kafka/docker/launch

VOLUME ["/etc/kafka/secrets", "/var/lib/kafka/data", "/mnt/shared/config"]

RUN /etc/kafka/docker/hosts.sh

COPY --chown=appuser:0 run.sh /etc/confluent/docker/run
RUN chmod 755 /etc/confluent/docker/run

# Important to set this to the kafka home
WORKDIR /opt/kafka

# For compatibility with standard Kubernetes, we explicitly switch to a non-root UID. OpenShift
# will ignore these settings and run as an arbitrary UID in the root group.
USER appuser

CMD ["/etc/confluent/docker/run"]
