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

FROM eclipse-temurin:21.0.8_9-jre-alpine-3.22 AS build-jsa

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


FROM eclipse-temurin:21.0.8_9-jre-alpine-3.22

# exposed ports
EXPOSE 9092

USER root

LABEL org.label-schema.name="kafka" \
      org.label-schema.description="Apache Kafka" \
      org.label-schema.vcs-url="https://github.com/apache/kafka" \
      maintainer="Apache Kafka"

ARG DISTRO_NAME=kafka_2.13-3.9.1

COPY core/build/distributions/$DISTRO_NAME.tgz /

RUN set -eux ; \
    apk update ; \
    apk upgrade ; \
    apk add --no-cache wget gcompat gpg gpg-agent procps bash su-exec; \
    mkdir opt/kafka; \
    tar xfz $DISTRO_NAME.tgz -C /opt/kafka --strip-components 1; \
    mkdir -p /var/lib/kafka/data /etc/kafka/secrets; \
    mkdir -p /etc/kafka/docker /usr/logs /mnt/shared/config; \
    adduser -h /home/appuser -D --shell /bin/bash appuser; \
    chown appuser:appuser -R /usr/logs /opt/kafka /mnt/shared/config; \
    chown appuser:root -R /var/lib/kafka /etc/kafka/secrets /etc/kafka; \
    chmod -R ug+w /etc/kafka /var/lib/kafka /etc/kafka/secrets; \
    cp /opt/kafka/config/log4j.properties /etc/kafka/docker/log4j.properties; \
    cp /opt/kafka/config/tools-log4j.properties /etc/kafka/docker/tools-log4j.properties; \
    rm $DISTRO_NAME.tgz; \
    apk del wget gpg gpg-agent; \
    apk cache clean;

COPY --from=build-jsa kafka.jsa /opt/kafka/kafka.jsa
COPY --from=build-jsa storage.jsa /opt/kafka/storage.jsa
COPY --chown=appuser:appuser docker/resources/common-scripts /etc/kafka/docker
COPY --chown=appuser:appuser docker/jvm/launch /etc/kafka/docker/launch

VOLUME ["/etc/kafka/secrets", "/var/lib/kafka/data", "/mnt/shared/config"]

RUN /etc/kafka/docker/hosts.sh

RUN mkdir /etc/confluent
RUN mkdir /etc/confluent/docker
COPY --chown=appuser:root run.sh /etc/confluent/docker/run
RUN chmod 755 /etc/confluent/docker/run

USER appuser

CMD ["/etc/confluent/docker/run"]