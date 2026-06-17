---
name: pekko-connector-kafka
description: Guidance for developing Apache Pekko Connectors Kafka applications using the latest official Apache Pekko standards.
type: prompt
whenToUse:
  - When writing, reviewing, or refactoring Apache Pekko Kafka Connector consumer/producer code in Java or Scala.
  - When choosing between Consumer/Producer factory methods, settings, commit strategies, or shutdown patterns.
  - When configuring pekko.kafka.* HOCON settings for Kafka connectivity.
---

# Apache Pekko Connectors Kafka

Use this skill when building reactive Kafka integration pipelines with [Apache Pekko Connectors Kafka](https://pekko.apache.org/docs/pekko-connectors-kafka/current/).

## Official reference

Always verify details against the latest official documentation:

- **Docs home:** https://pekko.apache.org/docs/pekko-connectors-kafka/current/
- **Current connector version:** `1.1.0`
- **Apache Pekko version:** `1.1.1`
- **Kafka client version:** `3.9.0`
- **Scala versions:** `2.12.20`, `2.13.15`, `3.3.4`
- **JDK:** OpenJDK 8 / OpenJDK 11

## Project coordinates

Artifact: `org.apache.pekko:pekko-connectors-kafka_{scala.binary.version}:1.1.0`

Keep all `pekko-*` dependencies on the same Pekko version to avoid binary incompatibilities.

## Dependencies

### Maven

```xml
<properties>
  <pekko.version>1.1.1</pekko.version>
  <scala.binary.version>2.13</scala.binary.version>
</properties>

<dependencies>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-connectors-kafka_${scala.binary.version}</artifactId>
    <version>1.1.0</version>
  </dependency>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-stream_${scala.binary.version}</artifactId>
    <version>${pekko.version}</version>
  </dependency>
</dependencies>
```

### SBT

```scala
val PekkoVersion = "1.1.1"
libraryDependencies ++= Seq(
  "org.apache.pekko" %% "pekko-connectors-kafka" % "1.1.0",
  "org.apache.pekko" %% "pekko-stream" % PekkoVersion
)
```

### Gradle

```gradle
def versions = [
  PekkoVersion: "1.1.1",
  ScalaBinary: "2.13"
]
dependencies {
  implementation "org.apache.pekko:pekko-connectors-kafka_${versions.ScalaBinary}:1.1.0"
  implementation "org.apache.pekko:pekko-stream_${versions.ScalaBinary}:${versions.PekkoVersion}"
}
```

## Imports and API packages

- Scala API: `org.apache.pekko.kafka.scaladsl.{Consumer, Producer, Committer, Transactional}`
- Java API: `org.apache.pekko.kafka.javadsl.{Consumer, Producer, Committer, Transactional}`
- Settings: `org.apache.pekko.kafka.{ConsumerSettings, ProducerSettings, CommitterSettings}`
- Messages: `org.apache.pekko.kafka.{ConsumerMessage, ProducerMessage}`
- Subscription: `org.apache.pekko.kafka.Subscription` / `Subscriptions`

Both typed and classic `ActorSystem` are supported because both implement `ClassicActorSystemProvider`.

## Consumer patterns

### Choosing a source

| Use case | Factory method | Element type |
|----------|----------------|--------------|
| Read only / external offset storage | `Consumer.plainSource` | `ConsumerRecord` |
| Read with explicit offset commits | `Consumer.committableSource` | `CommittableMessage` |
| Read with metadata in commits | `Consumer.commitWithMetadataSource` | `CommittableMessage` |
| At-most-once (commit before process) | `Consumer.atMostOnceSource` | `ConsumerRecord` |
| Per-partition stream handling | `Consumer.plainPartitionedSource` / `Consumer.committablePartitionedSource` | `(TopicPartition, Source[...])` |
| Shared `KafkaConsumerActor` | `Consumer.plainExternalSource` / `Consumer.committableExternalSource` | `ConsumerRecord` / `CommittableMessage` |
| Transactions | `Transactional.source` | `TransactionalMessage` |

### Consumer settings

Create from config with inheritance:

```conf
our-kafka-consumer: ${pekko.kafka.consumer} {
  kafka-clients {
    bootstrap.servers = "kafka-host:9092"
    group.id = "group1"
    enable.auto.commit = false
  }
}
```

```scala
val config = system.settings.config.getConfig("our-kafka-consumer")
val consumerSettings =
  ConsumerSettings(config, new StringDeserializer, new StringDeserializer)
    .withProperty(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest")
```

Default consumer reference config lives under `pekko.kafka.consumer`.

### Committing offsets

Use `Committer.sink` or `Committer.flow` for batched explicit commits:

```scala
val committerSettings = CommitterSettings(system)

val control =
  Consumer
    .committableSource(consumerSettings, Subscriptions.topics(topic))
    .mapAsync(1) { msg =>
      business(msg.record.key, msg.record.value)
        .map(_ => msg.committableOffset)
    }
    .toMat(Committer.sink(committerSettings))(DrainingControl.apply)
    .run()
```

Avoid committing per message (`withMaxBatch(1)`) in throughput-sensitive paths; batch commits instead.

### Controlled shutdown

Use `Consumer.DrainingControl` and `drainAndShutdown()` when committing to Kafka:

```scala
val drainingControl =
  Consumer
    .committableSource(consumerSettings.withStopTimeout(Duration.Zero), Subscriptions.topics(topic))
    .map(_.committableOffset)
    .toMat(Committer.sink(committerSettings))(DrainingControl.apply)
    .run()

val streamComplete = drainingControl.drainAndShutdown()
```

## Producer patterns

### Choosing a sink/flow

| Use case | Factory | Input | Notes |
|----------|---------|-------|-------|
| Simple publish | `Producer.plainSink` | `ProducerRecord` | Shared producer allowed |
| Continue stream after publish | `Producer.flexiFlow` | `Envelope` | Emits `Result` / `MultiResult` / `PassThroughResult` |
| Read-transform-write with commit | `Producer.committableSink` | `Envelope` with `Committable` pass-through | Commits consumed offsets |
| Exactly-once | `Transactional.sink` / `Transactional.flow` | `Envelope` | Managed producer, no sharing |

### Producer settings

```scala
val config = system.settings.config.getConfig("pekko.kafka.producer")
val producerSettings =
  ProducerSettings(config, new StringSerializer, new StringSerializer)
    .withBootstrapServers("localhost:9092")
```

### Producer envelopes

```scala
// single message
ProducerMessage.single(
  new ProducerRecord(topic, key, value),
  passThrough)

// multiple messages
ProducerMessage.multi(
  Seq(new ProducerRecord(topic, key, value), new ProducerRecord(anotherTopic, key, value)),
  passThrough)

// pass-through only (no produce)
ProducerMessage.passThrough(passThrough)
```

### Connecting consumer to producer

```scala
val control =
  Consumer
    .committableSource(consumerSettings, Subscriptions.topics(sourceTopic))
    .map { msg =>
      ProducerMessage.single(
        new ProducerRecord(targetTopic, msg.record.key, msg.record.value),
        msg.committableOffset
      )
    }
    .toMat(Producer.committableSink(producerSettings, committerSettings))(DrainingControl.apply)
    .run()
```

## Key HOCON configuration paths

- `pekko.kafka.consumer` — `ConsumerSettings` defaults
- `pekko.kafka.producer` — `ProducerSettings` defaults
- `pekko.kafka.committer` — `CommitterSettings` defaults

Important defaults:

- `pekko.kafka.consumer.kafka-clients.enable.auto.commit = false`
- `pekko.kafka.consumer.stop-timeout = 30s`
- `pekko.kafka.producer.parallelism = 10000`
- `pekko.kafka.committer.max-batch = 1000`
- `pekko.kafka.committer.max-interval = 10s`

## Best practices

1. **Version alignment:** keep `pekko-stream`, `pekko-connectors-kafka`, and other `pekko-*` artifacts on compatible versions.
2. **Auto-commit:** leave `enable.auto.commit = false` and use explicit `Committer` for at-least-once semantics.
3. **Batch commits:** tune `CommitterSettings.max-batch` and `max-interval` for throughput, accepting more re-processing on failure.
4. **Clean shutdown:** use `DrainingControl.drainAndShutdown()` when committing offsets; set `stop-timeout = 0` in that case.
5. **External offset storage:** use `plainSource` with `Subscriptions.assignmentWithOffset` or `plainPartitionedManualOffsetSource`.
6. **Shared producers:** reuse a single `KafkaProducer` across stages for better performance; do not share producers with transactional flows.
7. **Error handling:** decide per stream whether failures terminate the stream, restart via Pekko Streams supervision, or are handled with `Recover`/`RestartSource`.
8. **Testing:** prefer deterministic unit tests for stream graphs; use embedded Kafka or Testcontainers for integration tests.

## References

- [Apache Pekko Connectors Kafka documentation](https://pekko.apache.org/docs/pekko-connectors-kafka/current/)
- [Consumer docs](https://pekko.apache.org/docs/pekko-connectors-kafka/current/consumer.html)
- [Producer docs](https://pekko.apache.org/docs/pekko-connectors-kafka/current/producer.html)
