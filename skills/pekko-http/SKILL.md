---
name: pekko-http
description: Reference for writing and reviewing Apache Pekko HTTP code in Java, including server routing DSL, low-level server/client APIs, marshalling, WebSockets, and testing.
type: prompt
whenToUse:
  - When generating, refactoring, or reviewing Apache Pekko HTTP Java code.
  - When designing HTTP server routes, clients, or RESTful APIs with Pekko HTTP.
  - When choosing marshalling strategies, directives, connection pools, or test patterns.
---

# Apache Pekko HTTP (Java)

Use this skill as a concise, Java-focused reference for the Apache Pekko HTTP API. It is based on the official Pekko HTTP documentation (`https://pekko.apache.org/docs/pekko-http/current/`) and the Pekko HTTP source code. Prefer the Java DSL (`org.apache.pekko.http.javadsl.*`) when writing examples.

## Official reference

- **Docs home:** https://pekko.apache.org/docs/pekko-http/current/
- **Java docs:** https://pekko.apache.org/docs/pekko-http/current/java/http/
- **Current Pekko HTTP version:** `1.3.0`
- **Compatible Apache Pekko version:** `1.1.5`
- **Scala versions:** `2.12`, `2.13`, `3.3`
- **JDK:** OpenJDK 8 / 11 / 17 / 21

## Project coordinates

Pekko HTTP is released independently from Apache Pekko. You must add both `pekko-http` and `pekko-stream` explicitly.

Artifact: `org.apache.pekko:pekko-http_{scala.binary.version}:1.3.0`

Pekko HTTP BOM for version management:

```xml
<properties>
  <pekko.version>1.1.5</pekko.version>
  <scala.binary.version>2.13</scala.binary.version>
</properties>

<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>org.apache.pekko</groupId>
      <artifactId>pekko-http-bom_${scala.binary.version}</artifactId>
      <version>1.3.0</version>
      <type>pom</type>
      <scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>

<dependencies>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-actor-typed_${scala.binary.version}</artifactId>
    <version>${pekko.version}</version>
  </dependency>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-stream_${scala.binary.version}</artifactId>
    <version>${pekko.version}</version>
  </dependency>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-http_${scala.binary.version}</artifactId>
  </dependency>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-http-testkit_${scala.binary.version}</artifactId>
    <scope>test</scope>
  </dependency>
  <dependency>
    <groupId>org.apache.pekko</groupId>
    <artifactId>pekko-stream-testkit_${scala.binary.version}</artifactId>
    <version>${pekko.version}</version>
    <scope>test</scope>
  </dependency>
</dependencies>
```

Optional marshalling modules:

- `org.apache.pekko:pekko-http-jackson_{scala.binary.version}:1.3.0`
- `org.apache.pekko:pekko-http-spray-json_{scala.binary.version}:1.3.0`
- `org.apache.pekko:pekko-http-xml_{scala.binary.version}:1.3.0`

---

## 1. Imports and setup

```java
import org.apache.pekko.actor.typed.ActorSystem;
import org.apache.pekko.actor.typed.javadsl.Behaviors;
import org.apache.pekko.http.javadsl.Http;
import org.apache.pekko.http.javadsl.ServerBinding;
import org.apache.pekko.http.javadsl.model.*;
import org.apache.pekko.http.javadsl.server.*;
import org.apache.pekko.stream.javadsl.*;

import java.util.concurrent.CompletionStage;
import java.util.function.Function;
```

HTTP runs inside an `ActorSystem`. Always obtain `Http` via `Http.get(system)`.

```java
final ActorSystem<Void> system = ActorSystem.create(Behaviors.empty(), "http-system");
final Http http = Http.get(system);
```

---

## 2. Core vocabulary

