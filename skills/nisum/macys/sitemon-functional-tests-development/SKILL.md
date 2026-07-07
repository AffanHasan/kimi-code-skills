---
name: sitemon-functional-tests-development
description: Build and run Macy's sitemonetization-xapi functional tests with ci profile, WireMock mocks, and expected JSON comparisons.
type: prompt
whenToUse: |
  Use this skill when asked to create, add, or debug TestNG functional tests
  for the sitemonetization-xapi project, especially when the task involves:
  - Starting the service with the ci profile for functional testing
  - Stubbing external dependencies (Criteo, Amazon Ads, FCC, Promo, Rules Publisher)
    with WireMock on port 9001
  - Converting real curl request/response samples into mock JSON files and
    expected SiteMon responses
  - Adding new endpoints to Constants.java and helper stubs to MockServiceUtility.java
  - Running functional tests via Maven failsafe
arguments: []
---

# Macy's SiteMonetization XAPI Functional Test Development Guide

## Project Context

- **Repo**: `sitemonetization-xapi` (Spring Boot, Java 17, Maven multi-module)
- **Functional-test module**: `functional-test/` (TestNG + WireMock + REST Assured)
- **Service port**: `8080`
- **Mock server port**: `9001`
- **Required profile for functional tests**: `ci`
- **Critical prerequisite**: Redis must be running on port 6379; stale cache can suppress vendor calls
  (e.g. Amazon) and produce only Criteo products or HTTP 204. The helper script flushes Redis
  automatically, but if you run manually, execute `redis-cli FLUSHALL` before starting the service.
- **Always build the whole project**: Because the functional-test module depends on
  `Constants.java` and `MockServiceUtility.java` inside `functional-test/src/test/java`,
  building only the service JAR will not pick up test-source changes. Use
  `mvn clean install -DskipTests -q` from the repository root.

## Mandatory Pre-Automation Code Verification

Before writing any test, mock, or expected response, you **must** verify how the actual service code behaves for the scenario. Do not assume the curl samples or an existing similar test tell the whole story. Cross-check the following in the `service` module:

### 1. Verify the Page ID and Device Mapping

Read `service/src/main/java/com/macys/marketing/xapi/sitemonetization/util/SiteMonetizationUtil.java` and `service/src/main/java/com/macys/marketing/xapi/sitemonetization/util/Constants.java`:

- Confirm the exact string for the page ID (e.g. `sm-search-desktop`, `sm-browse-desktop`, `sm-product-desktop`).
- Confirm the corresponding constant (e.g. `Constants.SEARCH_DESKTOP`, `Constants.BROWSE_DESKTOP`).
- Confirm the device type resolved for that page ID.

### 2. Verify RMP and Kill-Switch Logic

Read `SiteMonetizationUtil.isRMPEnable(...)` and `service/src/main/java/com/macys/marketing/xapi/sitemonetization/ks/KillswitchPropertiesBean.java`:

- Is RMP decided by query param `version=1.1` plus a page-specific kill switch?
- What is the exact property name for the page type? (Pattern: `<page-id>.rmp.enabled`, kebab-case, e.g. `sm-search-desktop.rmp.enabled`.)
- If the scenario uses special filters (age, gender, size, brand, price, rating, etc.), verify the relevant filter-passthrough kill switches. Examples include:
  - `amazon.additional.filters.enabled`
  - `criteo.additional.filters.enabled`
  - `sm-plp-site.additional.filters.enabled`
  - `sm-plp-app.additional.filters.enabled`
  - Any other `<page-id>.<filter-type>.enabled` or similar property referenced in the code for the scenario.

If RMP is required, add **only** the exact kill switches for the page types being automated. Do not blanket-enable every page type unless the story explicitly requires it.

### 3. Verify the External Call Flow

Trace the code path for the endpoint under test (typically `/v1/sponsored-items/{pageId}`):

