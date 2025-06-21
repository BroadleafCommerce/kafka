# Kafka Environment Variable to Properties Converter

This directory contains scripts for working with Kafka in Docker environments.

## kafka-env-to-properties.sh

This script takes environment variables starting with `KAFKA_` and converts them to properties format, then updates a specified file. If a property already exists in the file, it will be overwritten with the new value. If it doesn't exist, it will be added to the file.

### Usage

```bash
./kafka-env-to-properties.sh <output_file>
```

### Example

```bash
./kafka-env-to-properties.sh /opt/kafka/config/server.properties
```

### Description

The script:

1. Takes an output file as a command-line argument
2. Checks if the output file exists and is writable
3. Processes all environment variables that start with `KAFKA_`
4. Excludes certain variables that are handled separately (like `KAFKA_HEAP_OPTS`, `KAFKA_JMX_OPTS`, etc.)
5. Converts the variable names by:
   - Removing the `KAFKA_` prefix
   - Converting to lowercase
   - Replacing underscores with dots
6. Extracts the values of the environment variables
7. Updates the specified output file:
   - If a property already exists in the file (and is not commented out), it overwrites it with the new value
   - If a property doesn't exist in the file, it adds it to the end of the file
   - If a property exists in the file but is commented out, it skips it entirely (doesn't uncomment or add it)

### Example Conversion

Environment variable:
```
KAFKA_BROKER_ID=1
```

Converted property:
```
broker.id=1
```

### Excluded Variables

The following environment variables are excluded from conversion:

- `KAFKA_VERSION`
- `KAFKA_HEAP_OPTS`
- `KAFKA_LOG4J_OPTS`
- `KAFKA_OPTS`
- `KAFKA_JMX_OPTS`
- `KAFKA_JVM_PERFORMANCE_OPTS`
- `KAFKA_GC_LOG_OPTS`
- `KAFKA_LOG4J_ROOT_LOGLEVEL`
- `KAFKA_LOG4J_LOGGERS`
- `KAFKA_TOOLS_LOG4J_LOGLEVEL`
- `KAFKA_JMX_HOSTNAME`

These variables are typically used for JVM configuration or other purposes and should not be included in the Kafka properties file.
