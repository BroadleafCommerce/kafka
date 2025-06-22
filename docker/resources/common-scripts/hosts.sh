#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

HOSTS_FILE="/etc/hosts"
TEMP_HOSTS_FILE="/tmp/hosts.tmp" # Writable by root in /tmp

# Remove the IPv6 localhost entry (::1 localhost) and any other IPv6 entries for localhost
# Ensure 127.0.0.1 localhost is present
# We use 'grep -v' to filter out lines containing '::1 localhost'
# and then add the desired 127.0.0.1 localhost entry explicitly.

# First, filter out lines containing '::1 localhost' and any 'ip6-loopback' or similar
# This creates a new temporary hosts file without the IPv6 localhost entries.
grep -vE '::1\s+localhost|ip6-localhost|ip6-loopback' "${HOSTS_FILE}" > "${TEMP_HOSTS_FILE}"

# Ensure 127.0.0.1 localhost is present at the beginning of the file
# Check if 127.0.0.1 localhost already exists in the filtered file
if ! grep -q "127.0.0.1 localhost" "${TEMP_HOSTS_FILE}"; then
  # If not, add it to the top
  echo "127.0.0.1 localhost" | cat - "${TEMP_HOSTS_FILE}" > "${HOSTS_FILE}.new" && mv "${HOSTS_FILE}.new" "${TEMP_HOSTS_FILE}"
fi

# Overwrite the original /etc/hosts with the modified content
# This requires root privileges, which the entrypoint has.
cat "${TEMP_HOSTS_FILE}" > "${HOSTS_FILE}"
rm "${TEMP_HOSTS_FILE}"

if [[ -n "${KAFKA_ZOOKEEPER_CONNECT-}" ]] then
  cp /opt/kafka/config/server.properties /etc/kafka/docker/server.properties;
else
  cp /opt/kafka/config/kraft/server.properties /etc/kafka/docker/server.properties;
fi

exec su-exec appuser /etc/kafka/docker/run
