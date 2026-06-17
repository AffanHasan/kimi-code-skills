---
name: pekko-actor-based-development
description: Enables the agent to design and implement highly concurrent, distributed, and resilient software systems using modern Apache Pekko Typed standards.
type: prompt
whenToUse:
  - When generating, refactoring, or reviewing Apache Pekko actor-based code.
  - When designing concurrent, distributed, or fault-tolerant systems with Pekko Typed.
  - When discussing actor hierarchies, supervision, messaging patterns, or testing strategies in Pekko.
---

# Apache Pekko Actor-Based Development

Use this skill to guide the design and implementation of concurrent, distributed, and resilient software systems using **Apache Pekko Typed**. Prefer modern, type-safe actor practices over classic untyped actors.

## Core Principles & Standards

### Type-Safe Messaging
- Use **Pekko Typed**, where an `ActorRef<T>` is parameterized with the specific message type `T` it can receive.
- This compile-time constraint prevents "pointless messages" from being sent to an actor.

### State Management via Behaviors
- Actors manage internal state not through mutable variables, but by **returning a new `Behavior`** for the next message.
- State transitions become explicit and race-condition-free without locks or synchronization primitives.

### Encapsulation & Isolation
- All internal state is strictly shielded.
- Interaction happens exclusively through asynchronous message passing.

### Immutability
- Messages must be immutable to prevent accidental sharing of mutable state, which would break the actor model's concurrency guarantees.
- Prefer Java records, Scala case classes, or final immutable classes for message types.

## Architectural Patterns

### Strict Hierarchical Structure
Actors are organized in a tree where every child has a parent:

- **The Root Guardian (`/`)**: The base of the system, parent to all other guardians.
- **The System Guardian (`/system`)**: Manages internal utilities like logging and orderly shutdown.
- **The User Guardian (`/user`)**: The top-level actor provided by the user to bootstrap application subsystems.

### Error Kernel Pattern
- Push potentially dangerous or high-risk sub-tasks (e.g., network calls, disk I/O) to child actors.
- This localizes failures and protects the parent's vital state from corruption.

### Location Transparency
- Design actors to communicate identically whether they are in the same JVM or on different nodes in a Pekko Cluster.
- Avoid relying on local-only assumptions in message protocols.

## Lifecycle & Fault Tolerance

### Explicit Lifecycle
- Actors must be explicitly started using `context.spawn()` and explicitly stopped.
- Stopping a parent recursively stops all children to prevent resource leaks.

### Supervision Strategies
Parents act as supervisors for their children, deciding how to respond to failures:

- **Restart**: The default case; wipes the actor state and starts fresh.
- **Stop**: Permanently terminates the actor.
- **Resume**: Ignores the error and keeps the current state (rarely used).
- **Escalate**: Passes the failure to the parent's own supervisor.

### Lifecycle Signals
- Use `PostStop` for cleaning up resources.
- Use `PreRestart` for actions immediately before an actor is recreated after a failure.

## Interaction Patterns

### Tell vs. Ask
- Prefer the asynchronous **tell (`!`)** pattern to preserve non-blocking behavior.
- Use the **ask (`?`)** pattern sparingly, as it introduces implicit synchronization and timeouts.

### Death Watch
- Use `context.watch(actorRef)` to monitor the transition of another actor from alive to dead.
- The monitoring actor receives a `Terminated` message when the target stops.

### Backpressure & Mailboxes
- Monitor mailbox sizes as a "canary in the coal mine" for system health.
- Growing mailboxes signal a need for circuit breakers or load shedding rather than larger queues.

## Testing & Observability

### Unit Testing
- Test individual behaviors by providing mock environments.
- Use the Pekko typed testkit to verify behavior logic in isolation.

### Integration Testing
- Use `TestProbe`s to verify message flows between multiple actors.
- Validate supervision and lifecycle behavior under failure scenarios.

### Structured Logging
- Utilize Pekko's logging facilities to maintain context across asynchronous operations.
- Include actor paths and correlation identifiers in log entries where appropriate.

## References

- [Apache Pekko Documentation](https://pekko.apache.org/docs/)
- [Apache Pekko Typed](https://pekko.apache.org/docs/pekko/current/typed/index.html)
- [Apache Pekko Cluster](https://pekko.apache.org/docs/pekko/current/typed/cluster.html)
