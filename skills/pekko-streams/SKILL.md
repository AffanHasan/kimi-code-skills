---
name: pekko-streams
description: Reference for writing and reviewing Apache Pekko Streams code in Java, including core operators, materialization, graphs, error handling, IO, and testing.
type: prompt
whenToUse:
  - When generating, refactoring, or reviewing Apache Pekko Streams Java code.
  - When choosing operators, materialization strategies, graph shapes, or error-handling patterns.
  - When explaining back-pressure, context propagation, KillSwitch, hubs, StreamRefs, or stream testing.
---

# Apache Pekko Streams (Java)

Use this skill as a concise, Java-focused reference for the Apache Pekko Streams API. It is based on the official Pekko Streams documentation (`https://pekko.apache.org/docs/pekko/current/stream/`) and the Pekko source code. Prefer the Java DSL (`org.apache.pekko.stream.javadsl.*`) when writing examples.

## Official reference

- **Docs home:** https://pekko.apache.org/docs/pekko/current/stream/
- **Operators index:** https://pekko.apache.org/docs/pekko/current/stream/operators/index.html
- **Current Pekko version:** `1.6.0`
- **Scala versions:** `2.12`, `2.13`, `3.3`
- **JDK:** OpenJDK 8 / 11 / 17 / 21

## Project coordinates

Artifact: `org.apache.pekko:pekko-stream_{scala.binary.version}:1.6.0`

Testkit: `org.apache.pekko:pekko-stream-testkit_{scala.binary.version}:1.6.0` (test scope)

Pekko BOM for version management:

```xml
<properties>
  <scala.binary.version>2.13</scala.binary.version>
</properties>

<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>org.apache.pekko</groupId>
      <artifactId>pekko-bom_${scala.binary.version}</artifactId>
      <version>1.6.0</version>
      <type>pom</type>
      <scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>

<dependencies>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-stream_${scala.binary.version}</artifactId>
  </dependency>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-stream-testkit_${scala.binary.version}</artifactId>
    <scope>test</scope>
  </dependency>
</dependencies>
```

---

## 1. Imports and setup

```java
import org.apache.pekko.actor.ActorSystem;
import org.apache.pekko.Done;
import org.apache.pekko.NotUsed;
import org.apache.pekko.stream.*;
import org.apache.pekko.stream.javadsl.*;
import org.apache.pekko.util.ByteString;

import java.time.Duration;
import java.util.concurrent.CompletionStage;
```

Streams run inside an `ActorSystem`. The system provides a global `Materializer`, so pass `system` to `run()` / `runWith()`.

```java
final ActorSystem system = ActorSystem.create("QuickStart");
```

---

## 2. Core vocabulary

| Concept | Meaning |
|---------|---------|
| **Element** | One unit of data flowing through the stream. |
| **Source** | Has one output; produces elements. |
| **Sink** | Has one input; consumes elements. |
| **Flow** | Has one input and one output; transforms elements. |
| **RunnableGraph** | A graph with all ports connected; can be `run()`. |
| **Materialized value (Mat)** | Value produced when a graph is materialized, e.g., `CompletionStage`, `ActorRef`, `Cancellable`. |
| **Back-pressure** | Downstream demand controls upstream production automatically. |
| **Operator** | Any graph building block: `map`, `filter`, `Merge`, `Broadcast`, custom `GraphStage`. |

Every stream type has two type parameters: element type and materialized value type.

```java
Source<Integer, NotUsed> source;                       // emits Integer
Sink<Integer, CompletionStage<Integer>> sink;          // consumes Integer, mat is a future result
Flow<Integer, String, NotUsed> flow;                   // Int in, String out
```

---

## 3. Defining and running linear streams

Build streams left-to-right. Nothing runs until a terminal operation (`run*`, `runWith`).

```java
Source<Integer, NotUsed> source = Source.from(Arrays.asList(1, 2, 3, 4, 5));
Sink<Integer, CompletionStage<Integer>> sink = Sink.fold(0, Integer::sum);

RunnableGraph<CompletionStage<Integer>> runnable = source.toMat(sink, Keep.right());
CompletionStage<Integer> sum = runnable.run(system);
```