| Concept | Meaning |
|---------|---------|
| **Route** | A function `RequestContext -> CompletionStage<RouteResult>`; the building block of the routing DSL. |
| **Directive** | A composable rule that filters/transforms requests (path, method, parameter, entity, etc.). |
| **Rejection** | Information about why a route could not handle a request; collected and turned into a response. |
| **ExceptionHandler** | Converts uncaught exceptions inside routes into `HttpResponse`s. |
| **Marshaller** | Converts a domain object into an HTTP entity. |
| **Unmarshaller** | Converts an HTTP entity into a domain object. |
| **HttpRequest / HttpResponse** | Immutable request/response messages. |
| **ServerBinding** | Handle to a bound server port; call `unbind()` to shut down. |

---

## 3. Server routing DSL

The routing DSL is the recommended way to build HTTP servers. Mix in or extend `AllDirectives` to access all directives.

```java
import org.apache.pekko.http.javadsl.server.AllDirectives;
import org.apache.pekko.http.javadsl.server.Route;

public class Routes extends AllDirectives {

  public Route createRoute() {
    return concat(
        path("hello", () -> get(() -> complete("Hello!"))),
        path("items" / "item", () -> get(() -> complete("List items")))
    );
  }
}
```

Start the server:

```java
final Routes app = new Routes();
final CompletionStage<ServerBinding> binding =
    http.newServerAt("localhost", 8080).bind(app.createRoute());

binding.thenAccept(b -> System.out.println("Server at " + b.localAddress()));
```

### Common directives

```java
// Path
path("users", () -> ...)
path("users" / LongNumber, id -> ...)
pathPrefix("api" / "v1", () -> ...)
pathEnd(() -> ...)
pathSingleSlash(() -> ...)

// Method
get(() -> ...)
post(() -> ...)
put(() -> ...)
delete(() -> ...)

// Parameters and headers
parameter("name", name -> ...)
parameter(StringUnmarshallers.INTEGER, "id", id -> ...)
headerValueByName("X-Request-Id", requestId -> ...)

// Entity
entity(Jackson.unmarshaller(Order.class), order -> ...)
entity(Unmarshaller.entityToMultipartFormData(), formData -> ...)

// Completion
complete("plain text")
complete(StatusCodes.OK, "created")
completeOK(item, Jackson.marshaller())
complete(StatusCodes.NOT_FOUND)

// Asynchronous completion
onSuccess(future, result -> complete(result))
onComplete(() -> future, tryResult -> ...)
```

### Route composition

```java
return concat(route1, route2, route3);
```

Routes are tried in order. A route can either complete, reject, or fail. Rejections are collected unless handled.

---

## 4. JSON with Jackson

Add `pekko-http-jackson` and use `Jackson.marshaller()` / `Jackson.unmarshaller(Class)`.

```java
import org.apache.pekko.http.javadsl.marshallers.jackson.Jackson;

public class ItemRoutes extends AllDirectives {

  private Route createRoute() {
    return concat(
        get(() ->
            pathPrefix("item", () ->
                path(longSegment(), id -> {
                  CompletionStage<Optional<Item>> future = fetchItem(id);
                  return onSuccess(future, maybeItem ->
                      maybeItem.map(item -> completeOK(item, Jackson.marshaller()))
                               .orElseGet(() -> complete(StatusCodes.NOT_FOUND, "Not found")));
                }))),
        post(() ->
            path("create-order", () ->
                entity(Jackson.unmarshaller(Order.class), order -> {
                  CompletionStage<Done> saved = saveOrder(order);
                  return onSuccess(saved, done -> complete("order created"));
                })))
    );
  }
}
```

Use standard Jackson annotations (`@JsonCreator`, `@JsonProperty`) on domain classes.

---

## 5. Streaming request/response bodies

Bodies are streams of `ByteString`. Streaming keeps memory constant even for large payloads.