- Resource class: `SiteMonetizationResource.java`
- Service class: `SiteMonetizationServiceImpl.java`
- Component classes: `ProductAddComponent.java`, `WaterfallAdComponent.java`, `CriteoComponent.java`, `AmazonAdsComponent.java`
- Client classes: `CriteoWebClient.java`, `AmazonAdsWebClient.java` (or corresponding REST client adapters)
- Response builders: `SponsoredItemsResponseBuilder.java`, `ProductAdResponseBuilder.java`

For the scenario, determine:
- Which external services are called (Criteo, Amazon, Pentaleap, FCC, Promo, Rules Publisher)?
- Which endpoint/path does each service call under the required kill-switch state?
- How are query parameters and request bodies built? Are filters passed in the URL query string or in the POST body?
- How does the response get transformed? Are product IDs remapped? Are beacons copied, dropped, or transformed?

### 4. Verify Beacon Behavior

If the scenario involves RMP, verify in `ProductAddComponent.java` and `SponsoredItemsResponseBuilder.java`:

- Are `sponsoredItems.onLoadBeacon` and `sponsoredItems.onViewBeacon` populated only when RMP is enabled?
- How many product-level beacons are expected per product in RMP vs non-RMP mode?
- Which beacons come from Criteo vs Amazon?

Use this to decide whether captured responses need wrapper-beacon updates before becoming expected JSONs.

### 5. Verify Request/Response DTO Fields

Open the relevant request and response DTOs (e.g. `SponsoredProductsRequest.java`, `SponsoredItems.java`, `ProductAd.java`) and the validator class (`SiteMonetizationDataValidator.java`):

- Which query parameters are mandatory?
- Which headers are required?
- Which response fields are always present vs optional?
- Are there field-name or format constraints (e.g. `pageId`, `deviceType`, `version`)?

## Request/Response Sample Validation Checklist

The curl samples provided for a story are a starting point, not gospel. Validate every sample against the code before turning it into a mock or expected response:

### Validate the SiteMon Request Sample

- [ ] JSON is valid and parseable.
- [ ] `pageId` in the URL matches the scenario's page type and the code constant.
- [ ] `deviceType` matches the expected device (DESKTOP, TABLET, PHONE, APP).
- [ ] `version=1.1` is present if RMP is required; absent or different if non-RMP is intended.
- [ ] All required query parameters from the validator/DTO are present.
- [ ] Filter parameters (e.g. `age_category`, `gender`, `SIZE`, `BRAND`, `PRICE`, `RATING`) are spelled and formatted exactly as the service code expects.
- [ ] `selectedFacets` matches the applied filters when facet-based logic is in play.
- [ ] Required headers (`x-macys-clientid`, `X-Macys-RequestID`, etc.) are present.

### Validate the Criteo Sample

- [ ] JSON is valid and parseable.
- [ ] The request URL path matches the RMP state determined in code verification (`/delivery/retailmedia` for RMP enabled, `/delivery/adserving` otherwise).
- [ ] Query parameters include the values the service actually sends (e.g. `keywords`, `category`, `page-number`, `regionId=Control`).
- [ ] Filter values appear in the correct place (query string vs POST body) per the code.
- [ ] Response contains the fields the builder reads (`products`, `onLoadBeacon`, `onViewBeacon`, product-level beacons, etc.).

### Validate the Amazon Sample

- [ ] JSON is valid and parseable.
- [ ] OAuth request/response shape matches `AmazonAdsComponent` expectations.
- [ ] GetAds request body contains the expected fields.
- [ ] GetAds response contains `seatbid` and the fields mapped by `ProductAdResponseBuilder`.
- [ ] **Response format compatibility**: The service may drop Amazon bids if the `adm_native` payload does not match the exact shape expected by `ProductAdResponseBuilder`. Do not assume a captured curl response will be accepted as-is. If the actual service response returns fewer Amazon products than the curl sample, compare the working Amazon mock from an existing happy-flow test with the captured sample. Prefer the smallest valid response (typically one `assets` entry with `data.type=600`) and update the expected SiteMon response to reflect the actual service output, not the original curl sample.