Shorthand:

```java
CompletionStage<Integer> sum = source.runWith(sink, system);
```

### Common Source factories

```java
Source.single("only one");
Source.from(list);
Source.fromIterator(() -> iterator);
Source.fromJavaStream(() -> javaStream);
Source.range(1, 100);
Source.repeat("x");
Source.empty();
Source.<String>completionStage(completionStage);   // fromCompletionStage is deprecated
Source.<String>lazySource(() -> heavySource);
Source.tick(Duration.ofSeconds(1), Duration.ofSeconds(1), "tick");
Source.<Integer>queue(100);              // mat is BoundedSourceQueue
Source.<Integer>maybe();                 // mat is CompletableFuture<Optional<Integer>>
```

### Common Sink factories

```java
Sink.foreach(System.out::println);
Sink.head();
Sink.seq();
Sink.ignore();
Sink.fold(0, Integer::sum);
Sink.actorRef(receiver, onCompleteMessage);
Sink.actorRefWithBackpressure(receiver, onInit, ack, onComplete, onFailure);
Sink.asPublisher(AsPublisher.WITHOUT_FANOUT);
Sink.fromSubscriber(subscriber);
```

### Important rules

- **No `null` elements** in streams. Use `Optional` or sentinel values.
- Operators are **immutable**. Reassign the returned value when chaining.
- `run*` methods are terminal; other methods build a blueprint.

---

## 4. Materialized values

`via` / `to` keep the left materialized value by default. Use `viaMat` / `toMat` with a combiner to change that.

```java
import org.apache.pekko.japi.Pair;

Source<Integer, CompletableFuture<Optional<Integer>>> maybe = Source.maybe();
Flow<Integer, Integer, Cancellable> throttler =
    Flow.of(Integer.class).throttle(1, Duration.ofSeconds(1));
Sink<Integer, CompletionStage<Integer>> head = Sink.head();

// Keep both
RunnableGraph<Pair<CompletableFuture<Optional<Integer>>, CompletionStage<Integer>>> both =
    maybe.via(throttler).toMat(head, Keep.both());

// Keep right only
RunnableGraph<CompletionStage<Integer>> right =
    maybe.via(throttler).toMat(head, Keep.right());
```

Combiners in `Keep`: `left()`, `right()`, `both()`, `none()`.

`runWith` returns the materialized value of the stage it attaches:

```java
CompletionStage<Integer> r1 = source.via(flow).runWith(sink, system);     // sink's mat
CompletableFuture<Optional<Integer>> r2 = flow.to(sink).runWith(source, system); // source's mat
Pair<..., CompletionStage<Integer>> r3 = flow.runWith(source, sink, system);      // both
```

Pre-materialize a materialized-value-powered source:

```java
Source<String, ActorRef> actorRefSource = Source.actorRef(
    elem -> Optional.empty(),
    elem -> Optional.empty(),
    100,
    OverflowStrategy.dropHead());

Pair<ActorRef, Source<String, NotUsed>> pair = actorRefSource.preMaterialize(system);
ActorRef ref = pair.first();
Source<String, NotUsed> usable = pair.second();
```

---

## 5. Operators

Quick reference of commonly used operators. For the exhaustive list see the official operators index.

### Simple transforms

```java
source.map(String::toUpperCase)
      .filter(s -> s.length() > 2)
      .filterNot(String::isEmpty)
      .mapConcat(s -> Arrays.asList(s.split("")))   // 1 -> many
      .take(10)
      .drop(2)
      .dropWhile(String::isEmpty)
      .grouped(5)
      .fold(0, (acc, list) -> acc + list.size())
      .reduce(Integer::sum)
      .collect(PFBuilder.<String, Integer>create().match(...).build());
```

### Stateful / side-effecting

```java
source.statefulMap(() -> 0, (acc, elem) -> Pair.create(acc + 1, acc + elem), acc -> Optional.empty())
source.mapWithResource(() -> resource, (r, elem) -> transform(r, elem), Resource::close)
source.log("label")                 // use Attributes.createLogLevels(...) for levels
source.watchTermination((mat, done) -> done) // done is CompletionStage<Done>
```

