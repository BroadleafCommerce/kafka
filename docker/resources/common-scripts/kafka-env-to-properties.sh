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

# This script takes environment variables starting with KAFKA_ and converts them
# to properties format, then appends them to a specified file.
#
# Usage: kafka-env-to-properties.sh <output_file>
#
# Example: kafka-env-to-properties.sh /opt/kafka/config/server.properties

# Check if output file is provided
if [ -z "$1" ]; then
  echo "Error: Output file not specified"
  echo "Usage: kafka-env-to-properties.sh <output_file>"
  exit 1
fi

OUTPUT_FILE="$1"

# Check if output file exists and is writable
if [ ! -f "$OUTPUT_FILE" ]; then
  echo "Error: Output file does not exist: $OUTPUT_FILE"
  exit 1
fi

if [ ! -w "$OUTPUT_FILE" ]; then
  echo "Error: Output file is not writable: $OUTPUT_FILE"
  exit 1
fi

# Define variables to exclude (these are handled separately or shouldn't be in properties file)
EXCLUDE_VARS=(
  "KAFKA_VERSION"
  "KAFKA_HEAP_OPTS"
  "KAFKA_LOG4J_OPTS"
  "KAFKA_OPTS"
  "KAFKA_JMX_OPTS"
  "KAFKA_JVM_PERFORMANCE_OPTS"
  "KAFKA_GC_LOG_OPTS"
  "KAFKA_LOG4J_ROOT_LOGLEVEL"
  "KAFKA_LOG4J_LOGGERS"
  "KAFKA_TOOLS_LOG4J_LOGLEVEL"
  "KAFKA_JMX_HOSTNAME"
)

# Create temporary files
TEMP_FILE=$(mktemp)
ENV_FILE=$(mktemp)

# Add a header to the temporary file
echo "# Properties modified by kafka-env-to-properties.sh on $(date)" > "$TEMP_FILE"

# Process all environment variables and store them in a temporary file
for VAR in $(env)
do
  # Extract the variable name (without the value)
  VAR_NAME=$(echo "$VAR" | cut -d= -f1)

  # Check if variable starts with KAFKA_ and is not in the exclude list
  if [[ $VAR_NAME =~ ^KAFKA_ ]]; then
    # Check if the variable is in the exclude list
    EXCLUDED=false
    for EXCLUDE in "${EXCLUDE_VARS[@]}"; do
      if [[ $VAR_NAME == "$EXCLUDE" ]]; then
        EXCLUDED=true
        break
      fi
    done

    # Process only if not excluded
    if [[ $EXCLUDED == false ]]; then
      # Convert variable name: remove KAFKA_ prefix, convert to lowercase, replace _ with .
      KAFKA_PROP_KEY=$(echo "$VAR" | sed -r 's/KAFKA_(.*)=.*/\1/g' | tr '[:upper:]' '[:lower:]' | tr '_' '.' | sed -r 's/\.\.+/_/g')

      # Extract the value
      KAFKA_PROP_VALUE=$(echo "$VAR" | sed -r 's/.*=(.*)/\1/g')

      # Store in temporary file
      echo "$KAFKA_PROP_KEY=$KAFKA_PROP_VALUE" >> "$ENV_FILE"
    fi
  fi
done

# Process the original file line by line
MODIFIED=false
# Create a list of commented property keys to skip
COMMENTED_KEYS=()
# First pass: identify all commented property keys
while IFS= read -r LINE || [[ -n "$LINE" ]]; do
  if [[ "$LINE" =~ ^[[:space:]]*#[[:space:]]*([^=]+)[[:space:]]*= ]]; then
    COMMENTED_KEY="${BASH_REMATCH[1]}"
    COMMENTED_KEY="${COMMENTED_KEY// /}"  # Remove any spaces
    COMMENTED_KEYS+=("$COMMENTED_KEY")
  fi
done < "$OUTPUT_FILE"

# Second pass: process the file
while IFS= read -r LINE || [[ -n "$LINE" ]]; do
  # Handle empty lines
  if [[ -z "${LINE// }" ]]; then
    echo "$LINE" >> "$TEMP_FILE"
    continue
  fi

  # Skip commented property lines - we'll keep them as is but won't process them
  if [[ "$LINE" =~ ^[[:space:]]*#[[:space:]]*([^=]+)[[:space:]]*= ]]; then
    # Just keep the commented line as is
    echo "$LINE" >> "$TEMP_FILE"
    continue
  fi

  # Skip other comment lines
  if [[ "$LINE" =~ ^[[:space:]]*# ]]; then
    echo "$LINE" >> "$TEMP_FILE"
    continue
  fi

  # Extract property key from the line
  if [[ "$LINE" =~ ^[[:space:]]*([^=]+)[[:space:]]*= ]]; then
    PROP_KEY="${BASH_REMATCH[1]}"
    PROP_KEY="${PROP_KEY// /}"  # Remove any spaces

    # Check if this property is in our environment variables
    MATCH=$(grep -E "^$PROP_KEY=" "$ENV_FILE" || true)
    if [[ -n "$MATCH" ]]; then
      # Replace the line with our new value
      PROP_VALUE=$(echo "$MATCH" | cut -d= -f2-)
      echo "$PROP_KEY=$PROP_VALUE" >> "$TEMP_FILE"
      echo "Updated: $PROP_KEY=$PROP_VALUE"
      # Remove from the env file to mark as processed
      sed -i.bak "/^$PROP_KEY=/d" "$ENV_FILE"
      MODIFIED=true
    else
      # Keep the original line
      echo "$LINE" >> "$TEMP_FILE"
    fi
  else
    # Not a property line, keep as is
    echo "$LINE" >> "$TEMP_FILE"
  fi
done < "$OUTPUT_FILE"

# Add any remaining properties that weren't in the original file
while IFS= read -r LINE || [[ -n "$LINE" ]]; do
  if [[ -n "$LINE" ]]; then
    PROP_KEY=$(echo "$LINE" | cut -d= -f1)
    PROP_VALUE=$(echo "$LINE" | cut -d= -f2-)

    # Check if this property was commented in the original file
    SKIP=false
    for COMMENTED_KEY in "${COMMENTED_KEYS[@]}"; do
      if [[ "$PROP_KEY" == "$COMMENTED_KEY" ]]; then
        SKIP=true
        echo "Skipping commented property: $PROP_KEY"
        break
      fi
    done

    # Only add the property if it wasn't commented in the original file
    if [[ "$SKIP" == "false" ]]; then
      echo "$PROP_KEY=$PROP_VALUE" >> "$TEMP_FILE"
      echo "Added: $PROP_KEY=$PROP_VALUE"
      MODIFIED=true
    fi
  fi
done < "$ENV_FILE"

# Clean up the temporary env file
rm -f "$ENV_FILE" "$ENV_FILE.bak"

# Replace the original file with the temporary file
mv "$TEMP_FILE" "$OUTPUT_FILE"

if [[ "$MODIFIED" == "true" ]]; then
  echo "Environment variables have been written to $OUTPUT_FILE"
else
  echo "No changes were made to $OUTPUT_FILE"
fi