### Validate the SiteMon Expected Response

- [ ] JSON is valid and parseable.
- [ ] Top-level `sponsoredItems` fields (`products`, `onLoadBeacon`, `onViewBeacon`, etc.) match what `SponsoredItemsResponseBuilder` produces for the scenario.
- [ ] Each product contains the fields the builder sets, including the correct beacon set for the RMP state.
- [ ] Product IDs match the transformation logic in the code (e.g. member_item_id, ParentSKU, Consolidated/Master mapping).
- [ ] Pagination fields (`pageIndex`, `totalCount`, etc.) match the request when pagination is tested.

If any sample violates the code expectations, ask the user for clarification or recapture the sample before proceeding.

## Quick Start: Build and Run Functional Tests

Use the bundled helper script in this skill directory:

```bash
${KIMI_SKILL_DIR}/run-functional-tests.sh
```

Or from the project root copy the script and run it:

```bash
cp ${KIMI_SKILL_DIR}/run-functional-tests.sh /path/to/sitemonetization-xapi/
cd /path/to/sitemonetization-xapi
./run-functional-tests.sh Discovery_Search_<Scenario>_SM_DesktopIT
```

The helper script performs these steps:

1. Checks for Redis; if it is not running and `redis-server` is available, it starts Redis on port 6379, then flushes it with `redis-cli FLUSHALL`.
2. Builds the service **and the functional-test module** so source/test changes are picked up: `mvn clean install -DskipTests -q`
3. Starts the service: `java -jar service/target/sitemonetization-xapi-service-1.0.0-SNAPSHOT.jar --spring.profiles.active=ci --server.port=8080`
4. Polls `/sitemonetization/actuator/health/liveness` until `UP`.
5. Runs functional tests: `mvn -pl functional-test verify -DskipFunctionalTests=false -DskipTests=true`
6. Stops the service and the Redis instance that the script started on exit.

## Manual Run (Alternative)

```bash
cd /path/to/sitemonetization-xapi
redis-cli FLUSHALL
mvn clean install -DskipTests -q
java -jar service/target/sitemonetization-xapi-service-1.0.0-SNAPSHOT.jar --spring.profiles.active=ci --server.port=8080 &
# wait for health UP
curl -s http://localhost:8080/sitemonetization/actuator/health/liveness
mvn -pl functional-test verify -DskipFunctionalTests=false -Dit.test=<TestClassName> -DskipTests=true
```

## File Layout for Functional Tests

```
functional-test/src/test/java/com/macys/platform/xapi/sitemonetization/it/
├── test/
│   ├── BaseTest.java
│   ├── Constants.java            <-- add endpoint constants here
│   └── SM_ServiceTest/
│       └── <Device>/
│           └── Discovery_...SM_<Device>IT.java <-- new test class here
└── util/
    └── MockServiceUtility.java   <-- add mock helpers here
```

**Important naming convention**: The functional-test module uses Maven Failsafe with the default
`*IT.java` include pattern. New test classes must end in `IT.java` (e.g.
`Discovery_Search_<Scenario>_SM_DesktopIT.java`). Classes named only `*SM_Desktop.java` are
ignored by the full suite.

```
functional-test/src/test/resources/SitemonJsonFiles/<BRAND>/<DEVICE>/<PAGE>/
├── *_Criteo_Response.json
├── *_Amazon_Response.json
└── *_Sitemon_Response.json       <-- expected response
```

A shared `OAuth_Token_Response.json` is normally used for the Amazon OAuth stub.

## Step-by-Step: Add a New Functional Test from Real Curl Samples

### 1. Identify the Scenario and Verify the Code Path

From the Jira story, determine:

- Page type: `Search`, `Browse`, `Homepage`, `PDP`, `Deals`, `ZeroSearchResult`, etc.
- Device: `Desktop`, `Tablet`, `Phone`, `App`
- Brand: `MCOM` or `BCOM`
- Query parameters, headers, and filters (e.g. `age_category`, `SIZE`, `PRICE`, `RATING`)

Then perform the **Mandatory Pre-Automation Code Verification** above. Document the findings:
- Exact page ID and constant
- RMP kill-switch property name
- Filter-passthrough kill-switch property names
- External services called and their expected paths
- Expected response structure (wrapper beacons, product beacons, product ID mapping)

Do not proceed to creating mocks until this verification is complete.

### 2. Validate the Provided Curl Samples

Run the **Request/Response Sample Validation Checklist** against every curl sample. If a sample is invalid or does not match the code path, stop and ask the user for a corrected capture.

### 3. Add Endpoint Constants

Open `functional-test/src/test/java/com/macys/platform/xapi/sitemonetization/it/test/Constants.java`.

Add constants following existing naming. Use placeholders that match the scenario:

```java
public static final String SEARCH_<SCENARIO>_<DEVICE>_<USERTYPE> =
    "sponsored-items/sm-search-desktop?deviceType=DESKTOP&regionCode=US&keywords=shoes&pageIndex=1&...";
```

If new external mocks are needed, add their endpoints too:

```java
public static final String AMAZON_OAUTH_ENDPOINT = "/auth/o2/token";
public static final String AMAZON_GETADS_ENDPOINT = "/getAds";
```

### 4. Copy Real Response Samples to Mock JSON Files

Use the validated curl responses provided in the story directory (e.g. `/Users/ahasan/macys/curls/<story>/<scenario>/`).

Save them under the appropriate resource folder with naming convention:

```
<scenario>_<Vendor>_Response.json
```

For example:

- `search_GuestUser_<Scenario>_Amazon_Response.json`
- `search_GuestUser_<Scenario>_Criteo_Response.json`

The Amazon OAuth token is usually mocked once with a shared response; call
`mockServiceUtility.amazonOAuthServiceMock(Constants.AMAZON_OAUTH_ENDPOINT)` instead of
providing a per-scenario OAuth file.

### 5. Add Mock Helpers (If Not Already Present)

Open `functional-test/src/test/java/com/macys/platform/xapi/sitemonetization/it/util/MockServiceUtility.java`.

Reusable helpers already available (verify in code which one matches the scenario):

```java
public void amazonOAuthServiceMock(String endPoint)
public void amazonGetAdsServiceMock(String endPoint, String requestFullFilePath, String responseFullFilePath)
public void criteoRMPServiceMockByPath(String responseFullFilePath, String keywords)
public void criteoRMPServiceMockByCategory(String responseFullFilePath, String categoryId)
```

`criteoRMPServiceMockByPath` is used for search pages where the Criteo RMP request carries
`keywords`. `criteoRMPServiceMockByCategory` is preferred for browse/category pages because it
matches on `category=<categoryId>` and ignores volatile params like `regionId` or query ordering.

Add new helpers only when a vendor endpoint changes significantly. Match URL path, query params, and HTTP method as the service expects.

**Note on Criteo RMP stubs**: When RMP is enabled, the service calls `/delivery/retailmedia`. The query string may include volatile params such as `regionId`, `retailer-visitor-id`, or query-param ordering. Prefer `criteoRMPServiceMockByPath` for search (matches on `keywords`) or `criteoRMPServiceMockByCategory` for browse (matches on `category`). Avoid matching on a `filters` query param for search pages because the service passes filters in the request body, not the URL.

**Note on generating expected responses**: `MockServiceUtility.compareJsons()` writes side-by-side diff files under `functional-test/target/functional-test-diffs/` when a comparison fails. For a brand-new test, temporarily capture the actual response, inspect it, and copy it to the expected response path. Do not hand-edit a JSON comparison file from a failing run unless you have confirmed the actual output is correct.