### Time and rate

```java
source.delay(Duration.ofMillis(100));
source.throttle(10, Duration.ofSeconds(1));
source.groupedWithin(100, Duration.ofSeconds(1));
source.initialDelay(Duration.ofSeconds(2));
source.takeWithin(Duration.ofSeconds(5));
```

### Buffers and back-pressure-aware

```java
source.buffer(100, OverflowStrategy.dropHead());  // explicit user buffer
flow.batch(100, first -> first, (agg, elem) -> combine(agg, elem));
flow.conflate((last, next) -> next);              // collapse while downstream backpressures
flow.extrapolate(last -> Stream.iterate(last, x -> x).iterator());
flow.expand(last -> Stream.iterate(0, i -> i + 1)
                           .map(i -> Pair.create(last, i)).iterator());
```

### Async / futures

```java
// preserves order
source.mapAsync(4, author -> lookupEmail(author.handle()));

// completes as they finish, unordered
source.mapAsyncUnordered(4, author -> lookupEmail(author.handle()));
```

### Fan-in / fan-out

```java
Source<Integer, NotUsed> s1 = Source.single(1);
Source<Integer, NotUsed> s2 = Source.single(2);
Source<Integer, NotUsed> merged =
    Source.combine(s1, s2, new ArrayList<>(), n -> Merge.create(n));

Sink<Integer, NotUsed> sink1 = Sink.foreach(System.out::println);
Sink<Integer, NotUsed> sink2 = Sink.ignore();
Sink<Integer, NotUsed> combined =
    Sink.combine(sink1, sink2, new ArrayList<>(), n -> Broadcast.create(n));

flow.alsoTo(Sink.foreach(x -> audit(x)))  // tap side output without affecting main flow
     .to(Sink.ignore());
```

### Context propagation

```java
SourceWithContext<String, Long, NotUsed> withCtx =
    Source.from(listOfPairs).asSourceWithContext(pair -> pair.offset());

withCtx.map(line -> parse(line))
       .filter(event -> event.valid())
       .mapConcat(event -> event.items())
       .to(Sink.foreach(x -> {}));
```

Allowed operations: `map`, `filter`, `collect`, `grouped`, `mapConcat`. Escape hatch: `unsafeDataVia` (use with care).

---

## 6. Graph DSL

Use `GraphDSL.create` when you need fan-in/fan-out, cycles, or reusable components.

```java
RunnableGraph.fromGraph(
    GraphDSL.create(
        builder -> {
          final UniformFanOutShape<Integer, Integer> bcast = builder.add(Broadcast.create(2));
          final UniformFanInShape<Integer, Integer> merge = builder.add(Merge.create(2));
          final FlowShape<Integer, Integer> doubleIt =
              builder.add(Flow.of(Integer.class).map(x -> x * 2));

          builder.from(builder.add(Source.single(1))).viaFanOut(bcast);
          builder.from(bcast)
                 .via(builder.add(Flow.of(Integer.class).map(x -> x + 10)))
                 .toFanIn(merge);
          builder.from(bcast).via(doubleIt).toFanIn(merge);
          builder.from(merge).to(builder.add(Sink.foreach(System.out::println)));
          return ClosedShape.getInstance();
        }))
    .run(system);
```

### Common shapes

| Shape | Use |
|-------|-----|
| `SourceShape<Out>` | one output |
| `SinkShape<In>` | one input |
| `FlowShape<In,Out>` | one input, one output |
| `ClosedShape` | fully connected, runnable |
| `BidiShape<In1,Out1,In2,Out2>` | two inputs, two outputs |
| `UniformFanInShape<T,T>` / `UniformFanOutShape<T,T>` | N inputs/outputs of same type |
| `FanInShape2<A,B,C>` / `FanOutShape2<A,B,C>` | typed multi-port shapes |

Partial graphs can be turned back into `Source`, `Sink`, `Flow`, or `BidiFlow`:

