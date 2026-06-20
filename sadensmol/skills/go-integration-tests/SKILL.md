---
name: go-integration-tests
description: |
  Create integration tests for Go applications using testify/suite framework. Use when the user requests: (1) creating tests for new functionality, (2) covering new code with tests, (3) adding new related tests, (4) creating integration tests for Go services or applications, (5) testing API endpoints (gRPC, HTTP), (6) testing database interactions, (7) testing with external service dependencies. Guides test creation with proper suite hierarchy, gRPC mocking via bufconn, fixtures/test data management, and testify assertion patterns.
---

# Go Integration Tests

Create integration tests for Go applications using the testify/suite framework with hierarchical test suites, gRPC mocking, and comprehensive test data management.

## Before Writing Tests

Critical guidelines before creating any tests:

1. **Check existing tests first** - Understand patterns used in the project
2. **Follow the same pattern** - Don't invent new test styles
3. **NEVER touch the code when writing tests** - If code changes are needed, ask first
4. **Use testify/suite** - All integration tests use testify/suite framework
5. **Fixtures for read-only tests ONLY** - If test modifies data, use dynamic data with defer cleanup
6. **NEVER use time.Sleep** - Always use `require.Eventually` for async operations
7. **NEVER modify mock server files** (ledger-server.go, integration-server.go, etc.) — these are shared test infrastructure. If a nil pointer panic occurs because a mock func is nil, set up the mock expectation in the test BEFORE the action that triggers the call. For background processors, move mock setup before the action that creates data the processor picks up.
8. **NEVER set up catch-all mocks in `SetupSuite`** — multiple test suites run in parallel sharing the same DB. Catch-all mocks let one suite's background processor steal records from another suite. Set up mocks only in specific tests that need them. Use a suite helper method to avoid duplication, called explicitly per-test.
9. **NEVER call `wiremock.Reset()` (or any global mock reset) on a shared WireMock server** — see [WireMock: shared server, no global Reset](#wiremock-shared-server-no-global-reset) below.

## WireMock: shared server, no global Reset

WireMock runs as **one long-lived server process per port** (e.g. core mock `:8081`, integration mock `:8082`), started once for the whole `go test ./...` job. **Every test in every package is a client of the same server** — the stub registry is global mutable state *inside the server*, not inside your Go test. Go runs different **packages** in parallel (no `-p 1`), so suites in `tests/api/v1`, `tests/privateapi/v1`, `tests/service`, … all hit the same WireMock concurrently.

`wc.Reset()` in `go-wiremock` is `POST /__admin/mappings/reset` — it **wipes the ENTIRE server's stub registry** (and reloads only file-based mappings from `mappings/`). It does NOT delete "this test's stubs". So one suite's `Reset()` deletes the stubs another parallel suite just registered → that suite's request hits no stub → WireMock returns a plain-text `404 Not Found` / `500`.

Symptoms of this race (they **move between runs**, same root cause — the tell-tale sign of the shared-Reset bug):
- `[404]<provider> order http error: 404 Not Found` (file-based stub briefly gone during another suite's reset)
- `failed to parse core error response: invalid character 'N'/'R'` (parser choking on WireMock's plain-text `Not Found` / request-not-matched body where JSON was expected)
- Passes locally (packages effectively serialize) but fails in CI (packages run parallel).

**Rule: delete only your own stub, never reset the server.** Capture the `*StubRule` returned by `wiremock.Get(...)/Post(...)`, register with `StubFor(stub)`, and clean up with `DeleteStub(stub)` (deletes by the rule's auto-generated UUID). `NewStubRule` assigns the UUID at build time, so the handle is valid for deletion.

```go
// Bad — wipes the whole shared server; races with every parallel package
func (s *Suite) stubCoreProducts(externalID string, products []coreapiv1.ProductInfo) func() {
    wc := wiremock.NewClient(tests.TestCoreWireMockURL)
    err := wc.StubFor(wiremock.Get(wiremock.URLPathEqualTo("/api/v1/products")).
        WithQueryParam("externalID", wiremock.EqualTo(externalID)).
        WillReturnResponse(wiremock.NewResponse().WithStatus(200).WithJSONBody(products)))
    s.Require().NoError(err)
    return func() { s.Require().NoError(wc.Reset()) }   // ❌ global reset
}

// Good — capture the stub, delete only it
func (s *Suite) stubCoreProducts(externalID string, products []coreapiv1.ProductInfo) func() {
    wc := wiremock.NewClient(tests.TestCoreWireMockURL)
    stub := wiremock.Get(wiremock.URLPathEqualTo("/api/v1/products")).
        WithQueryParam("externalID", wiremock.EqualTo(externalID)).
        WillReturnResponse(wiremock.NewResponse().WithStatus(200).WithJSONBody(products))
    s.Require().NoError(wc.StubFor(stub))
    return func() { s.Require().NoError(wc.DeleteStub(stub)) }   // ✅ scoped delete
}
// call site: defer s.stubCoreProducts(externalID, products)()
```

Corollaries:
- **No `Reset()` in `SetupTest`/`SetupSuite` either.** If a suite re-stubbed a fixed path each test via `SetupTest` + `Reset()`, register the shared stub **once** in `SetupSuite` and remove it in `TearDownSuite` (`DeleteStub`); per-test stubs get a per-test `defer DeleteStub`.
- **Make stubs naturally non-colliding** — match on a unique key per test (unique `externalID`, `session_id`, cart UUID) so leftover stubs from other tests never satisfy your request and you never *need* a global reset.
- **Request-journal cleanup is the same** — if you assert call counts, scope with `DeleteRequestsByCriteria(matcher)` for your exact key, never `DeleteAllRequests()`.

## Workflow

### Step 1: Understand What to Test

Identify what needs testing:

**For new endpoints/features:**
- What is the endpoint/method being tested?
- What are the success scenarios?
- What are the error scenarios? (validation errors, not found, external service errors)
- What external dependencies need mocking?

**For existing code coverage:**
- What functionality is currently untested?
- What edge cases are missing?
- What error paths are uncovered?

### Step 2: Locate or Create the Test Suite

**Decision: Where does this test belong?**

Check if a test suite already exists for the feature:
- Look in `tests/{api-type}/{version}/` or project root test directory
- Pattern: `{feature}_test.go` (e.g., `order_test.go`, `refund_test.go`)

**If suite exists:**
- Add new test methods to the existing suite
- Jump to Step 4

**If suite doesn't exist:**
- Create a new test suite file
- Continue to Step 3

### Step 3: Create Test Suite Structure

**For detailed suite hierarchy patterns, see [suite-hierarchy.md](references/suite-hierarchy.md)**

Create a new feature test suite:

```go
package privateapiv1_test  // Note: Use {apitype}{version}_test pattern

import (
    "testing"
    "github.com/stretchr/testify/suite"
    // Import repositories and dependencies
)

type FeatureTestSuite struct {
    PrivateAPIV1TestSuite  // Embed the API-level suite

    // Add feature-specific repositories
    featureRepository     *repository.Feature
    featureTestRepository *repository_test.Feature
}

func TestFeatureTestSuite(t *testing.T) {
    suite.Run(t, &FeatureTestSuite{})
}

func (s *FeatureTestSuite) SetupSuite() {
    s.PrivateAPIV1TestSuite.SetupSuite()

    // Set up feature-specific dependencies
    db, err := db.Setup(s.Cfg.Postgres)
    s.Require().NoError(err)

    s.featureRepository = repository.NewFeature(db)
    s.featureTestRepository = repository_test.NewFeature(db)
}
```

**Key points:**
- Package name must have `_test` suffix (e.g., `privateapiv1_test`)
- Embed the API-level suite (e.g., `PrivateAPIV1TestSuite`)
- Always include test runner function: `func TestFeatureTestSuite(t *testing.T)`
- Call parent `SetupSuite()` first
- Initialize repositories needed for this feature

### Step 4: Write Test Methods

**For common test patterns and examples, see [common-patterns.md](references/common-patterns.md)**

For each scenario, create a test method following these patterns:

**Test naming:**
- `TestFeatureSuccess()` - for success cases
- `TestFeatureConditionFail()` - for specific failures
- `Test_WhenCondition_ExpectResult()` - for complex conditions

**Test structure (Arrange-Act-Assert):**

```go
func (s *FeatureTestSuite) TestFeatureSuccess() {
    // Arrange - Set up test data
    testAmount := int64(1000)
    testID := uuid.New().String()
    expectedResult := "expected_value"

    // Arrange - Configure mock behavior (if needed)
    s.mockSrv.MethodFunc = func(ctx context.Context, req *pkg.Request) (*pkg.Response, error) {
        // Validate incoming request
        s.Require().Equal(testAmount, req.Amount)
        s.Require().NotEmpty(req.ID)

        // Return mock response
        return &pkg.Response{
            Result: expectedResult,
        }, nil
    }

    // Act - Call the API
    res, err := s.apiClient.Feature(s.Ctx, &api.Request{
        ID:     testID,
        Amount: testAmount,
    })

    // Assert - Verify results
    s.Require().NoError(err)
    s.Require().NotNil(res)
    s.Require().Equal(expectedResult, res.Result)
}
```

**For error scenarios:**

```go
func (s *FeatureTestSuite) Test_WhenIDNotFound_Return404() {
    s.mockSrv.MethodFunc = nil  // Won't reach mock

    res, err := s.apiClient.Feature(s.Ctx, &api.Request{
        ID: "non-existent-id",
    })

    s.Require().ErrorContains(err, "[404]not found")
    s.Require().Nil(res)
}
```

### Step 4b: Table-Driven Tests (Alternative Pattern)

For testing multiple scenarios of the same functionality, use table-driven tests:

```go
func (s *FeatureTestSuite) TestFeatureVariousInputs() {
    tests := []struct {
        name    string  // Use descriptive names with spaces
        input   string
        amount  int64
        wantErr bool
        errMsg  string
    }{
        {name: "processes valid input successfully", input: "valid", amount: 1000, wantErr: false},
        {name: "returns error when amount is zero", input: "valid", amount: 0, wantErr: true, errMsg: "amount required"},
        {name: "returns error when input is empty", input: "", amount: 1000, wantErr: true, errMsg: "input required"},
    }

    for _, tt := range tests {
        s.Run(tt.name, func() {
            res, err := s.apiClient.Feature(s.Ctx, &api.Request{
                Input:  tt.input,
                Amount: tt.amount,
            })

            if tt.wantErr {
                s.Require().Error(err)
                s.Require().ErrorContains(err, tt.errMsg)
                s.Require().Nil(res)
            } else {
                s.Require().NoError(err)
                s.Require().NotNil(res)
            }
        })
    }
}
```

**Table test guidelines:**
- Don't use underscores in test names - use spaces
- Name should describe what the test does (arrange-act-assert style)
- **Don't use description field** - just use name
- Use `s.Run()` for subtests within suite methods

### Step 4c: Test Data Constants

Use constants instead of magic strings or numbers in tests:

```go
// Package-level constants (uppercase) - shared across tests
const (
    TestExternalID = "test_ext_id"
    TestProductID = "test_product"
    TestAmount = int64(1000)
)

// Function-level constants (lowercase) - used in single test
func (s *FeatureTestSuite) TestFeature() {
    const (
        testEmail = "test@example.com"
        testName  = "Test User"
    )

    // Use constants in test
    res, err := s.apiClient.Feature(s.Ctx, &api.Request{
        Email: testEmail,
        Name:  testName,
    })

    s.Require().NoError(err)
    s.Require().Equal(testEmail, res.Email)
}

// Exception - one-time setup values can be inline
func (s *FeatureTestSuite) SetupTest() {
    s.timeout = 30 // OK - used once for setup
}
```

**Guidelines:**
- If constants are used in current test only, use lowercase (package private)
- If used across multiple tests, use uppercase (package exported)
- No magic strings or numbers where you arrange then assert
- Always use constants for amounts, IDs, and other test values

### Step 5: Configure Mocks (if needed)

**For detailed mocking patterns, see [mocking.md](references/mocking.md)**

If the feature calls external services:

**Check if mock server exists:**
- Look in `tests/` directory for mock server files (e.g., `integration-server.go`, `ledger-server.go`)
- If it exists, configure its behavior in your test
- If not, create a new mock server

**Configure mock in test:**

```go
s.integrationSrv.OrderFunc = func(ctx context.Context, req *integrationv1.OrderRequest) (*integrationv1.BalanceResponse, error) {
    // Validate request parameters
    s.Require().Equal(testAmount, req.Amount)

    // Return mock response
    return &integrationv1.BalanceResponse{
        Balance: expectedBalance,
    }, nil
}
```

**Key patterns:**
- Set `MockSrv.MethodFunc = nil` when mock shouldn't be called
- Validate request parameters in mock functions
- Use boolean flags to track if mocks were called
- Extract and validate gRPC metadata when needed

### Step 6: Handle Test Data

**For detailed fixture and test data patterns, see [fixtures-and-test-data.md](references/fixtures-and-test-data.md)**

**CRITICAL RULE: Fixtures are for read-only tests ONLY**

**Use fixtures (static test data)** when:
- **Test only READS data** (no modifications)
- Testing filtering, fetching, or querying operations
- Data structure is complex with relationships
- Multiple tests need the same read-only data

**Use dynamic data (on-the-fly creation)** when:
- **Test modifies, updates, or deletes data** (NEVER use fixtures for this)
- Tests run in parallel (avoid conflicts)
- Testing creation/deletion operations
- Data is test-specific or unique
- Testing edge cases with specific values

**Why this matters:**
- Fixtures are shared across all tests
- Modifying fixture data breaks other tests
- Creates race conditions and flaky tests
- Violates test isolation principles

**Using fixtures (READ-ONLY tests):**
```go
const (
    TestUnlimitedSessionID = "8eacba81-c3d4-4680-8c56-90ac841a8ec6"  // From fixtures
)

// ✅ GOOD - Read-only test using fixture
func (s *FeatureTestSuite) TestGetFeature() {
    res, err := s.apiClient.GetFeature(s.Ctx, &api.Request{
        ID: TestUnlimitedSessionID,  // From db/fixtures - only reading
    })
    s.Require().NoError(err)
    s.Require().NotNil(res)
}

// ❌ BAD - Modifying fixture data
func (s *FeatureTestSuite) TestUpdateFeature() {
    res, err := s.apiClient.UpdateFeature(s.Ctx, &api.Request{
        ID:    TestUnlimitedSessionID,  // ❌ DON'T modify fixture data
        Field: "new_value",
    })
}
```

**Creating dynamic data with helpers (for tests that modify data):**
```go
// ✅ GOOD - Dynamic data for update test
func (s *FeatureTestSuite) TestUpdateFeature() {
    testUserID := uuid.NewString()
    sessionID := s.CreateNewSessionWithUserID(testUserID)
    defer s.DeleteSession(sessionID)  // Always clean up in defer

    // Now safe to modify
    res, err := s.apiClient.UpdateFeature(s.Ctx, &api.Request{
        ID:    sessionID,
        Field: "new_value",
    })
    s.Require().NoError(err)
}
```

**Creating dynamic data with test repositories:**
```go
func (s *FeatureTestSuite) TestDeleteFeature() {
    // Create unique test data
    testID := uuid.New()
    expectedTxID := fmt.Sprintf("test_%s", testID)

    testData := &model.SomeData{
        ID:      testID,
        ExtTxID: expectedTxID,
        Field:   "value",
    }
    err := s.repository.Insert(s.Ctx, testData)
    s.Require().NoError(err)

    // IMMEDIATELY defer cleanup - use TEST repository, delete ONLY this record
    defer func() {
        delErr := s.testRepository.DeleteByExtTxID(s.Ctx, expectedTxID)
        s.Require().NoError(delErr)
    }()

    // Test logic
    res, err := s.apiClient.DeleteFeature(s.Ctx, &api.Request{
        ID: testData.ID,
    })
    s.Require().NoError(err)
}
```

**CRITICAL cleanup rules:**
1. **Use test repositories** (e.g., `repository_test.Feature`) for delete operations
2. **Delete ONLY the specific record** created by this test - NEVER delete all records
3. **Use `defer` for cleanup - NEVER use `s.T().Cleanup()`** - defer runs immediately on function exit (even on panic), while `T().Cleanup()` may not run if process is killed
4. **Delete by specific ID/key** - the same identifier used when creating the record
5. **NEVER create "DeleteAll" or bulk delete methods** - they destroy other tests' data
6. **If cleanup fails, the test fails** - don't swallow cleanup errors

**WHY this matters - orphaned test data causes:**
- Background processors pick up stale records and call mocks that aren't configured
- Nil pointer panics when mock functions aren't set
- Flaky tests that pass/fail depending on database state
- Tests interfering with each other across runs

```go
// ❌ NEVER DO THIS - destroys other tests' data
func (r *TestRepo) DeleteAllPending(ctx context.Context) error {
    _, err := table.MyTable.DELETE().WHERE(table.MyTable.Status.EQ("pending")).Exec(tx)
    return err
}

// ✅ DO THIS - delete only the specific record you created
func (r *TestRepo) DeleteByExtTxID(ctx context.Context, txID string) error {
    _, err := table.MyTable.DELETE().WHERE(table.MyTable.ExtTxID.EQ(postgres.String(txID))).Exec(tx)
    return err
}
```

### Step 7: Verify Database Changes (when applicable)

For operations that modify database state:

```go
// Get state before
before, err := s.repository.GetByID(s.Ctx, id)
s.Require().NoError(err)

// Perform action
res, err := s.apiClient.Feature(s.Ctx, &api.Request{...})
s.Require().NoError(err)

// Get state after
after, err := s.repository.GetByID(s.Ctx, id)
s.Require().NoError(err)

// Verify changes
s.Require().Equal(before.Count+1, after.Count, "Count should increment")
```

### Step 8: Run Tests

**IMPORTANT: Always use VSCode MCP tasks to run tests** - never use command line directly.

**Standard Go test commands** (reference only, prefer VSCode MCP):

```bash
# Run all tests
go test ./...

# Run tests in specific package
go test -v ./tests/private-api/v1

# Run specific test suite or test method
go test -v ./tests/private-api/v1 -run TestOrderTestSuite
go test -v ./tests/private-api/v1 -run TestOrderTestSuite/TestRealSuccess

# Run with coverage
go test -v -cover ./...
```

**When tests fail:**
1. Check the logs first
2. If not enough logs, add more logs to understand what's happening
3. Don't guess what's going on - add logging to verify assumptions
4. Run the test again after adding logs

**After changing existing tests:**
- Always run the test to ensure it still works
- Don't commit test changes without verifying they pass
- If test changes require code changes, ask first before modifying code

## Coverage Guidelines

Ensure comprehensive coverage:

**For each endpoint, test:**
1. ✅ Success case (happy path)
2. ✅ Validation errors (invalid input)
3. ✅ Not found errors (missing resources)
4. ✅ External service errors (mock returning errors)
5. ✅ Authorization/permission errors (if applicable)
6. ✅ Edge cases specific to the feature

**For features with modes (demo vs real):**
- Test both modes separately
- Verify correct service is called (or not called)

**For financial operations:**
- Verify balance changes
- Verify database state changes
- Test rollback scenarios

## Quick Reference

**Common imports:**
```go
import (
    "context"
    "testing"

    "github.com/google/uuid"
    "github.com/stretchr/testify/suite"
    "google.golang.org/grpc/metadata"

    // Your project's packages
    "yourproject/tests"
    "yourproject/internal/domain"
)
```

**Common assertions:**
```go
s.Require().NoError(err)
s.Require().Equal(expected, actual)
s.Require().ErrorContains(err, "substring")
s.Require().NotNil(value)
s.Require().True(condition, "explanation")
```

**Async testing (CRITICAL - NEVER use time.Sleep):**
```go
// ✅ DO THIS - Use Eventually
s.Require().Eventually(func() bool {
    record, err := s.repository.FindByID(s.Ctx, id)
    if err != nil {
        return false
    }
    return record.Status == "completed"
}, tests.EventuallyWaitTime, tests.EventuallyPollInterval, "expected status to be completed")

// ❌ DON'T DO THIS - Never use time.Sleep
time.Sleep(10 * time.Millisecond)  // Flaky and unreliable
```

**Test data generation:**
```go
testID := uuid.New().String()
testUserID := uuid.NewString()
testAmount := int64(1000)
```

## Resources

### references/suite-hierarchy.md
Detailed guide to the test suite hierarchy (4 levels: IntegrationTestSuite → AppTestSuite → APITestSuite → FeatureTestSuite). Includes complete examples and package naming conventions for organizing tests.

### references/mocking.md
Complete guide to gRPC mocking with bufconn. Covers creating mock servers, registering mocks, configuring behavior, validating requests, and tracking mock calls.

### references/common-patterns.md
Common test patterns including test naming conventions, Arrange-Act-Assert structure, assertion examples, async testing with Eventually (NEVER use time.Sleep), test data management, cleanup patterns, and database verification.

### references/fixtures-and-test-data.md
Comprehensive guide to fixtures (static test data) vs dynamic test data, partition pruning considerations, goose migration management, and best practices for test data lifecycle.