### 6. Handle Special Scenario Variants

#### Pagination
When the scenario uses `pageIndex` other than `1`, keep the same index in both:
- The SiteMon endpoint constant (`pageIndex=3`)
- The Criteo endpoint constant (`page-number=3`)

Example:
```java
BROWSE_<SCENARIO>_PAGINATION_DESKTOP_GUESTUSER =
    "...pageIndex=3...";
BROWSE_<SCENARIO>_PAGINATION_CRITEO_GUEST_ENDPOINT =
    "/delivery/retailmedia?...page-number=3...";
```

#### Mixed Filters
When multiple facet filters are applied together (e.g. `age_category` + `BRAND` or `age_category` + `PRICE`), ensure:
- The SiteMon `filters` parameter includes every filter expression.
- The SiteMon `selectedFacets` parameter lists every facet code.
- The Criteo mock URL includes the combined filter expression.

For browse/category pages with mixed filters, use `criteoRMPServiceMockByCategory(criteoFile, "<categoryId>")` so volatile query ordering does not break the stub.

### 7. Create the Test Class

Create a class under `functional-test/src/test/java/com/macys/platform/xapi/sitemonetization/it/test/SM_ServiceTest/<Device>/`.

Use this template:

```java
package com.macys.platform.xapi.sitemonetization.it.test.SM_ServiceTest.<Device>;

import com.github.tomakehurst.wiremock.WireMockServer;
import com.github.tomakehurst.wiremock.client.WireMock;
import com.macys.platform.xapi.sitemonetization.it.test.BaseTest;
import com.macys.platform.xapi.sitemonetization.it.test.Constants;
import com.macys.platform.xapi.sitemonetization.it.util.MockServiceUtility;
import io.restassured.RestAssured;
import io.restassured.path.json.JsonPath;
import io.restassured.response.Response;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.testng.Assert;
import org.testng.annotations.AfterClass;
import org.testng.annotations.BeforeClass;
import org.testng.annotations.Test;

import java.io.IOException;

import static com.macys.platform.xapi.sitemonetization.it.test.Constants.*;
import static io.restassured.RestAssured.given;

public class Discovery_<Page>_<Scenario>_SM_<Device>IT extends BaseTest {

    private static final Logger logger = LoggerFactory.getLogger(Discovery_<Page>_<Scenario>_SM_<Device>IT.class);
    public static WireMockServer server = new WireMockServer(MOCK_PORT);
    MockServiceUtility mockServiceUtility;

    @BeforeClass(enabled = true)
    public void beforeClass() {
        logger.info("Starting mock server......");
        server.start();
        WireMock.configureFor(MOCK_HOST, MOCK_PORT);
        logger.info("mock server running on port: " + MOCK_PORT);
        mockServiceUtility = new MockServiceUtility();
    }

    @Test(testName = "Scenario_<ID>_<JIRA>-<Short_Description>")
    public void <page>_GuestUser_<Scenario>_siteMonResponseValidation() throws Exception {
        logger.info("initializing mock services......");

        // Amazon OAuth mock (shared token response)
        mockServiceUtility.amazonOAuthServiceMock(Constants.AMAZON_OAUTH_ENDPOINT);

        // Amazon getAds mock
        String amazonGetAdsFile = mockServiceUtility.getFilePath("<page>_GuestUser_<Scenario>_Amazon_Response.json", "<Device>", "<BRAND>");
        mockServiceUtility.amazonGetAdsServiceMock(Constants.AMAZON_GETADS_ENDPOINT, null, amazonGetAdsFile);

        // Criteo RMP mock (use criteoRMPServiceMockByCategory for browse/category pages)
        String criteoFile = mockServiceUtility.getFilePath("<page>_GuestUser_<Scenario>_Criteo_Response.json", "<Device>", "<BRAND>");
        mockServiceUtility.criteoRMPServiceMockByPath(criteoFile, "<keywords>");

        logger.info("All mock services are up and running......");
        purgeCache();

        Response response = given()
                .header(Constants.CONTENT_TYPE, Constants.HEADER_APPLICATION_JSON)
                .header(Constants.ACCEPT, Constants.HEADER_APPLICATION_JSON)
                .header("x-macys-clientid", "discovery-xapi")
                .header("X-Macys-RequestID", "bd51af21029a4efd")
                .header("True-Client-IP", "72.255.58.68")
                .header("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
                .when().urlEncodingEnabled(false).get(getHost() + <PAGE>_<SCENARIO>_<DEVICE>_<USERTYPE>);

        int statusCode = response.getStatusCode();
        Assert.assertEquals(statusCode, 200, "Status code displayed 200 Ok");

        int size = response.jsonPath().getList("sponsoredItems.products").size();
        Assert.assertTrue(size > 0, "sponsoredItems.products should not be empty");

        String expectedResponseFile = mockServiceUtility.getFilePath("<page>_GuestUser_<Scenario>_Sitemon_Response.json", "<Device>", "<BRAND>");
        String actualResponse = response.getBody().asString();
        Assert.assertTrue(mockServiceUtility.compareJsons("<page>_GuestUser_<Scenario>", actualResponse, expectedResponseFile),
                "Actual and expected site monetization response is not matching");
    }

    @AfterClass(enabled = true)
    public void afterClass() {
        logger.info("Stopping the server.......");
        server.stop();
    }
}
```