```java
Graph<FlowShape<Integer, Integer>, NotUsed> partial = GraphDSL.create(/* ... */);
Flow<Integer, Integer, NotUsed> reusable = Flow.fromGraph(partial);
```

Materialized values of imported graphs can be accessed by passing them into `GraphDSL.create(...)` and combining with a function.

---

## 7. Modularity, nesting and attributes

Wrap a sub-graph to give it a name or attributes:

```java
final Source<Integer, NotUsed> nestedSource =
    Source.single(0)
          .map(i -> i + 1)
          .named("nestedSource");

final Flow<Integer, Integer, NotUsed> nestedFlow =
    Flow.of(Integer.class)
        .filter(i -> i != 0)
        .withAttributes(Attributes.inputBuffer(4, 4))
        .named("nestedFlow");
```

Attributes are inherited by nested modules unless overridden closer to the operator.

Useful attributes:

```java
Attributes.name("my-stage")
Attributes.inputBuffer(initial, max)
ActorAttributes.dispatcher("custom-dispatcher")
ActorAttributes.withSupervisionStrategy(decider)
```

---

## 8. Async boundaries and parallelism

By default operators are fused (run in one actor). Insert `.async()` to run a section in its own actor.

```java
source.map(this::step1)
      .async()                 // boundary
      .map(this::step2)
      .async()                 // boundary
      .runWith(Sink.ignore(), system);
```

Combine pipelining and parallelism:

```java
Flow<Job, Result, NotUsed> workerPool(Flow<Job, Result, NotUsed> worker, int workers) {
  return Flow.fromGraph(GraphDSL.create(builder -> {
    final UniformFanOutShape<Job, Job> balance = builder.add(Balance.create(workers));
    final UniformFanInShape<Result, Result> merge = builder.add(Merge.create(workers));
    for (int i = 0; i < workers; i++) {
      builder.from(balance.out(i)).via(builder.add(worker.async())).toInlet(merge.in(i));
    }
    return FlowShape.of(balance.in(), merge.out());
  }));
}
```

`Balance`/`Merge` give parallel unordered processing. Use `MergeSequence` or `Zip` to preserve ordering.

---

## 9. Error handling

By default an exception in an operator fails the whole stream.

### log / recover / recoverWithRetries

```java
source.map(x -> 100 / x)
      .log("errors")
      .recover(PFBuilder.<Throwable, Integer>create()
          .match(ArithmeticException.class, ex -> -1)
          .build())
      .runWith(Sink.seq(), system);

Source<String, NotUsed> planB = Source.from(Arrays.asList("fallback"));
source.map(x -> risky(x))
      .recoverWithRetries(3,
          PFBuilder.<Throwable, Source<String, NotUsed>>create()
              .match(RuntimeException.class, ex -> planB)
              .build())
      .runWith(Sink.seq(), system);
```

### Restart with backoff

```java
RestartSettings settings = RestartSettings.create(
    Duration.ofSeconds(3),
    Duration.ofSeconds(30),
    0.2)
    .withMaxRestarts(20, Duration.ofMinutes(5));

Source<ServerSentEvent, NotUsed> events =
    RestartSource.withBackoff(settings, () -> createEventSource());
```

Also available: `RestartFlow.withBackoff`, `RestartSink.withBackoff`, `RestartSource.onFailuresWithBackoff`, `RetryFlow.withBackoff`.

### Supervision strategies

Attach a decider to drop or restart on exceptions (only operators documented to honor supervision will apply it):

```java
Function<Throwable, Supervision.Directive> decider = ex ->
    ex instanceof ArithmeticException ? Supervision.resume() : Supervision.stop();

source.map(x -> 100 / x)
      .withAttributes(ActorAttributes.withSupervisionStrategy(decider))
      .runWith(Sink.fold(0, Integer::sum), system);
```

Directives: `Supervision.stop()`, `Supervision.resume()`, `Supervision.restart()`.

---

## 10. Dynamic stream handling

### KillSwitch

