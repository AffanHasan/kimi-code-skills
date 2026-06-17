---
name: java-programming
description: Enforce Java coding style by preferring final variables, String constants, records, Java 8 Streams, and meaningful comments.
type: prompt
whenToUse: When generating, refactoring, or reviewing Java code.
---

# Java Programming Style

When this skill is active, apply the following rules to all Java code you generate or refactor.

## 1. Prefer `final` variables

Declare variables, parameters, and fields as `final` whenever their value does not change.

```java
// Avoid
String name = "Alice";
name = "Bob";

// Prefer
final String name = "Alice";
```

## 2. Use `String` constants for literals

Do not duplicate string literals. Extract them into named constants, usually `private static final`.

```java
// Avoid
System.out.println("ERROR: invalid input");
// ...
System.out.println("ERROR: invalid input");

// Prefer
private static final String ERROR_INVALID_INPUT = "ERROR: invalid input";
// ...
System.out.println(ERROR_INVALID_INPUT);
```

## 3. Prefer records over POJOs

Use `record` for immutable data carriers instead of verbose POJOs.

```java
// Avoid
public class Person {
    private final String name;
    private final int age;

    public Person(String name, int age) {
        this.name = name;
        this.age = age;
    }

    public String getName() {
        return name;
    }

    public int getAge() {
        return age;
    }
}

// Prefer
public record Person(String name, int age) {
}
```

## 4. Use Java 8 Streams

Favor the Stream API for collection transformations, filtering, and aggregation.

```java
// Avoid
List<String> result = new ArrayList<>();
for (String s : items) {
    if (s.startsWith("A")) {
        result.add(s.toUpperCase());
    }
}

// Prefer
final List<String> result = items.stream()
    .filter(s -> s.startsWith("A"))
    .map(String::toUpperCase)
    .toList();
```

## 5. Write meaningful, easy-to-read comments

Document the **why**, not the obvious. Use Javadoc for classes, constructors, and public methods. Keep inline comments short and only when they add value.

```java
// Avoid
public class Person { // this is a person class
    // constructor
    public Person(String name) {
        this.name = name; // set name
    }
}

// Prefer
/**
 * Represents a person with a unique name.
 */
public class Person {
    private final String name;

    /**
     * Creates a new person with the given name.
     *
     * @param name the person's full name; must not be blank
     */
    public Person(final String name) {
        this.name = name;
    }
}
```

## References

- `references/java-style-references.md` — authoritative Java documentation for `final`, records, and Streams.
