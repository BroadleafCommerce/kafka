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

FROM eclipse-temurin:21.0.9_10-jre-alpine-3.23 AS build-jsa

USER root

COPY docker/jvm/jsa_launch /etc/kafka/docker/jsa_launch

ARG DISTRO_NAME=kafka_2.13-3.9.1

COPY core/build/distributions/$DISTRO_NAME.tgz /

RUN set -eux ; \
    # 1. Add Alpine Edge repositories
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories; \
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories; \
    # 2. Update and upgrade apk-tools
    apk update ; \
    apk add --upgrade apk-tools; \
    # 3. Force upgrade to Edge versions
    apk upgrade --available ; \
    # 4. Install build dependencies
    apk add --no-cache wget gcompat gpg gpg-agent procps bash; \
    mkdir opt/kafka; \
    tar xfz $DISTRO_NAME.tgz -C /opt/kafka --strip-components 1;

# Generate jsa files using dynamic CDS for kafka server start command and kafka storage format command
RUN /etc/kafka/docker/jsa_launch


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
    # 1. Add Alpine Edge repositories
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories; \
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories; \
    # 2. Update and upgrade apk-tools
    apk update ; \
    apk add --upgrade apk-tools; \
    # 3. Force upgrade all OS packages to Edge versions (patches CVEs)
    apk upgrade --available ; \
    # 4. Install runtime dependencies
    apk add --no-cache wget gcompat gpg gpg-agent procps bash su-exec; \
    # 5. Continue with Kafka installation and configuration
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
    # 6. Cleanup (remove build-only tools)
    apk del wget gpg gpg-agent; \
    apk cache clean;

COPY --from=build-jsa kafka.jsa /opt/kafka/kafka.jsa
COPY --from=build-jsa storage.jsa /opt/kafka/storage.jsa
COPY --chown=appuser:0 docker/resources/common-scripts /etc/kafka/docker
COPY --chown=appuser:0 docker/jvm/launch /etc/kafka/docker/launch

VOLUME ["/etc/kafka/secrets", "/var/lib/kafka/data", "/mnt/shared/config"]

RUN /etc/kafka/docker/hosts.sh

RUN mkdir /etc/confluent
RUN mkdir /etc/confluent/docker
COPY --chown=appuser:0 run.sh /etc/confluent/docker/run
RUN chmod 755 /etc/confluent/docker/run

# For compatibility with standard Kubernetes, we explicitly switch to a non-root UID. OpenShift
# will ignore these settings and run as an arbitrary UID in the root group.
USER appuser

CMD ["/etc/confluent/docker/run"]