```java
UniqueKillSwitch killSwitch = source
    .viaMat(KillSwitches.single(), Keep.right())
    .toMat(Sink.last(), Keep.left())
    .run(system);

killSwitch.shutdown();   // complete the stream normally
killSwitch.abort(error); // fail the stream
```

`SharedKillSwitch` can control many streams.

### Hubs

```java
// dynamic fan-in
Sink<String, NotUsed> sink =
    MergeHub.of(String.class, 16).to(Sink.foreach(System.out::println)).run(system);
Source.single("a").runWith(sink, system);
Source.single("b").runWith(sink, system);

// dynamic fan-out
Source<String, NotUsed> publisher =
    producer.toMat(BroadcastHub.of(String.class, 256), Keep.right()).run(system);
publisher.runForeach(x -> consumer1(x), system);
publisher.runForeach(x -> consumer2(x), system);

// partition by key
Source<String, NotUsed> partitioned =
    producer.toMat(
        PartitionHub.of(String.class, (size, elem) -> Math.abs(elem.hashCode() % size), 2, 256),
        Keep.right()).run(system);
```

---

## 11. Custom operators with GraphStage

Use `GraphStage` when built-in operators cannot express what you need. Keep the `GraphStage` immutable; all mutable state belongs inside `GraphStageLogic`.

```java
public class NumbersSource extends GraphStage<SourceShape<Integer>> {
  public final Outlet<Integer> out = Outlet.create("NumbersSource.out");
  private final SourceShape<Integer> shape = SourceShape.of(out);

  @Override public SourceShape<Integer> shape() { return shape; }

  @Override
  public GraphStageLogic createLogic(Attributes inheritedAttributes) {
    return new GraphStageLogic(shape) {
      private int counter = 1;
      {
        setHandler(out, new AbstractOutHandler() {
          @Override public void onPull() { push(out, counter++); }
        });
      }
    };
  }
}

Source<Integer, NotUsed> mySource = Source.fromGraph(new NumbersSource());
```

A custom `Flow` stage:

```java
public class Map<A, B> extends GraphStage<FlowShape<A, B>> {
  private final Function<A, B> f;
  public final Inlet<A> in = Inlet.create("Map.in");
  public final Outlet<B> out = Outlet.create("Map.out");

  public Map(Function<A, B> f) { this.f = f; }
  @Override public FlowShape<A, B> shape() { return FlowShape.of(in, out); }

  @Override
  public GraphStageLogic createLogic(Attributes inheritedAttributes) {
    return new GraphStageLogic(shape) {{
      setHandler(in, new AbstractInHandler() {
        @Override public void onPush() { push(out, f.apply(grab(in))); }
      });
      setHandler(out, new AbstractOutHandler() {
        @Override public void onPull() { pull(in); }
      });
    }};
  }
}
```

Key port lifecycle callbacks:

- `InHandler.onPush()` – new element available; call `grab(in)` then `pull(in)` or `push(out, ...)`.
- `InHandler.onUpstreamFinish()` / `onUpstreamFailure(...)`.
- `OutHandler.onPull()` – downstream requested an element; call `push(out, elem)` if available.
- `OutHandler.onDownstreamFinish()` – downstream cancelled.

Convenience methods: `completeStage()`, `failStage(ex)`, `emit(out, elem)`, `emitMultiple(out, iterable)`.

---

## 12. Interop

### Futures (`CompletionStage`)

```java
source.mapAsync(4, author -> lookupEmail(author.handle()));
source.mapAsyncUnordered(4, author -> sendEmail(author));
```

For blocking calls, run on a dedicated dispatcher:

```java
Executor blockingEc = system.dispatchers().lookup("blocking-dispatcher");
source.mapAsync(4, phone ->
    CompletableFuture.supplyAsync(() -> smsServer.send(phone), blockingEc));
```

### Actors (classic)