```java
import org.apache.pekko.NotUsed;
import org.apache.pekko.util.ByteString;
import java.util.Random;

public class StreamRoutes extends AllDirectives {

  private Route createRoute() {
    final Random rnd = new Random();
    Source<Integer, NotUsed> numbers =
        Source.fromIterator(() -> Stream.generate(rnd::nextInt).iterator());

    return path("random", () ->
        get(() -> complete(
            HttpEntities.create(
                ContentTypes.TEXT_PLAIN_UTF8,
                numbers.map(n -> ByteString.fromString(n + "\n"))))));
  }
}
```

---

## 6. Low-level server API

Use `pekko-http-core` directly for full control. It works with `HttpRequest -> HttpResponse` functions or flows.

```java
import org.apache.pekko.stream.javadsl.Flow;

public class LowLevelServer {

  public static void main(String[] args) {
    final ActorSystem<Void> system = ActorSystem.create(Behaviors.empty(), "lowlevel");

    final Function<HttpRequest, HttpResponse> handler = request -> {
      if (request.getUri().path().equals("/ping")) {
        return HttpResponse.create().withEntity(ByteString.fromString("PONG!"));
      }
      request.discardEntityBytes(system);
      return HttpResponse.create()
          .withStatus(StatusCodes.NOT_FOUND)
          .withEntity("Unknown");
    };

    Http.get(system).newServerAt("localhost", 8080).bindSync(handler);
  }
}
```

Flow-based variant:

```java
Flow<HttpRequest, HttpResponse, NotUsed> handlerFlow = Flow.<HttpRequest>create()
    .map(request -> HttpResponse.create().withEntity("ok"));

Http.get(system).newServerAt("localhost", 8080).bindFlow(handlerFlow);
```

---

## 7. Client API

Pekko HTTP provides three client API levels. All use immutable `HttpRequest`/`HttpResponse`.

### Request-level API (recommended)

Connection pooling, retry, and queueing are managed automatically.

```java
import org.apache.pekko.http.javadsl.Http;

final CompletionStage<HttpResponse> response =
    Http.get(system).singleRequest(HttpRequest.create("https://pekko.apache.org"));

// Always consume or discard the response entity to free the connection
response.thenCompose(r -> r.discardEntityBytes(system).completionStage());
```

POST with entity:

```java
HttpRequest request = HttpRequest.create("https://api.example.com/items")
    .withMethod(HttpMethods.POST)
    .withEntity(ContentTypes.APPLICATION_JSON, ByteString.fromString("{\"name\":\"x\"}"));

Http.get(system).singleRequest(request)
    .thenCompose(r -> r.toStrict(3000, system).thenApply(HttpResponse::entity));
```

### Host-level API

Use a connection pool to one host/port, useful when you have a `Source<HttpRequest, ?>`.

```java
import org.apache.pekko.http.javadsl.HostConnectionPool;
import org.apache.pekko.http.javadsl.model.*;
import org.apache.pekko.japi.Pair;

Flow<Pair<HttpRequest, Integer>, Pair<Try<HttpResponse>, Integer>, HostConnectionPool> poolClientFlow =
    Http.get(system).cachedHostConnectionPoolTo("api.example.com", 443);

Source.single(Pair.create(HttpRequest.create("/items"), 42))
    .via(poolClientFlow)
    .runWith(Sink.foreach(pair -> System.out.println(pair.first())), system);
```

### Connection-level API

Manually open and close one HTTP connection. Use only when you need explicit connection control.

```java
Flow<HttpRequest, HttpResponse, CompletionStage<OutgoingConnection>> connectionFlow =
    Http.get(system).outgoingConnection("api.example.com", 443);

Source.single(HttpRequest.create("/"))
    .via(connectionFlow)
    .runWith(Sink.head(), system);
```

### Important: consume responses

Always consume or discard the response entity stream to return the connection to the pool:

```java
response.discardEntityBytes(system).completionStage();
// or
response.entity().getDataBytes().runWith(Sink.ignore(), system);
```

---

## 8. WebSocket server and client

### Server

