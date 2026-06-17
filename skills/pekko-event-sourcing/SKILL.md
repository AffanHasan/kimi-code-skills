---
name: pekko-event-sourcing
description: Guidance for developing Apache Pekko event-sourced persistent actors using the typed persistence API.
type: prompt
whenToUse:
  - When writing, reviewing, or refactoring Apache Pekko EventSourcedBehavior actors in Java or Scala.
  - When designing command, event, and state models for persistent actors.
  - When choosing persistence effects, recovery, snapshots, serialization, tagging, or cluster-sharding integration.
---

# Apache Pekko Event Sourcing

Use this skill when building event-sourced actors with [Apache Pekko Persistence typed](https://pekko.apache.org/docs/pekko/current/typed/persistence.html).

## Official reference

Always verify details against the latest official documentation:

- **Docs home:** https://pekko.apache.org/docs/pekko/current/typed/persistence.html
- **Current Pekko version:** `1.6.0`
- **Current persistence artifact:** `org.apache.pekko:pekko-persistence-typed:1.6.0`
- **Scala versions:** `2.12.21`, `2.13.18`, `3.3.7`
- **JDK:** OpenJDK 8 / OpenJDK 11 / OpenJDK 17 / OpenJDK 21

## Project coordinates

Keep all `pekko-*` dependencies on the same Pekko version to avoid binary incompatibilities.

### Maven

```xml
<properties>
  <pekko.version>1.6.0</pekko.version>
  <scala.binary.version>2.13</scala.binary.version>
</properties>

<dependencies>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-persistence-typed_${scala.binary.version}</artifactId>
    <version>${pekko.version}</version>
  </dependency>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-persistence-testkit_${scala.binary.version}</artifactId>
    <version>${pekko.version}</version>
    <scope>test</scope>
  </dependency>
</dependencies>
```

### SBT

```scala
val PekkoVersion = "1.6.0"
libraryDependencies ++= Seq(
  "org.apache.pekko" %% "pekko-persistence-typed" % PekkoVersion,
  "org.apache.pekko" %% "pekko-persistence-testkit" % PekkoVersion % Test
)
```

### Gradle

```gradle
def versions = [
  PekkoVersion: "1.6.0",
  ScalaBinary: "2.13"
]
dependencies {
  implementation "org.apache.pekko:pekko-persistence-typed_${versions.ScalaBinary}:${versions.PekkoVersion}"
  testImplementation "org.apache.pekko:pekko-persistence-testkit_${versions.ScalaBinary}:${versions.PekkoVersion}"
}
```

## Imports and API packages

- Scala API: `org.apache.pekko.persistence.typed.scaladsl.{EventSourcedBehavior, Effect}`
- Java API: `org.apache.pekko.persistence.typed.javadsl.{EventSourcedBehavior, Effect}`
- Core types: `org.apache.pekko.persistence.typed.PersistenceId`
- Signals: `org.apache.pekko.persistence.typed.RecoveryCompleted`

## Core API

A minimal `EventSourcedBehavior` needs four things:

| Component | Purpose |
|-----------|---------|
| `persistenceId` | Stable unique identifier for the actor in the journal and snapshot store. |
| `emptyState` | Initial state before any events are applied. |
| `commandHandler` | Validates commands and decides what events to persist (the `Effect`). |
| `eventHandler` | Applies persisted events to the state to produce the next state. |

The `Behavior` is typed to the `Command` type because that is the only message type the persistent actor should receive.

### PersistenceId

Use `PersistenceId.ofUniqueId("abc")` for a standalone actor. With Cluster Sharding, build it from `entityTypeHint` and `entityId`:

Scala:
```scala
val persistenceId = PersistenceId("BlogPost", entityId)
```

Java:
```java
PersistenceId persistenceId = PersistenceId.of("BlogPost", entityId);
```

The default separator is `|`. The `entityTypeHint` makes the id unique across different entity types that might share the same `entityId`.

### Command handler

Validate the command against the current state, then return an `Effect`:

- `Effect.persist(event)` — persist one event atomically.
- `Effect.persist(event1, event2, ...)` — persist multiple events atomically.
- `Effect.none()` — no event to persist (read-only or rejected command).
- `Effect.unhandled()` — command not supported in current state.
- `Effect.stop()` — stop the actor.
- `Effect.stash()` — stash the command for later processing.
- `Effect.reply(replyTo, response)` — reply immediately without persisting.

Chain side effects after the primary effect:

- `.thenRun(state => ...)` — run a side effect after successful persist.
- `.thenReply(replyTo)(state => ...)` — reply after persist.
- `.thenStop()` — stop the actor after persist.
- `.thenUnstashAll()` — process stashed commands after persist.

Side effects execute at-most-once and only after successful persistence. They are **not** run during recovery.

### Event handler

The event handler must only update state. Never perform side effects here, because the same handler is used during recovery replay.

Scala:
```scala
val eventHandler: (State, Event) => State = {
  case (state, Added(data)) => state.addItem(data)
  case (_, Cleared)         => State.empty
}
```

Java:
```java
@Override
public EventHandler<State, Event> eventHandler() {
  return newEventHandlerBuilder()
      .forAnyState()
      .onEvent(Added.class, (state, event) -> state.addItem(event.data))
      .onEvent(Cleared.class, (state, event) -> new State())
      .build();
}
```

## State-based handlers (FSM-like)

Use `forStateType` to define different command/event handlers for different states:

Scala:
```scala
CommandHandler[Command, Event, State] { (state, command) =>
  state match {
    case _: BlankState => command match { ... }
    case draft: DraftState => command match { ... }
    case _: PublishedState => command match { ... }
  }
}
```

Java:
```java
CommandHandlerBuilder<Command, Event, State> builder = newCommandHandlerBuilder();
builder.forStateType(BlankState.class).onCommand(AddPost.class, this::onAddPost);
builder.forStateType(DraftState.class).onCommand(ChangeBody.class, this::onChangeBody);
return builder.build();
```

## Enforced replies

For request/response interactions, use `EventSourcedBehavior.withEnforcedReplies` (Scala) or extend `EventSourcedBehaviorWithEnforcedReplies` (Java). The compiler will then require every command handler to return a `ReplyEffect`, ensuring a reply is not forgotten.

Scala:
```scala
EventSourcedBehavior.withEnforcedReplies[Command, Event, State](
  persistenceId, emptyState, commandHandler, eventHandler)
```

Java:
```java
public class AccountEntity
    extends EventSourcedBehaviorWithEnforcedReplies<
        AccountEntity.Command, AccountEntity.Event, AccountEntity.Account> { ... }
```

## Accessing ActorContext

Wrap construction with `Behaviors.setup` when the behavior needs `ActorContext`:

Scala:
```scala
Behaviors.setup { context =>
  EventSourcedBehavior[Command, Event, State](
    persistenceId, emptyState,
    commandHandler = (state, cmd) => { ... },
    eventHandler = (state, evt) => { ... })
}
```

Java:
```java
public static Behavior<Command> create(PersistenceId persistenceId) {
  return Behaviors.setup(ctx -> new MyBehavior(persistenceId, ctx));
}
```

## Recovery

Event sourced actors automatically recover by replaying journaled events on start and restart. New messages are stashed until recovery completes.

Use `RecoveryCompleted` for side effects that must run after recovery:

Scala:
```scala
EventSourcedBehavior[Command, Event, State](...)
  .receiveSignal {
    case (state, RecoveryCompleted) =>
      // safe place for post-recovery side effects
  }
```

Java:
```java
@Override
public SignalHandler<State> signalHandler() {
  return newSignalHandlerBuilder()
      .onSignal(RecoveryCompleted.instance(), state -> { ... })
      .build();
}
```

To disable recovery entirely:

Scala:
```scala
EventSourcedBehavior[Command, Event, State](...).withRecovery(Recovery.disabled)
```

Java:
```java
@Override
public Recovery recovery() {
  return Recovery.disabled();
}
```

## Snapshots

Snapshots reduce recovery time. Define when a snapshot should be taken:

Scala:
```scala
EventSourcedBehavior[Command, Event, State](...)
  .snapshotWhen { (state, event, sequenceNr) =>
    sequenceNr % 100 == 0
  }
```

Java:
```java
@Override
public boolean shouldSnapshot(State state, Event event, long sequenceNr) {
  return sequenceNr % 100 == 0;
}
```

## Serialization

Commands, events, and snapshots must be serializable. Use Jackson/CBOR as the default recommendation and plan for schema evolution from the start. Events live forever; ensure old events can still be read after the application evolves.

## Tagging

Tag events without an `EventAdapter`:

Scala:
```scala
EventSourcedBehavior[Command, Event, State](...)
  .withTagger(_ => Set("tag1", "tag2"))
```

Java:
```java
@Override
public Set<String> tagsFor(Event event) {
  return Set.of("tag1", "tag2");
}
```

## Event adapters

Use `EventAdapter` when the journal should store a different representation than the actor's event type:

Scala:
```scala
class WrapperEventAdapter[T] extends EventAdapter[T, Wrapper[T]] {
  override def toJournal(e: T): Wrapper[T] = Wrapper(e)
  override def fromJournal(p: Wrapper[T], manifest: String): EventSeq[T] = EventSeq.single(p.event)
  override def manifest(event: T): String = ""
}
```

Java:
```java
public class WrapperEventAdapter extends EventAdapter<SimpleEvent, Wrapper<SimpleEvent>> {
  @Override public Wrapper<SimpleEvent> toJournal(SimpleEvent e) { return new Wrapper<>(e); }
  @Override public String manifest(SimpleEvent e) { return ""; }
  @Override public EventSeq<SimpleEvent> fromJournal(Wrapper<SimpleEvent> p, String m) {
    return EventSeq.single(p.getEvent());
  }
}
```

## Cluster Sharding integration

Pekko Persistence follows the single-writer principle: only one active actor instance per `persistenceId` should persist events at a time. Use Cluster Sharding to enforce this uniqueness across the cluster.

Construct the `PersistenceId` from the sharding `entityTypeHint` and `entityId`:

Scala:
```scala
EntityTypeKey[Command]("BlogPost")
```

Java:
```java
EntityTypeKey<Command> typeKey = EntityTypeKey.create(Command.class, "BlogPost");
```

## Journal failures

By default the actor stops on journal failures. Override with a backoff supervisor strategy because normal supervision cannot simply resume after a failed persist:

Scala:
```scala
EventSourcedBehavior[Command, Event, State](...)
  .onPersistFailure(
    SupervisorStrategy.restartWithBackoff(minBackoff = 10.seconds, maxBackoff = 60.seconds, randomFactor = 0.1))
```

Java:
```java
private MyBehavior(PersistenceId persistenceId) {
  super(
    persistenceId,
    SupervisorStrategy.restartWithBackoff(Duration.ofSeconds(10), Duration.ofSeconds(60), 0.1));
}
```

## Testing

Use `pekko-persistence-testkit` for deterministic tests:

- `PersistenceTestKit` — verify persisted events and snapshots.
- `EventSourcedBehaviorTestKit` — test command/event handling in isolation without a real journal.

## Best practices

1. **Commands validate; events cannot fail.** Validate in the command handler. The event handler should always succeed.
2. **No side effects in event handlers.** Side effects belong in `thenRun` or `RecoveryCompleted`.
3. **Prefer immutable state.** Use immutable classes or records for state, commands, and events.
4. **Version alignment.** Keep all `pekko-*` artifacts on the same Pekko version.
5. **Use Cluster Sharding.** For distributed entities, combine `EventSourcedBehavior` with Cluster Sharding to guarantee a single active writer per `persistenceId`.
6. **Plan serialization and schema evolution.** Use Jackson/CBOR and ensure old events remain readable.
7. **Use enforced replies.** For request/response flows, use `withEnforcedReplies` to avoid forgetting replies.
8. **Snapshot strategically.** Use snapshots to limit recovery time for actors with long event logs.
9. **Keep effects focused.** Each command returns one primary effect; chain side effects with `thenRun`/`thenReply`.
10. **Tag events explicitly.** Use `withTagger`/`tagsFor` when projections or read models need tagged event streams.

## References

- [Apache Pekko Persistence typed documentation](https://pekko.apache.org/docs/pekko/current/typed/persistence.html)
- [Apache Pekko Cluster Sharding](https://pekko.apache.org/docs/pekko/current/typed/cluster-sharding.html)
- [Apache Pekko Serialization](https://pekko.apache.org/docs/pekko/current/serialization.html)