```java
// ask pattern
source.ask(5, actorRef, String.class, Timeout.apply(5, TimeUnit.SECONDS));

// sink with back-pressure
Sink<String, NotUsed> sink = Sink.<String>actorRefWithBackpressure(
    receiver,
    new StreamInitialized(), Ack.INSTANCE, new StreamCompleted(), ex -> new StreamFailure(ex));

// source fed from actorRef
Source<Integer, ActorRef> src = Source.actorRef(
    elem -> elem == Done.done() ? Optional.of(CompletionStrategy.immediately()) : Optional.empty(),
    elem -> Optional.empty(), 100, OverflowStrategy.dropHead());
```

### Actors (typed)

Requires `pekko-stream-typed`.

```java
import org.apache.pekko.stream.typed.javadsl.ActorFlow;

Flow<String, Reply, NotUsed> askFlow =
    ActorFlow.ask(actorRef, Duration.ofSeconds(1), Asking::new);
```

### Reactive Streams

```java
// wrap external Publisher/Subscriber
Source.fromPublisher(publisher);
Sink.fromSubscriber(subscriber);

// expose Pekko Source/Sink as Publisher/Subscriber
Publisher<Author> pub =
    source.via(flow).runWith(Sink.asPublisher(AsPublisher.WITH_FANOUT), system);
Subscriber<Tweet> sub =
    flow.to(Sink.fromSubscriber(storage)).runWith(Source.asSubscriber(), system);

// Java 9+ Flow interfaces
import org.apache.pekko.stream.javadsl.JavaFlowSupport;
JavaFlowSupport.Source.<String>fromPublisher(flowPublisher);
```

---

## 13. Streaming IO

### TCP

```java
Tcp.get(system).bind("127.0.0.1", 8888)
    .runForeach(conn -> {
      Flow<ByteString, ByteString, NotUsed> echo =
          Flow.of(ByteString.class)
              .via(Framing.delimiter(ByteString.fromString("\n"), 256, FramingTruncation.DISALLOW))
              .map(ByteString::utf8String)
              .map(s -> s + "!!!\n")
              .map(ByteString::fromString);
      conn.handleWith(echo, system);
    }, system);
```

Outgoing connection:

```java
Flow<ByteString, ByteString, CompletionStage<OutgoingConnection>> connection =
    Tcp.get(system).outgoingConnection("127.0.0.1", 8888);
```

### File IO

```java
CompletionStage<IOResult> read = FileIO.fromPath(Paths.get("input.csv"))
    .to(Sink.foreach(chunk -> System.out.println(chunk.utf8String())))
    .run(system);

CompletionStage<IOResult> written = sourceOfByteStrings
    .runWith(FileIO.toPath(Paths.get("output.bin")), system);
```

Use `ActorAttributes.dispatcher("...")` to configure the blocking-io dispatcher for a specific operator.

---

## 14. StreamRefs (distributed streams)

StreamRefs let you run a stream across Pekko Cluster nodes. They are single-shot.

```java
// Offer a Source to a remote node
SourceRef<String> ref = logs.runWith(StreamRefs.sourceRef(), mat);
getSender().tell(new LogsOffer(id, ref), getSelf());

// Remote side
offer.sourceRef.getSource().runWith(Sink.foreach(System.out::println), mat);

// Offer a Sink to receive from a remote node
SinkRef<String> sinkRef = StreamRefs.<String>sinkRef().to(logsSink).run(mat);
getSender().tell(new MeasurementsSinkReady(id, sinkRef), getSelf());

// Remote side
Source.repeat("hello").runWith(ready.sinkRef.getSink(), mat);
```

Subscription timeout can be set per ref via `StreamRefAttributes.subscriptionTimeout(duration)`.

---

## 15. Testing

Use `pekko-stream-testkit`.

```java
import org.apache.pekko.stream.testkit.javadsl.TestSource;
import org.apache.pekko.stream.testkit.javadsl.TestSink;

TestSubscriber.Probe<Integer> sub =
    sourceUnderTest.runWith(TestSink.create(system), system);
sub.request(2).expectNext(4, 8).expectComplete();

TestPublisher.Probe<Integer> pub =
    TestSource.<Integer>create(system).toMat(Sink.cancelled(), Keep.left()).run(system);
pub.expectCancellation();
```

Enable fuzzing mode in tests only:

```conf
pekko.stream.materializer.debug.fuzzing-mode = on
```