```java
import org.apache.pekko.http.javadsl.model.ws.*;

public class WsRoutes extends AllDirectives {

  public Route createRoute() {
    return path("ws", () ->
        handleWebSocketMessages(
            Flow.<Message>create()
                .mapConcat(msg -> {
                  if (msg.isText()) {
                    return Collections.singletonList(TextMessage.create("echo: " + msg.asTextMessage().getStrictText()));
                  }
                  return Collections.emptyList();
                })));
  }
}
```

### Client

```java
final WebSocketRequest request = WebSocketRequest.create("wss://example.com/ws");

final Flow<Message, Message, CompletionStage<UpgradeResponse>> webSocketFlow =
    Http.get(system).webSocketClientFlow(request);

final Pair<CompletionStage<UpgradeResponse>, CompletionStage<Terminated>> pair =
    Source.<Message>maybe()
        .viaMat(webSocketFlow, Keep.both())
        .to(Sink.foreach(System.out::println))
        .run(system);
```

---

## 9. Exception handling and rejections

### ExceptionHandler

```java
import org.apache.pekko.http.javadsl.server.ExceptionHandler;
import org.apache.pekko.http.javadsl.server.RejectionHandler;

ExceptionHandler exceptionHandler = ExceptionHandler.create(exec -> {
  if (exec instanceof IllegalArgumentException) {
    return complete(StatusCodes.BAD_REQUEST, exec.getMessage());
  }
  return complete(StatusCodes.INTERNAL_SERVER_ERROR, "Oops");
});

final Route route = handleExceptions(exceptionHandler, () -> riskyRoute);
```

### RejectionHandler

```java
RejectionHandler rejectionHandler = RejectionHandler.newBuilder()
    .handle(MethodRejection.class, r -> complete(StatusCodes.METHOD_NOT_ALLOWED))
    .handleNotFound(complete(StatusCodes.NOT_FOUND, "Not here"))
    .build();

final Route route = handleRejections(rejectionHandler, () -> innerRoute);
```

---

## 10. Testing with the Route TestKit

Add `pekko-http-testkit` to test routes in isolation.

```java
import org.apache.pekko.http.javadsl.testkit.JUnitRouteTest;
import org.apache.pekko.http.javadsl.testkit.TestRoute;
import org.junit.Test;

public class RoutesTest extends JUnitRouteTest {

  @Override
  public ActorSystem system() {
    return ActorSystem.create(Behaviors.empty(), "test");
  }

  @Test
  public void testHello() {
    Routes routes = new Routes();
    TestRoute route = testRoute(routes.createRoute());

    route.run(HttpRequest.GET("/hello"))
        .assertStatusCode(StatusCodes.OK)
        .assertEntity("Hello!");
  }
}
```

Test classes: extend `JUnitRouteTest` or use `TestRouteResult` helpers like `assertStatusCode`, `assertEntity`, `entityAs(Class)`.

---

## 11. File uploads and multipart

Handle file uploads as streams of body parts.

```java
import org.apache.pekko.http.javadsl.server.directives.FileInfo;
import org.apache.pekko.http.javadsl.unmarshalling.Unmarshaller;
import org.apache.pekko.japi.Pair;

Route uploadRoute = path("video", () ->
    entity(Unmarshaller.entityToMultipartFormData(), formData -> {
      CompletionStage<Map<String, Object>> allParts = formData.getParts()
          .mapAsync(1, bodyPart -> {
            if ("file".equals(bodyPart.getName())) {
              File file = File.createTempFile("upload", ".tmp");
              return bodyPart.getEntity().getDataBytes()
                  .runWith(FileIO.toPath(file.toPath()), system)
                  .thenApply(io -> new Pair<String, Object>("file", file));
            } else {
              return bodyPart.toStrict(2000, system)
                  .thenApply(strict -> new Pair<String, Object>(
                      bodyPart.getName(),
                      strict.getEntity().getData().utf8String()));
            }
          })
          .runFold(new HashMap<>(), (acc, pair) -> {
            acc.put(pair.first(), pair.second());
            return acc;
          }, system);

      return onSuccess(allParts, x -> complete("ok!"));
    }));
```

