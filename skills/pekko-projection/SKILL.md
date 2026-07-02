---
name: pekko-projection
description: Guidance for developing Apache Pekko Projection applications in Java, including source providers, handlers, offset stores, testing, and cluster distribution.
type: prompt
whenToUse:
  - When writing, reviewing, or refactoring Apache Pekko Projection code in Java.
  - When choosing a source provider, offset store, handler style, or projection semantics.
  - When testing projections, managing offsets, or running projections in a Pekko Cluster.
---

# Apache Pekko Projection (Java)

Use this skill when building [Apache Pekko Projections](https://pekko.apache.org/docs/pekko-projection/current/index.html) applications in Java. A Projection consumes a stream of envelopes from a `SourceProvider`, processes them with a `Handler`, and stores an offset so it can resume after restart.

## Official reference

Always verify details against the latest official documentation:

- **Docs home:** https://pekko.apache.org/docs/pekko-projection/current/index.html
- **Current milestone (as of this skill):** Pekko Projection `2.0.0-M0`, Pekko `2.0.0-M3`
- **JDK:** Java 17 (formatter compatibility); runtime target depends on the Pekko version in use
- **Scala binary versions:** `2.13`, `3`

## Project coordinates

Keep all `pekko-*` dependencies on the same Pekko version. Projection artifacts are published for Scala binary versions and used from Java like any other cross-built artifact.

### Maven

```xml
<properties>
  <pekko.version>2.0.0-M3</pekko.version>
  <pekko.projection.version>2.0.0-M0</pekko.projection.version>
  <scala.binary.version>2.13</scala.binary.version>
</properties>

<dependencies>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-projection-core_${scala.binary.version}</artifactId>
    <version>${pekko.projection.version}</version>
  </dependency>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-projection-eventsourced_${scala.binary.version}</artifactId>
    <version>${pekko.projection.version}</version>
  </dependency>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-projection-jdbc_${scala.binary.version}</artifactId>
    <version>${pekko.projection.version}</version>
  </dependency>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-projection-testkit_${scala.binary.version}</artifactId>
    <version>${pekko.projection.version}</version>
    <scope>test</scope>
  </dependency>
</dependencies>
```

### SBT

```scala
val PekkoVersion = "2.0.0-M3"
val PekkoProjectionVersion = "2.0.0-M0"

libraryDependencies ++= Seq(
  "org.apache.pekko" %% "pekko-projection-core" % PekkoProjectionVersion,
  "org.apache.pekko" %% "pekko-projection-eventsourced" % PekkoProjectionVersion,
  "org.apache.pekko" %% "pekko-projection-jdbc" % PekkoProjectionVersion,
  "org.apache.pekko" %% "pekko-projection-testkit" % PekkoProjectionVersion % Test
)
```

### Gradle

```gradle
def versions = [
  PekkoVersion: "2.0.0-M3",
  PekkoProjectionVersion: "2.0.0-M0",
  ScalaBinary: "2.13"
]

dependencies {
  implementation "org.apache.pekko:pekko-projection-core_${versions.ScalaBinary}:${versions.PekkoProjectionVersion}"
  implementation "org.apache.pekko:pekko-projection-eventsourced_${versions.ScalaBinary}:${versions.PekkoProjectionVersion}"
  implementation "org.apache.pekko:pekko-projection-jdbc_${versions.ScalaBinary}:${versions.PekkoProjectionVersion}"
  testImplementation "org.apache.pekko:pekko-projection-testkit_${versions.ScalaBinary}:${versions.PekkoProjectionVersion}"
}
```

### Available modules

| Module | Artifact | Purpose |
|--------|----------|---------|
| Core | `pekko-projection-core` | `Projection`, `ProjectionId`, `Handler`, `SourceProvider` |
| Event Sourced | `pekko-projection-eventsourced` | `EventSourcedProvider` for `eventsByTag` / `eventsBySlices` |
| Durable State | `pekko-projection-durable-state` | `DurableStateSourceProvider` for `changesByTag` / `changesBySlices` |
| JDBC | `pekko-projection-jdbc` | Offset store and session in JDBC |
| R2DBC | `pekko-projection-r2dbc` | Offset store and session in R2DBC |
| Cassandra | `pekko-projection-cassandra` | Offset store in Cassandra |
| Slick | `pekko-projection-slick` | Offset store via Slick (community-driven) |
| Kafka | `pekko-projection-kafka` | `KafkaSourceProvider` with managed offset commits |
| gRPC | `pekko-projection-grpc` | Event producer/consumer over gRPC |
| TestKit | `pekko-projection-testkit` | `ProjectionTestKit`, `TestProjection`, `TestSourceProvider` |

## Imports and API packages

Core Java API:

- `org.apache.pekko.projection.Projection`
- `org.apache.pekko.projection.ProjectionId`
- `org.apache.pekko.projection.ProjectionBehavior`
- `org.apache.pekko.projection.javadsl.Handler`
- `org.apache.pekko.projection.javadsl.SourceProvider`
- `org.apache.pekko.projection.javadsl.ProjectionManagement`

Source providers:

- `org.apache.pekko.projection.eventsourced.javadsl.EventSourcedProvider`
- `org.apache.pekko.projection.eventsourced.EventEnvelope`
- `org.apache.pekko.projection.state.javadsl.DurableStateSourceProvider`
- `org.apache.pekko.projection.kafka.javadsl.KafkaSourceProvider`

Offset stores (choose one):

- JDBC: `org.apache.pekko.projection.jdbc.javadsl.JdbcProjection`, `org.apache.pekko.projection.jdbc.javadsl.JdbcHandler`, `org.apache.pekko.projection.jdbc.JdbcSession`
- R2DBC: `org.apache.pekko.projection.r2dbc.javadsl.R2dbcProjection`, `org.apache.pekko.projection.r2dbc.javadsl.R2dbcHandler`
- Cassandra: `org.apache.pekko.projection.cassandra.javadsl.CassandraProjection`
- Slick: `org.apache.pekko.projection.slick.javadsl.SlickProjection`

TestKit:

- `org.apache.pekko.projection.testkit.javadsl.ProjectionTestKit`
- `org.apache.pekko.projection.testkit.javadsl.TestProjection`
- `org.apache.pekko.projection.testkit.javadsl.TestSourceProvider`

## Core API

A projection is assembled from three pieces:

| Component | Purpose |
|-----------|---------|
| `SourceProvider<Offset, Envelope>` | Stream of envelopes with extractable offsets. |
| `Handler` / backend-specific handler | Processes each envelope (or grouped envelopes). |
| Offset store | Persists the latest processed offset for resume. |

Create a `ProjectionId` from a name and a key. The key typically corresponds to the tag or slice range the projection instance consumes:

```java
ProjectionId projectionId = ProjectionId.of("shopping-carts", "carts-1");
```

### Source providers

Event sourced `eventsByTag` (Cassandra, JDBC, or any Pekko Persistence plugin):

```java
import org.apache.pekko.persistence.cassandra.query.javadsl.CassandraReadJournal;
import org.apache.pekko.persistence.query.Offset;
import org.apache.pekko.projection.eventsourced.EventEnvelope;
import org.apache.pekko.projection.eventsourced.javadsl.EventSourcedProvider;
import org.apache.pekko.projection.javadsl.SourceProvider;

SourceProvider<Offset, EventEnvelope<ShoppingCart.Event>> sourceProvider =
    EventSourcedProvider.eventsByTag(system, CassandraReadJournal.Identifier(), "carts-1");
```

Event sourced `eventsBySlices` (R2DBC):

```java
SourceProvider<Offset, org.apache.pekko.persistence.query.typed.EventEnvelope<ShoppingCart.Event>> sourceProvider =
    EventSourcedProvider.eventsBySlices(system, "akka.persistence.r2dbc.query", "ShoppingCart", 0, 1023);
```

Durable state `changesByTag`:

```java
import org.apache.pekko.persistence.jdbc.state.javadsl.JdbcDurableStateStore;
import org.apache.pekko.persistence.query.DurableStateChange;
import org.apache.pekko.projection.state.javadsl.DurableStateSourceProvider;

SourceProvider<Offset, DurableStateChange<AccountEntity.Account>> sourceProvider =
    DurableStateSourceProvider.changesByTag(system, JdbcDurableStateStore.Identifier(), "bank-accounts-1");
```

Kafka:

```java
import org.apache.pekko.projection.MergeableOffset;
import org.apache.pekko.projection.kafka.javadsl.KafkaSourceProvider;
import org.apache.kafka.clients.consumer.ConsumerRecord;

SourceProvider<MergeableOffset<Long>, ConsumerRecord<String, String>> sourceProvider =
    KafkaSourceProvider.create(system, consumerSettings, Set.of(topicName));
```

Custom source provider: extend `SourceProvider<Offset, Envelope>` and implement `source`, `extractOffset`, and `extractCreationTime`.

## Handlers

### Generic handler

Use for `atLeastOnceAsync`, `groupedWithinAsync`, or sending to external systems:

```java
import org.apache.pekko.Done;
import org.apache.pekko.projection.javadsl.Handler;
import java.util.concurrent.CompletionStage;

public class ItemPopularityProjectionHandler
    extends Handler<EventEnvelope<ShoppingCartEvents.Event>> {

  @Override
  public CompletionStage<Done> process(EventEnvelope<ShoppingCartEvents.Event> envelope)
      throws Exception {
    ShoppingCartEvents.Event event = envelope.event();
    // ... idempotent, async processing
    return CompletableFuture.completedFuture(Done.getInstance());
  }
}
```

### JDBC handler

Use when the projection result and offset must be written in the same transaction (exactly-once):

```java
import org.apache.pekko.projection.jdbc.javadsl.JdbcHandler;
import org.apache.pekko.projection.eventsourced.EventEnvelope;

public class ShoppingCartHandler
    extends JdbcHandler<EventEnvelope<ShoppingCart.Event>, HibernateJdbcSession> {

  @Override
  public void process(HibernateJdbcSession session, EventEnvelope<ShoppingCart.Event> envelope)
      throws Exception {
    ShoppingCart.Event event = envelope.event();
    if (event instanceof ShoppingCart.CheckedOut checkedOut) {
      orderRepository.save(session.entityManager, new Order(checkedOut.cartId(), checkedOut.eventTime()));
    }
  }
}
```

Implement `JdbcSession` (or `PlainJdbcSession`) to provide a connection and transaction boundary. Disable auto-commit when using exactly-once so the handler and offset storage share the transaction.

### Handler lifecycle

Override `start()` and `stop()` for initialization and cleanup. These are called on projection start/stop and on restart after failure.

### Handler semantics

| Projection factory | Offset storage | Handler requirement |
|--------------------|----------------|---------------------|
| `exactlyOnce` | Same transaction as handler | Handler need not be idempotent, but failures roll back both offset and effect. |
| `atLeastOnce` | After successful processing | Handler must be idempotent because envelopes may be reprocessed after restart. |
| `groupedWithin` | Same transaction as handler (batch) | Batch handler; useful for bulk updates. |
| `atLeastOnceAsync` | After `CompletionStage` completes | Async handler; must be idempotent. |

## Building a projection

### JDBC

```java
Projection<EventEnvelope<ShoppingCart.Event>> projection =
    JdbcProjection.exactlyOnce(
        ProjectionId.of("shopping-carts", "carts-1"),
        sourceProvider,
        sessionProvider::newInstance,
        ShoppingCartHandler::new,
        system);
```

```java
Projection<EventEnvelope<ShoppingCart.Event>> projection =
    JdbcProjection.atLeastOnce(
            ProjectionId.of("shopping-carts", "carts-1"),
            sourceProvider,
            sessionProvider::newInstance,
            ShoppingCartHandler::new,
            system)
        .withSaveOffset(100, Duration.ofMillis(500));
```

### R2DBC

R2DBC supports `eventsBySlices`, which scales better than `eventsByTag` because the number of slice ranges can change:

```java
R2dbcProjection.exactlyOnce(
    ProjectionId.of("shopping-carts", "0-1023"),
    sourceProvider,
    () -> new ShoppingCartHandler(repo),
    system);
```

### Cassandra

```java
CassandraProjection.atLeastOnce(
    ProjectionId.of("shopping-carts", "carts-1"),
    sourceProvider,
    () -> new ShoppingCartHandler(session),
    system);
```

## Running projections

### Local actor

Spawn `ProjectionBehavior` directly for testing or single-node use:

```java
import org.apache.pekko.projection.ProjectionBehavior;

system.systemActorOf(ProjectionBehavior.create(projection), projection.projectionId().id());
```

Stop gracefully with `ProjectionBehavior.stop()`.

### Distributed with Sharded Daemon Process

For clustered deployments, distribute one projection instance per tag or slice range using `ShardedDaemonProcess`:

```java
ShardedDaemonProcess.get(system).init(
    ProjectionBehavior.Command.class,
    "ItemPopularityProjection",
    tags.size(),
    i -> ProjectionBehavior.create(projectionForTag(tags.get(i))),
    ShardedDaemonProcessSettings.create(system),
    Option.empty());
```

Use `ProjectionBehavior.stop()` as the stop message. Choose the number of tags/slice ranges to be larger than the expected cluster size.

### Cluster singleton

Use Pekko Cluster Singleton when only one or a few instances are needed, keeping in mind they all run on the same node.

## Tagging and slices

For `eventsByTag`, tag events in the `EventSourcedBehavior`:

```java
public class ShoppingCartTags {
  public static String SINGLE = "shopping-cart";
  public static String[] TAGS = {"carts-0", "carts-1", "carts-2"};
}
```

Select the tag from the entity id hash code modulo the number of tags. This partitions the journal so each projection instance processes one tag.

For `eventsBySlices` (R2DBC), events are sliced by persistence id. Use slice ranges instead of tags; slice ranges can be rebalanced when scaling out.

## Error handling

### Handler recovery strategy

Set per projection with `.withRecoveryStrategy(...)`:

- `fail` — fail the projection immediately (default).
- `skip` — skip the failing envelope.
- `retryAndFail(retries, delay)` — retry then fail.
- `retryAndSkip(retries, delay)` — retry then skip.

Default values come from `pekko.projection.recovery-strategy` in `reference.conf`.

### Projection restart

Projections automatically restart from the latest saved offset on failure. Configure backoff with `.withRestartBackoff(...)` or via `pekko.projection.restart-backoff`:

```conf
pekko.projection.restart-backoff {
  min-backoff = 3s
  max-backoff = 30s
  random-factor = 0.2
  max-restarts = -1
}
```

## Management

`ProjectionManagement` provides runtime operations:

- `getOffset(projectionId)` — read the latest stored offset.
- `clearOffset(projectionId)` — restart from the beginning.
- `updateOffset(projectionId, offset)` — skip a stuck offset.
- `pause(projectionId)` / `resume(projectionId)` / `isPaused(projectionId)` — pause and resume processing.

## Testing

Use `pekko-projection-testkit` with JUnit 5:

```java
import org.apache.pekko.actor.testkit.typed.javadsl.ActorTestKit;
import org.apache.pekko.projection.testkit.javadsl.ProjectionTestKit;

ActorTestKit testKit = ActorTestKit.create();
ProjectionTestKit projectionTestKit = ProjectionTestKit.create(testKit.system());
```

Run with an assertion function:

```java
projectionTestKit.run(
    projection,
    () -> cartCheckoutRepository.findById("abc-def").toCompletableFuture().get(1, TimeUnit.SECONDS));
```

Run with a `TestSink` probe to drive demand:

```java
projectionTestKit.runWithTestSink(
    projection,
    sinkProbe -> {
      sinkProbe.request(1);
      sinkProbe.expectNext(Done.getInstance());
    });
```

Test a handler in isolation with `TestProjection` and `TestSourceProvider`:

```java
TestSourceProvider<Integer, Pair<Integer, String>> sourceProvider =
    TestSourceProvider.create(source, Pair::first);

Projection<Pair<Integer, String>> projection =
    TestProjection.create(ProjectionId.of("test", "00"), sourceProvider, () -> handler);

projectionTestKit.run(projection, () -> { /* assertions */ });
```

## Configuration

Core defaults are in `core/src/main/resources/reference.conf`:

```conf
pekko.projection {
  restart-backoff {
    min-backoff = 3s
    max-backoff = 30s
    random-factor = 0.2
    max-restarts = -1
  }
  recovery-strategy {
    strategy = fail
    retries = 5
    retry-delay = 1 s
  }
  at-least-once {
    save-offset-after-envelopes = 100
    save-offset-after-duration = 500 ms
  }
  grouped {
    group-after-envelopes = 20
    group-after-duration = 500 ms
  }
}
```

JDBC also requires:

```conf
pekko.projection.jdbc.dialect = "postgres-dialect" // or mysql-dialect, mssql-dialect, oracle-dialect, h2-dialect
pekko.projection.jdbc.blocking-jdbc-dispatcher.thread-pool-executor.fixed-pool-size = 8
```

## Working in the Pekko Projection repository

When modifying the Pekko Projection codebase itself:

- Base work on `origin/main` unless requested otherwise.
- Keep PRs scoped to one change.
- Every non-doc PR must add or update a directional test.
- Run the smallest focused test first: `sbt "module-name / Test / testOnly fully.qualified.SpecName"`.
- Compile examples: `sbt "examples / compile"`.
- Format Java with JDK 17:
  ```shell
  export JAVA_HOME=$(/usr/libexec/java_home -v 17)
  export PATH="$JAVA_HOME/bin:$PATH"
  sbt javafmtAll
  ```
- For new files, create the file without a header, then run `sbt headerCreateAll`; sbt adds the correct Apache license header.
- Verify headers: `sbt +headerCheckAll`.
- Check style: `sbt checkCodeStyle`.
- Run PR validation: `sbt validatePullRequest`.
- Run MiMa for public API or serialization changes: `sbt +mimaReportBinaryIssues`.
- Build docs for doc changes: `sbt docs/paradox`.
- Preserve at-least-once or exactly-once semantics for handler changes.
- Offset storage changes must consider backward compatibility with existing offset tables.
- Projection handlers used with at-least-once must be idempotent.

## Best practices

1. **Keep Pekko versions aligned.** All `pekko-*` and `pekko-projection-*` artifacts should share compatible versions.
2. **Choose the right semantics.** Use exactly-once when the offset and effect must be atomic; use at-least-once for higher throughput with idempotent handlers.
3. **Make at-least-once handlers idempotent.** Envelopes can be reprocessed after restart.
4. **Do not share handler instances.** Each `Projection` instance must use its own handler to avoid concurrent invocation.
5. **Use connection pools.** For JDBC, configure a dedicated pool and matching blocking dispatcher size.
6. **Prefer `eventsBySlices` with R2DBC.** It scales better than a fixed number of tags.
7. **Tag count > expected cluster nodes.** For `eventsByTag`, choose a factor of ten more tags than planned nodes.
8. **Handle lifecycle.** Implement `start()`/`stop()` for resources that must be initialized or released.
9. **Test with TestKit.** Use `TestProjection` and `TestSourceProvider` for fast, deterministic handler tests.
10. **Monitor status.** Implement `StatusObserver` and attach it with `withStatusObserver` for operational visibility.

## References

- [Apache Pekko Projection documentation](https://pekko.apache.org/docs/pekko-projection/current/index.html)
- [Apache Pekko Projection Java API (Javadoc)](https://pekko.apache.org/japi/pekko-projection/current/)
- [Apache Pekko documentation](https://pekko.apache.org/docs/pekko/current/typed/index.html)
- [Apache Pekko Persistence](https://pekko.apache.org/docs/pekko/current/typed/persistence.html)
- [Apache Pekko Cluster Sharding](https://pekko.apache.org/docs/pekko/current/typed/cluster-sharding.html)
- [Apache Pekko Connectors Kafka](https://pekko.apache.org/docs/pekko-connectors-kafka/current/)
- Source examples in the repository:
  - `examples/src/test/java/jdocs/jdbc/JdbcProjectionDocExample.java`
  - `examples/src/test/java/jdocs/eventsourced/EventSourcedDocExample.java`
  - `examples/src/test/java/jdocs/eventsourced/EventSourcedBySlicesDocExample.java`
  - `examples/src/test/java/jdocs/state/DurableStateStoreDocExample.java`
  - `examples/src/test/java/jdocs/kafka/KafkaDocExample.java`
  - `examples/src/test/java/jdocs/testkit/TestKitDocExample.java`
  - `examples/src/test/java/jdocs/guide/ItemPopularityProjectionHandler.java`
  - `r2dbc/src/test/java/jdocs/home/projection/R2dbcProjectionDocExample.java`
  - `integration-examples/src/test/java/jdocs/cassandra/CassandraProjectionDocExample.java`