### 8. Generate the Expected SiteMon Response

For a brand-new test, **derive the expected SiteMon response from the actual service output**, not from the captured curl sample. The curl sample is useful for building mocks, but the service may transform or drop products based on kill switches, cache, or response-parsing rules.

`MockServiceUtility.compareJsons()` writes side-by-side diff files when a comparison fails:

```
functional-test/target/functional-test-diffs/<methodName>_expected.json
functional-test/target/functional-test-diffs/<methodName>_actual.json
```

Use these files to identify the mismatch. To capture the actual response for a brand-new test:

1. Comment out the full JSON assertion temporarily.
2. Capture the actual response to a file using `StandardCharsets.UTF_8`:

```java
java.nio.file.Files.createDirectories(java.nio.file.Paths.get("target"));
java.nio.file.Files.write(java.nio.file.Paths.get("target/actual-response.json"),
        response.getBody().asString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
```

3. Run the test once.
4. Review `target/actual-response.json` and, if correct, copy it to the expected response path:

```bash
functional-test/src/test/resources/SitemonJsonFiles/<BRAND>/<Device>/<Page_Page>/<name>_Sitemon_Response.json
```

5. Remove the capture code and uncomment the `compareJsons` assertion.

#### Schema maxItems

If the scenario returns more than 10 products, do not reuse an existing schema with `maxItems: 10`. Create a scenario-specific schema file under `SchemaFiles/` with `maxItems` set to at least the observed product count (e.g. `40`). Update the test class to reference the new schema. Existing happy-flow schemas are not universally applicable.

### 9. Update Service Configuration If Needed

If the scenario requires new kill switches (e.g. filter passthrough, RMP), add them to `service/src/main/resources/application-ci.properties`:

```properties
# RMP (Retail Media Platform) kill switches - use kebab-case with `.rmp.enabled` suffix
# Only enable the page types actually exercised by the scenario
sm-search-desktop.rmp.enabled=true
sm-browse-desktop.rmp.enabled=true

# Example: enable filter passthrough for a specific vendor/page type
amazon.additional.filters.enabled=true
criteo.additional.filters.enabled=true
sm-plp-site.additional.filters.enabled=true
sm-plp-app.additional.filters.enabled=true
```

Also ensure external service URIs point to the mock server:

