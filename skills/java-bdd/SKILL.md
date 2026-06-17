---
name: java-bdd
description: A strict BDD workflow for Java projects using Cucumber JVM, Gherkin, and user stories.
type: prompt
whenToUse:
  - When implementing, refactoring, or reviewing Cucumber JVM features in a Java project.
  - When writing or updating Gherkin scenarios, step definitions, or glue code.
  - When turning user stories into executable specifications.
---

# Java BDD Workflow (Cucumber JVM)

When this skill is active, use Behavior-Driven Development (BDD) with [Cucumber JVM](https://cucumber.io/docs/cucumber/api) to turn requirements into executable specifications. Follow the workflow below strictly.

## Core principles

- A feature is a conversation, not just a test. Start from the user's goal.
- Write Gherkin in business language, not implementation detail.
- One scenario should prove exactly one business rule.
- Keep scenarios independent and repeatable.
- Let the scenario drive the implementation; do not retrofit tests to existing code.

## Strict workflow

### Step 1: Scenario definition & feedback

- Given a requirement or user story, write the smallest "happy path" Gherkin scenario that captures the business value.
- Use the `Feature`, `Scenario`, `Given`, `When`, `Then`, `And`, `But` keywords correctly. See the [Gherkin reference](https://cucumber.io/docs/gherkin/reference) for syntax rules.
- Stop and ask the user for feedback. Iterate on the scenario until the user explicitly accepts it.

**Good scenario traits:**

- Concrete examples, not abstract rules.
- One `When` per scenario (one action).
- Verifiable `Then` outcomes.
- No UI, database, or API jargon unless the business domain requires it.

### Step 2: Failing integration steps

- Once the scenario is accepted, generate the corresponding empty/failing step definitions in Java.
- Use [Cucumber Expressions](https://github.com/cucumber/cucumber-expressions#readme) for parameter capture. Prefer `{int}`, `{string}`, `{word}`, and custom parameter types over regex when possible.
- Verify that the project **compiles successfully** even though the tests are designed to fail.

### Step 3: Minimal implementation

- Write the smallest amount of production Java code needed to make the scenario pass.
- Do not add speculative features, abstractions, or optimizations.
- Follow the `java-programming` skill for Java style (final variables, records, streams, string constants).

### Step 4: Verification & loop

- Run the scenario with the project's build tool (Maven or Gradle).
- If it fails, analyze the output and run internal fix loops until the scenario passes.
- Do not proceed to the next step while the new scenario is red.

### Step 5: Explanation

- Ask the user whether they want an explanation of the implementation.
- If yes, explain the code and iterate on clarifications until the user is satisfied.

### Step 6: Refactoring & regression

- Ask the user whether any refactoring is required.
- If yes, refactor and immediately run **all** tests to ensure no regressions.

## Gherkin best practices

### Scenario organization

- Group related scenarios under one `Feature`.
- Use `Background` only for preconditions shared by every scenario in the feature. Avoid lengthy backgrounds; prefer explicit `Given` steps when in doubt. See [step organization](https://cucumber.io/docs/gherkin/step-organization) for details.
- Prefer scenario titles that describe the business rule, e.g. `Scenario: Withdrawal rejected when balance is insufficient`.

### Anti-patterns to avoid

Follow the [Cucumber anti-patterns guide](https://cucumber.io/docs/guides/anti-patterns):

- **False positives:** do not write steps that always pass.
- **Imperative scenarios:** avoid scripts of UI clicks and form fills; describe behavior in business terms.
- **Incidental details:** remove data that does not affect the outcome.
- **Brittle selectors:** do not hard-code UI locators or IDs in Gherkin.
- **Testing through the UI:** interact with the domain layer directly unless the scenario is explicitly about UI behavior.

### User stories

When a scenario comes from a [user story](https://cucumber.io/docs/terms/user-story), keep the focus on the user's goal:

```gherkin
Feature: Cash withdrawal
  Scenario: Withdrawal rejected when balance is insufficient
    Given Alice has a balance of $50
    When she withdraws $100
    Then the withdrawal is rejected
    And her balance remains $50
```

## Java step-definition conventions

- Place step definitions in a package such as `com.example.cucumber.steps`.
- Annotate methods with `@Given`, `@When`, `@Then`, `@And`, or `@But` from `io.cucumber.java.en`.
- Use constructor or field dependency injection with `io.cucumber.picocontainer`, Spring, or another supported DI container.
- Share state between steps via injected context objects, not static fields.
- Keep step definitions thin: parse inputs, delegate to the domain/service layer, and assert outcomes.

Example:

```java
package com.example.cucumber.steps;

import io.cucumber.java.en.Given;
import io.cucumber.java.en.When;
import io.cucumber.java.en.Then;

public final class AccountSteps {

    private final AccountContext context;

    public AccountSteps(final AccountContext context) {
        this.context = context;
    }

    @Given("a customer has a balance of ${int}")
    public void a_customer_has_a_balance_of(final int balance) {
        context.setAccount(new Account(balance));
    }

    @When("the customer withdraws ${int}")
    public void the_customer_withdraws(final int amount) {
        context.setResult(context.getAccount().withdraw(amount));
    }

    @Then("the withdrawal is rejected")
    public void the_withdrawal_is_rejected() {
        assertThat(context.getResult()).isEmpty();
    }
}
```

## References

- `references/cucumber-references.md` — authoritative Cucumber JVM and Gherkin documentation.