Convenience directives for simple cases: `storeUploadedFile`, `storeUploadedFiles`.

---

## 12. HTTPS server support

Provide an `HttpsConnectionContext` when binding.

```java
import org.apache.pekko.http.javadsl.HttpsConnectionContext;
import org.apache.pekko.http.javadsl.ConnectionContext;

// Build or load an SSLContext for your keystore, then wrap it
HttpsConnectionContext httpsContext = ConnectionContext.httpsServer(sslContext);

Http.get(system)
    .newServerAt("localhost", 8443)
    .enableHttps(httpsContext)
    .bind(route);
```

For full setup details (keystores, protocols, cipher suites) see the official server-side HTTPS docs.

---

## 13. Configuration

Key defaults from `pekko.http` reference configuration:

```conf
pekko.http {
  server {
    preview.enable-http2 = off
    idle-timeout = 60 s
    request-timeout = 20 s
    bind-timeout = 1 s
    max-connections = 1024
  }
  host-connection-pool {
    max-connections = 32
    min-connections = 0
    max-open-requests = 64
    idle-timeout = 30 s
  }
}
```

Override via `application.conf` or programmatic `ServerSettings`/`ConnectionPoolSettings`.

```java
import org.apache.pekko.http.javadsl.settings.PreviewServerSettings;
import org.apache.pekko.http.javadsl.settings.ServerSettings;

ServerSettings settings = ServerSettings.create(system)
    .withPreviewServerSettings(
        PreviewServerSettings.create(system).withEnableHttp2(true));

Http.get(system)
    .newServerAt("localhost", 8080)
    .withSettings(settings)
    .bind(route);
```

---

## 14. Common gotchas

- **Discard unconsumed request/response entities.** Forgetting to drain an entity leaks pooled connections.
- **Routes are immutable and lazy.** A route only executes when bound and a request arrives.
- **Order matters in `concat`.** More specific routes should come before generic ones.
- **Use `completeOKWithFuture` for async JSON.** It combines `onSuccess` and a marshaller cleanly.
- **Jackson module is optional.** Add `pekko-http-jackson` explicitly; it is not part of `pekko-http`.
- **Always provide `pekko-stream`.** Pekko HTTP marks `pekko-stream` as `provided`; you must declare it.
- **TestKit needs `pekko-stream-testkit`.** Declare it alongside `pekko-http-testkit` at the same Pekko version.
- **HTTP/2 is preview.** Enable with `ServerSettings` / `PreviewServerSettings` if required.

---

## 15. Documentation coverage

The sections above map to the official Pekko HTTP documentation trail:

- [x] Introduction and motivation
- [x] Using Pekko HTTP / getting started
- [x] Routing DSL
- [x] Directives overview
- [x] Rejections
- [x] Exception handling
- [x] Marshalling and unmarshalling
- [x] JSON support (Jackson)
- [x] XML support
- [x] Multipart and file uploads
- [x] Core server API (low-level)
- [x] Client-side APIs (request, host, connection levels)
- [x] Client-side HTTPS
- [x] WebSocket support
- [x] HTTP/2 preview
- [x] Server-side HTTPS
- [x] Configuration
- [x] Testing with Route TestKit

---

## 16. References

- [Apache Pekko HTTP documentation](https://pekko.apache.org/docs/pekko-http/current/)
- [Pekko HTTP Java docs](https://pekko.apache.org/docs/pekko-http/current/java/http/)
- [Apache Pekko HTTP source repository](https://github.com/apache/pekko-http)
- [Apache Pekko compatibility guidelines](https://pekko.apache.org/docs/pekko-http/current/compatibility-guidelines.html)