```properties
criteo.uri=http://localhost:9001/
amazon.oauth.uri=http://localhost:9001/
amazon.getAds.uri=http://localhost:9001/
fcc.uri=http://localhost:9001/
promo.uri=http://localhost:9001/
rules.publisher.uri=http://localhost:9001/
```

### 10. Run the Test

Use the helper script for a single test:

```bash
./run-functional-tests.sh Discovery_<Page>_<Scenario>_SM_<Device>IT
```

Or run the full suite to confirm the new test is discovered:

```bash
./run-functional-tests.sh
```

Check the Failsafe summary for an increased test count. If the count did not go up,
verify the class name ends in `IT.java`.

If it fails with only Criteo products or HTTP 204, **flush Redis** and rerun.

## Common Pitfalls

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Test automated without verifying code path | Skipped pre-automation code verification | Go back and trace the code path; fix mocks/expected JSON/config accordingly |
| Mock/expected JSON does not match actual service output | Request/response samples were not validated against code | Re-run the Request/Response Sample Validation Checklist; recapture if needed |
| HTTP 204 or empty products | Stale Redis cache | `redis-cli FLUSHALL` before starting service |
| Only Criteo in response, Amazon missing | Amazon disabled by cache or killswitch | Flush Redis; verify `application-ci.properties` kill switches |
| Criteo hits `/delivery/adserving` instead of `/delivery/retailmedia` | RMP not enabled for page type | Add `<page-id>.rmp.enabled=true` in `application-ci.properties` (kebab-case, e.g. `sm-search-desktop.rmp.enabled=true`) |
| WireMock returns 404 on Criteo | Missing `regionId=Control` or query-param ordering | Copy exact request URL from access log / WireMock mismatch and update the constant |
| WireMock returns 404 on FCC | Exact product ID list changed | Use `urlPathMatching("/api/catalog/v2/products/[0-9,]+")` instead of `urlPathEqualTo` |
| JSON compare fails | Dynamic fields or ordering, or expected JSON is stale | Use the diff files under `target/functional-test-diffs/` to compare; regenerate expected response if service output is correct |
| Expected JSON matches curl sample but test fails | Service dropped Amazon products due to incompatible `adm_native` shape; or schema `maxItems` is too low | Use the actual service response as the expected JSON; create a scenario-specific schema with sufficient `maxItems` |
| Functional test source changes not picked up | Only service module was rebuilt | Build from root with `mvn clean install -DskipTests -q` (not `-pl service -am`) |
| New tests do not run in full suite | Class name does not match Failsafe `*IT.java` pattern | Rename class and file to `Discovery_...<Device>IT.java` (e.g. `Discovery_Search_<Scenario>_SM_DesktopIT.java`) |
| HTTP 204 on a fresh colleague's machine | Service started without `ci` profile or stale process on port 8080 | Ensure `java -jar ... --spring.profiles.active=ci`; kill any old process on port 8080; flush Redis |
| HTTP 204 after code changes | Stale Redis cache or changed kill switches | `redis-cli FLUSHALL`; verify `application-ci.properties` has correct RMP/filter switches for the page type |

## References

- Helper script: `${KIMI_SKILL_DIR}/run-functional-tests.sh`
- Key code files to verify for any scenario:
  - `SiteMonetizationUtil.java`
  - `KillswitchPropertiesBean.java`
  - `SiteMonetizationResource.java`
  - `SiteMonetizationServiceImpl.java`
  - `ProductAddComponent.java`
  - `CriteoWebClient.java` / `CriteoComponent.java`
  - `AmazonAdsComponent.java` / `AmazonAdsWebClient.java`
  - `SponsoredItemsResponseBuilder.java`
  - `ProductAdResponseBuilder.java`
  - `SiteMonetizationDataValidator.java`
- Look at existing test classes and resource files in the same page/device area for naming conventions, but always verify the code path independently rather than copying assumptions.