---

## 16. Substreams

```java
source.groupBy(3, elem -> elem % 3)
      .map(x -> x * 2)
      .mergeSubstreams()
      .runWith(Sink.seq(), system);

source.splitWhen(elem -> elem == 3)        // or splitAfter
      .map(x -> 1)
      .reduce((a, b) -> a + b)
      .mergeSubstreams()
      .runWith(Sink.foreach(System.out::println), system);

source.flatMapConcat(i -> Source.from(Arrays.asList(i, i, i))); // one active substream at a time
source.flatMapMerge(4, i -> Source.from(Arrays.asList(i, i, i))); // up to 4 concurrent
```

Substreams cannot contribute to the parent materialized value.

---

## 17. Cookbook patterns

| Recipe | Operator / pattern |
|--------|-------------------|
| Logging | `.log("label")` or `.map(x -> { log(x); return x; })` |
| Flatten lists | `.mapConcat(identity)` |
| Digest over bytes | custom `GraphStage` |
| Parse lines | `Framing.delimiter(ByteString.fromString("\n"), max, truncation)` |
| Decompress gzip | `Compression.gzipDecompress()` |
| Worker pool | `Balance` + `Merge` with `.async()` |
| Drop from slow broadcast | `buffer(size, OverflowStrategy.dropHead())` per branch |
| Hold last value | custom `GraphStage` with `setHandlers` |
| Global rate limit | `mapAsync` + `Patterns.ask` a limiter actor |
| Adhoc source | `Source.lazySource` + `backpressureTimeout` + `recoverWithRetries` |

---

## 18. Configuration

Key defaults from the Pekko Streams reference configuration:

```conf
pekko.stream.materializer {
  initial-input-buffer-size = 4
  max-input-buffer-size = 16
  dispatcher = "pekko.actor.default-dispatcher"
  blocking-io-dispatcher = "pekko.actor.default-blocking-io-dispatcher"
  debug.fuzzing-mode = off
}
```

Override per stream or section via attributes instead of globally when possible.

---

## 19. Common gotchas

- **Forgetting to keep a result.** `source.map(x -> 0);` has no effect because operators are immutable.
- **Wrong `Keep` combiner.** `source.to(sink)` keeps the source mat value; use `toMat(sink, Keep.right())` for the sink's future.
- **Null elements.** Streams reject `null`. Use `Optional`.
- **Cycles deadlock.** Cycles need a `MergePreferred` or explicit buffer to make progress; plain `Merge` + `Broadcast` loops can deadlock.
- **Async surprise.** `.async()` introduces internal buffers; if time/rate behavior looks odd, set `Attributes.inputBuffer(1, 1)` on the stage.
- **Supervision limited.** Only operators documented to support supervision honor a decider; others still fail the stream.
- **`Source.queue` vs `Source.actorRef`.** Prefer `Source.queue` for back-pressured actor integration; `Source.actorRef` cannot back-pressure.
- **Typed actor interop requires `pekko-stream-typed`.**

---

## 20. Documentation coverage

The sections above map to the official Pekko Streams documentation trail:

- [x] Introduction / Motivation
- [x] Streams Quickstart Guide
- [x] Design Principles
- [x] Basics and working with Flows
- [x] Working with Graphs
- [x] Modularity, Composition and Hierarchy
- [x] Buffers and working with rate
- [x] Context Propagation
- [x] Dynamic stream handling
- [x] Custom stream processing
- [x] Futures interop
- [x] Actors interop
- [x] Reactive Streams Interop
- [x] Error Handling in Streams
- [x] Working with streaming IO
- [x] StreamRefs
- [x] Pipelining and Parallelism
- [x] Testing streams
- [x] Substreams
- [x] Streams Cookbook
- [x] Configuration
- [x] Operators index

---

## 21. References

- [Apache Pekko Streams documentation](https://pekko.apache.org/docs/pekko/current/stream/)
- [Operators index](https://pekko.apache.org/docs/pekko/current/stream/operators/index.html)
- [Apache Pekko source repository](https://github.com/apache/pekko)
