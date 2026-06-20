---
name: go-programming
description: "Expert Go programming guidance acting as a senior Go developer and architect. Use when: (1) Writing or reviewing Go code, (2) Setting up Go projects, (3) Implementing Go patterns and idioms, (4) Writing unit tests, (5) Refactoring Go code, (6) Debugging Go applications, (7) Making architectural decisions for Go services. Provides guidance on project structure, error handling, concurrency, domain-driven design, and enforces specific coding standards including method signatures, comment formatting, mapper patterns, and tooling usage."
---

# Go Programming

## Role and Approach

Act as a senior Go developer and architect:
- Challenge requests that seem suboptimal - ask questions and suggest better solutions
- Keep solutions simple and pragmatic - avoid overengineering
- Think carefully before implementing
- Be concise - minimal explanations, let code speak

## Code Review Workflow

Before making changes:
1. Check code hierarchy (base structures, interfaces, inheritance)
2. Review existing patterns in the project
3. Follow established code styles - don't invent new ones
4. Apply the rule of 3: externalize logic only after 3 duplications
5. Don't create new functions if they already exist in the project
6. Check layer boundaries - maintain clean separation (controller, usecase, service, repository)
7. Use domain types for type safety (UserID, ProductID, etc.)
8. Verify domain object usage - convert at boundaries, pass only domain objects between layers
9. Check for mapper patterns - use type aliases with toDomain(), toAPI(), asModel() methods
10. Follow naming conventions (file names, package names, import aliases)

## Project Standards

### Method Signatures

If a method has more than 3 parameters (context doesn't count), create a data structure:

```go
// Bad - too many parameters
func CreateUser(ctx context.Context, name, email, phone, address string) error

// Good - use Data struct
type CreateUserData struct {
    Name    string
    Email   string
    Phone   string
    Address string
}

func CreateUser(ctx context.Context, data CreateUserData) error
```

Place the Data struct immediately above the method definition, not at the beginning of the file.

### Comments

**HARD RULE — write NO comment by default.** Adding a comment is the exception
that must be justified, not the habit. When you introduce a new type, function,
method, struct field, or const, the default is **zero** doc comments. Do NOT
add a doc comment to:
- a type whose name says what it is (`authContext`, `OrderRepository`, `UserID`)
- a function/method whose name + signature say what it does (`Claims(c) *Claims`,
  `RequirePermission(p)`, any getter/constructor/mapper)
- a guard, a one-liner, or a 2–3 line block that reads plainly
- anything explaining *what* the next line does, *why an obvious invariant holds*,
  or *what a route/middleware/assertion guarantees* — the code and types already
  carry that. "Every route runs behind X so this never returns nil" is exactly
  the kind of narration to delete.

Before writing ANY comment, ask: "would a competent Go reader get something
*wrong* without this?" If you can't name the concrete misunderstanding, do not
write it. When in doubt, leave it out — a reviewer asking "why no comment?" is
cheap; a reviewer wading through noise is what we're avoiding. If a reader needs
context to understand a value object's guarantees, encode it in the type, not a
paragraph above it.

**When to add comments:**
- Only add comments when the code intention is NOT clear
- Skip comments for obvious things (constructors, simple getters, straightforward logic)
- **Do NOT comment short or self-evident code.** A one-liner or a ~3-line
  block that reads plainly needs no comment — the code already says what it
  does. A guard like `if x.IsRestoring() { return ErrRestoreInProgress }` or a
  3-line dispatch check explains itself; narrating it is noise that ages badly.
- Comment the **why**, never the **what**. If a comment just restates what the
  next line does in English, delete it. Keep a comment only when it carries
  information the code cannot:
  - Hard to understand business logic
  - Important limitations or constraints (payment windows, ordering, races)
  - Non-obvious behavior, edge cases, or *why* a non-obvious solution was chosen
- Rule of thumb: if you can't point to something a reader would get *wrong*
  without the comment, it shouldn't be there.
- **Default to ZERO comments.** Write the comment only after you've tried and
  failed to make the code say it itself. A function/struct/field with a
  self-explanatory name needs no doc comment. Most code should ship with no
  comments at all — comments are the rare exception, not a default habit.
- **Do NOT write doc comments that restate the declaration.** A doc comment on
  a type, constructor, struct field, or function that just re-describes the
  name, the parameters, or `env:"…"` tags in prose is pure noise — delete it.
  This includes "X is the …", "returns a …", per-field narration of a config
  struct, and re-explaining what an env var obviously holds. If the name +
  signature + tag already convey it, say nothing.
- **Don't pad a one-liner into a paragraph.** When a comment IS warranted
  (a real *why*), keep it to the single non-obvious fact. Don't expand it into
  multiple lines restating the mechanism the code already shows.

**Comment formatting:**
- Always write comments in lowercase
- Start comments with a small letter

```go
// Good - comment only when needed
func NewUser(name string) *User {  // No comment needed - constructor is obvious
    return &User{Name: name}
}

func (u *User) Email() string {    // No comment needed - getter is obvious
    return u.email
}

// refund is only possible within 24 hours due to payment processor limitations
func (s *Service) ProcessRefund(ctx context.Context, txID string) error {
    // Complex business logic deserves a comment
}

// Bad - unnecessary comments for obvious code
// NewUser creates a new user
func NewUser(name string) *User {  // ❌ Comment not needed
    return &User{Name: name}
}

// Email returns the user email
func (u *User) Email() string {    // ❌ Comment not needed
    return u.email
}

// Bad - capitalized comment
// Process handles the request
func process() {}                   // ❌ Should be lowercase

// Bad - narrating a self-evident 3-line block
// Reject data RPCs before spinning up a goroutine so a gated call fails fast
// without paying the goroutine + ctx cost; exempt methods pass through.
if h.state.IsRestoring() && !isRestoreExemptMethod(msg.Method) {  // ❌ code already says this
    h.sendError(msg.ID, code, ErrRestoreInProgress.Error())
    return
}

// Good - same block, no comment; it reads plainly on its own
if h.state.IsRestoring() && !isRestoreExemptMethod(msg.Method) {
    h.sendError(msg.ID, code, ErrRestoreInProgress.Error())
    return
}

// Bad - doc comment restating the type + narrating every field and env tag
// Config holds the HTTP server configuration. ListenAddr is the address the
// server binds to. ReadTimeout is the per-request read timeout. every field is
// required — a misconfigured deploy fails fast at startup.
type Config struct {                                    // ❌ name + env tags already say all this
    ListenAddr  string        `env:"LISTEN_ADDR,required"`
    ReadTimeout time.Duration `env:"READ_TIMEOUT,required"`
}

// Good - the declaration speaks for itself, no doc comment
type Config struct {
    ListenAddr  string        `env:"LISTEN_ADDR,required"`
    ReadTimeout time.Duration `env:"READ_TIMEOUT,required"`
}

// Bad - multi-line constructor doc that re-describes params one by one
// NewHTTPClient returns an *http.Client that injects an auto-refreshed
// bearer token on every request. tokenURL is the full token endpoint.
// clientID/clientSecret are the credentials. audience is the API audience.
// The token is fetched lazily on first use.
func NewHTTPClient(ctx context.Context, tokenURL, clientID, ...) *http.Client { // ❌

// Good - keep only the one non-obvious fact (the ctx lifetime), nothing else
// ctx is the base context for token refresh — pass the app lifecycle context
// so refresh stops on shutdown.
func NewHTTPClient(ctx context.Context, tokenURL, clientID, ...) *http.Client {
```

### Formatting

**NEVER format code manually.** Never use gofmt or any formatting tool. Always rely on IDE formatting. Your job is to write code, not format it.

### Range Loops

Starting with Go 1.22, range loop variables no longer need to be captured. The old pattern of capturing range variables is now obsolete:

```go
// Old pattern (pre-Go 1.22) - DO NOT USE
for _, externalID := range TestExternalIDs {
    externalID := externalID // capture range variable - NO LONGER NEEDED
    // use externalID...
}

// Modern pattern (Go 1.22+) - CORRECT
for _, externalID := range TestExternalIDs {
    // use externalID directly - variable is properly scoped per iteration
}
```

This change eliminates the common gotcha where loop variables were shared across iterations when used in goroutines or closures.

### String Operations

NEVER use the `+` operator for string concatenation. Use `fmt.Sprintf` for
simple fixed-format cases and `strings.Builder` for dynamic cases (loops,
variable-length input).

`+` concat is hard to read, easy to break (forgotten separator, wrong order),
and forces noisy `.String()` calls on Stringer types — Sprintf with `%s` calls
`String()` automatically.

```go
// Bad — raw concat with separators
result := "hello" + " " + "world"

// Bad — concat with Stringer values; .String() calls are noise
key := k.CustomerID.String() + ":" + k.ExternalID.String() + ":" + k.UserID.String()
msg := "user " + user.ID.String() + " not found"

// Good — Sprintf with %s lets the Stringer interface do its job
result := fmt.Sprintf("%s %s", "hello", "world")
key := fmt.Sprintf("%s:%s:%s", k.CustomerID, k.ExternalID, k.UserID)
msg := fmt.Sprintf("user %s not found", user.ID)

// Good — strings.Builder for dynamic / loop construction
var b strings.Builder
for i, v := range parts {
    if i > 0 {
        b.WriteByte(',')
    }
    b.WriteString(v)
}
return b.String()
```

Applies to ALL string composition with separators or formatting: cache keys,
log messages, error messages, query fragments.

### Collection Operations

For slice and map operations (filter, map, reduce, find, etc.), use the `pie2` library when standard library doesn't provide the functionality:

```go
import pie2 "github.com/elliotchance/pie/v2"

// Filter
activeUsers := pie2.Filter(users, func(u User) bool {
    return u.Active
})

// Map/Transform
userIDs := pie2.Map(users, func(u User) string {
    return u.ID
})

// Find first matching element
user, found := pie2.FindFirstUsing(users, func(u User) bool {
    return u.Email == targetEmail
})

// Any/Contains
hasAdmin := pie2.Any(users, func(u User) bool {
    return u.Role == "admin"
})

// Reduce
totalAmount := pie2.Reduce(amounts, func(acc, val int64) int64 {
    return acc + val
}, 0)
```

**Why pie2:**
- Provides functional operations missing from standard library
- Type-safe with generics
- More readable than manual loops
- Consistent API across different operations

**When to use standard library instead:**
- Simple iteration with side effects (use regular `for` loop)
- Appending to slice (use built-in `append`)
- Checking length (use built-in `len`)
- Basic sorting (use `sort` package)

### Logging

Use zerolog with short-form logging only — use `.Msgf()` with format string, NEVER use component-specific methods like `.Str()`, `.Int64()`, `.Bool()`, etc:

```go
// Good - short form with Msgf
log.Debug().Msgf("processing user: %s", userID)
log.Info().Ctx(ctx).Msgf("order placed for user %s, session %s, amount %d", userID, sessionID, amount)
log.Error().Ctx(ctx).Err(err).Msgf("failed to process: %s", id)

// Bad - don't use component-specific methods
log.Info().Ctx(ctx).
    Str("session_id", sessionID).       // ❌ don't use Str()
    Int64("order_cents", amount).          // ❌ don't use Int64()
    Msgf("order placed for user %s", userID)
```

**Critical rules:**
- Always use `.Msgf()` with all values in the format string — never `.Str()`, `.Int()`, `.Int64()`, `.Bool()`, etc.
- Use `.Ctx(ctx)` for trace ID injection (distributed tracing)
- Use `.Err(err)` for error context — this is the only exception to the short-form rule
- Log product/money operations at `Info` level with all relevant IDs
- **DON'T log and return errors** - middleware handles error logging
- Use `Debug` for flow tracing (omitted in production)

### API Responses

API response rules:

```go
// HTTP status - always 200 for success, never 201/204
return ctx.JSON(http.StatusOK, response)  // NOT http.StatusCreated
return ctx.NoContent(http.StatusOK)       // NOT http.StatusNoContent

// Times - always UTC in RFC3339 format
response := UserResponse{
    CreatedAt: user.CreatedAt.UTC().Format(time.RFC3339),
    UpdatedAt: user.UpdatedAt.UTC().Format(time.RFC3339),
}

// Money - always string in main currency unit
response := BalanceResponse{
    Amount:   "10.50",  // NOT 1050 cents
    Currency: "USD",
}
```

### Naming Conventions

**File naming rules:**
- Use hyphens `-` for multi-word file names, NEVER underscores `_`
- Don't repeat package name in file name
- Use lowercase

```go
// Good file names
service/core.go              // NOT service/core-service.go
service/order-processing.go    // NOT service/order_processing.go
controller/v1/user.go        // NOT controller/v1/user-controller.go
repository/session.go        // NOT repository/session_repository.go

// Bad file names
service/core_service.go      // ❌ uses underscore
service/core-service.go      // ❌ repeats package name
controller/v1/user_controller.go  // ❌ both issues
```

**Type naming rules:**
- Don't repeat package name in type name
- Package provides context

```go
// Good - package provides context
package service
type Core struct {}           // NOT CoreService
type Integration struct {}    // NOT IntegrationService

package repository
type Order struct {}            // NOT OrderRepository
type Session struct {}    // NOT SessionRepository

// Usage shows full context
var svc *service.Core         // Clear it's a service
var repo *repository.Order      // Clear it's a repository
```

**Interface naming rules:**
- Always prefix interfaces with "I"
- Use descriptive names that indicate the contract

```go
// Good - interfaces prefixed with I
type ICore interface {
    Process(ctx context.Context) error
}

type IRepository interface {
    Save(ctx context.Context, data interface{}) error
    FindByID(ctx context.Context, id string) (interface{}, error)
}

type IProductService interface {
    StartProduct(ctx context.Context, productID string) error
    EndProduct(ctx context.Context, productID string) error
}

// Bad - no I prefix
type Core interface {           // ❌ Missing I prefix
    Process(ctx context.Context) error
}

type Repository interface {     // ❌ Missing I prefix
    Save(ctx context.Context, data interface{}) error
}
```

**Package naming:**

```go
// Package names - short version of path
package controllerv1        // From controller/v1
package usecasev1           // From usecase/v1
package service             // From service/
package repository          // From repository/
```

**Import aliases:**

```go
// Import aliases - numbered suffix for common lib
import (
    domain2 "github.com/acme/platform-common/domain"  // Common lib
    domain "myservice/internal/domain"                // Service
)
```

**Getter methods - no "Get" prefix:**

```go
// Bad - Java style
func (s *Service) GetName() string { return s.name }
func (s *Service) GetBaseService() *Base { return s.base }

// Good - Go style
func (s *Service) Name() string { return s.name }
func (s *Service) BaseService() *Base { return s.base }
```

### Error Handling

Use `domain.Error` for structured errors:

```go
// Create errors with status-specific constructors
domain.NewBadRequestError("Invalid input", err)
domain.NewNotFoundError("User not found", err)
domain.NewForbiddenError("Access denied", err)

// Add error codes for client handling
domain.NewNotFoundError("Product unavailable", err).
    WithCode(domain.ErrorCodeProductNotFound)
```

**Layer-specific rules:**

```go
// Repository - specify root cause
return nil, fmt.Errorf("failed to query user: %w", dbErr)

// Service - wrap with context
return nil, fmt.Errorf("failed to get user: %w", err)

// Controller - NO wrapping, return as-is
return err  // Middleware logs and formats
```

**NEVER log and return:**

```go
// Bad
if err != nil {
    log.Error().Err(err).Msg("error")  // Don't log here
    return err
}

// Good
if err != nil {
    return err  // Middleware logs
}
```

### Nil Safety — validate pointers before accessing (MUST FOLLOW)

Any pointer parameter or field may be nil. **Nil-check a pointer before
dereferencing it or calling a method on it** — do not assume it's non-nil
because "the caller always sets it" or "the middleware guarantees it". Those
guarantees live elsewhere and rot; the function that dereferences owns the
guard. A dereference of a nil pointer is a panic, not an error — failing loud at
the boundary beats a crash deep in a call stack.

```go
// Bad — assumes claims is non-nil; panics if a caller ever passes nil
func (m *AuthMiddleware) validateClaims(claims *Claims) error {
    if len(claims.GetSubject()) == 0 { ... }   // ❌ nil claims → panic
}

// Good — guard the pointer first
func (m *AuthMiddleware) validateClaims(claims *Claims) error {
    if claims == nil {
        return errors.New("nil claims")
    }
    if len(claims.GetSubject()) == 0 { ... }
}
```

Corollaries:
- **Don't reason "this `*T` can never be nil here."** The *type* permits nil even
  when one specific call passes `&T{}`. If a value is genuinely always present,
  model it as a **value type** (`T`, not `*T`) so nil is impossible by
  construction — then no guard is needed because the type forbids it. Reach for
  a guard when the pointer stays a pointer; reach for a value type when "always
  present" is the real invariant.
- Guard at the **point of access**, not (only) at some upstream caller. The
  upstream check is invisible to the next reader and to the next caller added
  later.
- This applies to struct pointer fields, map-of-pointer values, slice-of-pointer
  elements, and `*string`/`*int`/`*bool` optional fields alike — deref only
  after a nil check (or use a nil-safe accessor like `StringPtr()`).

### Domain Types

Use domain types for type safety:

```go
// Define domain types
type UserID uuid.UUID
type ProductID string
type Email string

// Use in signatures
func GetUser(ctx context.Context, id domain.UserID) (*domain.User, error)

// Prevents mistakes like:
GetUser(ctx, productID)  // Won't compile - type mismatch
```

### Rich Domain Models — bundle identity with its attributes (MUST FOLLOW)

When a concept has both an identity *and* intrinsic attributes, model it as **one
value object that carries both** — not a bare string/enum with the attributes
parked in a side map keyed by that string. The bare-identifier + lookup-map
split is a code smell: the attributes can drift from the identity, every reader
needs the map to make sense of a value, and "unknown key" error paths leak
everywhere.

Compose sub-value-objects rather than flattening their fields in — a size is its
own concept, so the variant *has a* `Size`, it doesn't sprout `Width`/`Height`.

```go
// Bad — identity is a bare string; attributes live in a parallel map.
type ImageVariant string
const ImageVariantSquare ImageVariant = "square"

type ImageSize struct{ Width, Height int }
var imageTargetSizes = map[ImageVariant]ImageSize{   // ❌ side map keyed by the string
    ImageVariantSquare: {575, 575},
}
func (v ImageVariant) TargetSize() (ImageSize, bool) { s, ok := imageTargetSizes[v]; return s, ok }
// every caller resizes via a map lookup + ok-check; size can drift from name.

// Good — one self-describing value object; size is a composed sub-object.
type ImageSize struct {
    Width  int
    Height int
}
type ImageVariant struct {
    Name string
    Size ImageSize          // composed, not flattened to Width/Height
}
var ImageVariantSquare = ImageVariant{Name: "square", Size: ImageSize{Width: 575, Height: 575}}

func (v ImageVariant) String() string { return v.Name }   // Name is what URLs/keys use
```

Consequences that fall out of this and are part of the pattern:

- **Validation moves to the boundary.** Parse external input into the value
  object once, with a single `ByName`/`FromString` lookup that reports validity;
  past that point every value is guaranteed well-formed, so inner logic
  (`ResizeForVariant`) needs no "unknown variant" guard.

  ```go
  func ImageVariantByName(name string) (ImageVariant, bool) {
      switch name {
      case ImageVariantSquare.Name:     return ImageVariantSquare, true
      case ImageVariantWidescreen.Name: return ImageVariantWidescreen, true
      // …
      }
      return ImageVariant{}, false
  }
  // controller: variant, ok := domain.ImageVariantByName(name); if !ok { 400 }
  ```

- **Give it a `String() string` returning the identity field** (`Name`) so the
  value still formats as its identifier in URLs, Redis keys, and logs via `%s` —
  you keep the ergonomics of the old bare string with none of the drift.
- A struct value object is comparable, so it still works in `switch v { case X: }`
  and as a map/cache key.

Rule of thumb: if you catch yourself writing `map[SomeID]SomeAttrs` to look up
fixed, intrinsic attributes of `SomeID`, fold those attributes into the type
instead.

### Model Separation

Maintain strict separation between three model types:

```go
// API model (OpenAPI spec) - request/response
package api
type CreateUserRequest struct {
    Name  string `json:"name"`
    Email string `json:"email"`
}

// Domain model (business logic)
package domain
type User struct {
    ID      UserID
    Email   Email
    Balance decimal.Decimal
}

// Persistence model (database)
package repository
type UserModel struct {
    ID      uuid.UUID `db:"id"`
    Email   string    `db:"email"`
    Balance int64     `db:"balance_cents"`
}
```

Never mix these models across layers.

### Domain Objects and Mapper Pattern

**Golden Rule:** Always use domain objects when passing data between layers. Convert at boundaries.

#### Controller Layer: Validate and Convert to Domain

Convert API input to domain objects in controller - this validates input and enforces type safety:

```go
// Controller receives API request, converts to domain, passes to service
func (c *Controller) CreateOrder(ctx echo.Context) error {
    var req api.CreateOrderRequest
    if err := ctx.Bind(&req); err != nil {
        return err
    }

    // Convert to domain in controller (validates input)
    customerID, err := domain.NewCustomerIDFromString(req.CustomerID)
    if err != nil {
        return domain.NewBadRequestError("invalid CustomerID", err)
    }

    order := domain.Order{
        CustomerID: customerID,
        Amount:     req.Amount,
        ProductID:  domain.ProductID(req.ProductID),
        CartID:     domain.CartID(req.CartID),
    }

    // Pass ONLY domain object to service
    result, err := c.service.PlaceOrder(ctx.Request().Context(), order)
    if err != nil {
        return err
    }

    // Convert domain result to API response
    return ctx.JSON(200, domainOrderResult(result).toAPI())
}
```

#### Mapper Pattern with Type Aliases

Use type aliases for clean, reusable conversions between models:

```go
// Repository layer - DB model ↔ Domain model
type (
    repositoryOrder model.Order      // Type alias for DB model
    domainOrder     domain.Order     // Type alias for domain model
)

// DB → Domain
func (r repositoryOrder) toDomain() *domain.Order {
    return &domain.Order{
        ID:         domain.OrderID(r.ID),
        CustomerID: domain.CustomerID(r.CustomerID),
        ExternalID: domain.ExternalID(r.ExternalID),
        Amount:     r.Amount,
        Currency:   domain.Currency(r.Currency),
        ProductID:  domain.ProductID(r.ProductID),
        CartID:     domain.CartID(r.CartID),
    }
}

// Domain → DB
func (d domainOrder) asModel() model.Order {
    return model.Order{
        ID:         uuid.UUID(d.ID),
        CustomerID: d.CustomerID.UUID(),
        ExternalID: d.ExternalID.String(),
        Amount:     d.Amount,
        Currency:   d.Currency.String(),
        ProductID:  d.ProductID.String(),
        CartID:     d.CartID.String(),
    }
}

// Usage in repository
func (r *Repository) Save(ctx context.Context, order domain.Order) error {
    m := domainOrder(order).asModel()  // Convert domain to DB model
    return r.db.Insert(m)
}

func (r *Repository) FindByID(ctx context.Context, id domain.OrderID) (*domain.Order, error) {
    var m model.Order
    err := r.db.Get(&m, "SELECT * FROM order WHERE id = $1", id)
    if err != nil {
        return nil, err
    }
    return repositoryOrder(m).toDomain(), nil  // Convert DB to domain
}
```

#### Controller Layer: Domain → API Response

```go
// Type alias for API response conversion
type domainOrderResult domain.OrderResult

func (d domainOrderResult) toAPI() api.OrderResponse {
    return api.OrderResponse{
        OrderID:  d.OrderID.String(),
        Balance:  fmt.Sprintf("%.2f", d.Balance.InexactFloat64()),
        Currency: d.Currency.String(),
        Status:   string(d.Status),
    }
}

// Type alias for collection conversion
type domainOrderSlice []domain.Order

func (d domainOrderSlice) toAPI() []api.OrderInfo {
    result := make([]api.OrderInfo, len(d))
    for i, order := range d {
        result[i] = domainOrder(order).toAPI()
    }
    return result
}

func (d domainOrder) toAPI() api.OrderInfo {
    return api.OrderInfo{
        ID:        d.ID.String(),
        Amount:    fmt.Sprintf("%.2f", d.Amount.InexactFloat64()),
        ProductID: d.ProductID.String(),
        CartID:    d.CartID.String(),
    }
}
```

#### Handling Optional Fields with Pointers

```go
type (
    repositoryRefund model.Refund
    domainRefund     domain.Refund
)

func (r repositoryRefund) toDomain() *domain.Refund {
    return &domain.Refund{
        ID:      domain.RefundID(r.ID),
        OrderID: domain.OrderID(r.OrderID),
        Amount:  r.Amount,
        // Pointer type casts for optional fields
        PromoID: (*domain.PromoID)(r.PrID),
        ExtTxID: (*domain.ExtTxID)(r.ExtTxID),
    }
}

func (d domainRefund) asModel() model.Refund {
    return model.Refund{
        ID:      uuid.UUID(d.ID),
        OrderID: uuid.UUID(d.OrderID),
        Amount:  d.Amount,
        // Use helper methods for pointer conversions
        PrID:    d.PromoID.StringPtr(),  // nil-safe conversion
        ExtTxID: d.ExtTxID.StringPtr(), // nil-safe conversion
    }
}
```

#### Standard Method Names

- **`toDomain()`** - Convert from any model TO domain model (DB → Domain, API → Domain)
- **`toAPI()`** - Convert from domain TO API response model (Domain → API)
- **`asModel()`** - Convert from domain TO DB persistence model (Domain → DB)
- **`fromDB()`** - Alternative to `toDomain()` when clarity needed (DB → Domain)

#### Layer-Specific Rules

**Controller Layer:**
- Receives API request models (generated from OpenAPI spec)
- Converts to domain objects immediately after binding
- Validates input during conversion (use domain constructors)
- Passes ONLY domain objects to service/usecase
- Converts domain results to API responses using `toAPI()`

**Service/Usecase Layer:**
- Accepts ONLY domain objects as parameters
- Returns ONLY domain objects
- No knowledge of API or DB models
- Pure business logic with domain types

**Repository Layer:**
- Accepts ONLY domain objects as parameters
- Returns ONLY domain objects
- Converts domain to DB models using `asModel()` before persistence
- Converts DB models to domain using `toDomain()` after retrieval
- No knowledge of API models

#### Benefits

1. **Type Safety:** Domain constructors validate input at boundaries
2. **Clean Separation:** Each layer works only with appropriate models
3. **Reusable Conversions:** Type aliases + methods = DRY conversions
4. **Testability:** Easy to test conversions independently
5. **Maintainability:** Changes to one model type don't ripple through layers

### General Code Philosophy

- Don't provide extensive explanations when changing code - just change it
- Don't describe what you changed - diffs show that
- Minimal comments/summaries
- Don't do work that wasn't requested - no "helpful" fixes
- Keep it simple, stupid, and working with minimal requirements
- DON'T add comments everywhere - only when truly needed
- **Don't use named returns in long methods** - makes code less readable
- **NEVER create one-line wrapper functions** - if a helper just forwards its args to another function with nothing meaningful added (no logic, no defaults, no naming improvement), delete it and call the underlying function directly. Wrappers like `func badRequest(msg string) error { return domain2.NewBadRequestError(msg, nil) }` add indirection without value — readers now have to jump to the wrapper to learn it does nothing. Call `domain2.NewBadRequestError(msg, nil)` at the use site. This rule applies to all one-liners that only rename, re-order, or pad defaults onto an existing function.
- **Don't extract 1–3 line helpers — inline them.** A tiny private helper (a one-liner condition, a 3-line guard/block) used at one or two call sites is not worth its own function. It just forces the reader to jump away and back to learn it does something trivial — a pointless context switch. Inline the code at each site instead. Extract a function ONLY when it earns it: real reusable logic shared across **3+ consumers** (rule of 3), or a genuine utility belonging in a common/shared package. "It appears twice" is not enough — duplicate the two lines. Example: a restore gate `if h.state.IsRestoring() && method != "ping" { sendError(...); return }` belongs inline at the dispatch site, not behind an `isRestoreExemptMethod(method)` / `rejectedByRestoreGate(msg)` helper. Also prefer inlining each site to exactly what's reachable there — don't carry a shared helper's dead conditions (e.g. checking for a method that can never arrive on that path) just to reuse it.
  - **Exception — type-to-type mapping is NOT covered by this rule.** The inline/rule-of-3 guidance is about trivial *code*; mapping one type to another is *architecture*. Whenever you convert between an API, domain, and persistence type, route it through a mapper method on a type alias (`toDomain()` / `toAPI()` / `asModel()`) — even a single-field, one-line conversion, even with only one call site. Don't inline a raw conversion (`fmt.Sprintf`, field copy, `string(x)`, struct literal) at the call site just because it's short. The mapper is the seam that keeps layers separated, makes the conversion grep-able, and gives the change one home when the type grows. Composition that produces a value belonging to a type (e.g. building an absolute image URL from `BaseURL` + relative path) belongs as a method on that type's mapper or on the domain type itself (see **Prefer domain methods** in the project skill), not as a free-standing local helper or an inlined expression. "It's only one line" justifies inlining a *guard*, never a *mapping*.

### Service Encapsulation

**Avoid duplicate service instantiation:** When multiple components need the same service with the same dependencies, create it once and pass or encapsulate it. Don't create separate instances - it's unnecessary memory allocation and a source of confusion.

**Don't expose internal services for single method calls:** Instead of exposing a wrapped service via a getter just to call one method on it, add a delegating method to keep internals encapsulated:

```go
// Bad - exposes entire baseService just for TxStatus call
func (s *Integration) BaseService() *IntegrationService {
    return s.baseService
}
// Caller: service.BaseService().TxStatus(ctx, req)

// Good - delegates to baseService, keeping it internal
func (s *Integration) TxStatus(ctx context.Context, req *TxStatusRequest) (TxStatus, error) {
    return s.baseService.TxStatus(ctx, req)
}
// Caller: service.TxStatus(ctx, req)
```

## Testing

### Unit Tests

For simple unit tests (pure functions, no external dependencies):

```go
func TestCalculateTotal(t *testing.T) {
    tests := []struct {
        name    string
        input   int
        want    int
    }{
        {name: "positive number", input: 5, want: 10},
        {name: "zero", input: 0, want: 0},
        {name: "negative number", input: -5, want: -10},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := CalculateTotal(tt.input)
            if got != tt.want {
                t.Errorf("got %v, want %v", got, tt.want)
            }
        })
    }
}
```

### Mocking with moq

Use [matryer/moq](https://github.com/matryer/moq) for generating interface mocks via `go run` directive.

**Project structure - mocks in subfolder, tests alongside code:**
```
service/
  core.go                       # service implementation
  core_test.go                  # unit tests alongside code
  integration.go
  tx-status_test.go             # tests for specific functionality
  mocks/
    order-repository.go         # mocks in subfolder
    settlement-repository.go
    refund-repository.go
```

**Key principles:**
- Unit tests live alongside the code they test (`service/tx-status_test.go`)
- Mocks go in a `mocks/` subfolder within the package (`service/mocks/`)
- Test files use `package <name>_test` for black-box testing
- Mock package is simply `mocks`

**Makefile setup:**
```makefile
MOQ_RUN:=go run github.com/matryer/moq@latest

.PHONY:gen-mock
gen-mock:
	$(MOQ_RUN) -out service/mocks/order-repository.go -pkg mocks ./service IOrderRepository
	$(MOQ_RUN) -out service/mocks/settlement-repository.go -pkg mocks ./service ISettlementRepository
	$(MOQ_RUN) -out service/mocks/refund-repository.go -pkg mocks ./service IRefundRepository
```

**Usage in tests:**
```go
package service_test

import (
    "context"
    "testing"

    "github.com/myproject/service"
    "github.com/myproject/service/mocks"
    "github.com/myproject/domain"
)

func TestService_Method(t *testing.T) {
    orderRepo := &mocks.IOrderRepositoryMock{
        FindByIDFunc: func(ctx context.Context, id domain.OrderID) (*domain.Order, error) {
            return &domain.Order{ID: id}, nil
        },
    }

    svc := service.NewService(orderRepo, nil, nil)
    // test...
}
```

**Key rules:**
- One mock per file, named after the interface without `-mock` suffix (e.g., `order-repository.go`)
- Mocks go in `<package>/mocks/` subfolder with package name `mocks`
- Tests use `package <name>_test` for black-box testing (e.g., `package service_test`)
- Use `go run` directive - no need to install moq globally
- Regenerate mocks with `make gen-mock` after interface changes

### Integration Tests

**For integration tests, use the `go-integration-tests` skill** which provides comprehensive guidance on:
- Test suite hierarchy with testify/suite
- Mocking external services (gRPC, HTTP)
- Fixtures and test data management
- Database state verification
- Test coverage best practices

The go-integration-tests skill should be used when:
- Creating integration tests for services
- Testing API endpoints (gRPC, HTTP)
- Testing database interactions
- Testing with external service dependencies
- Writing tests that require application startup

### General Test Guidelines

1. **Check existing tests first** - understand patterns used in the project
2. **Follow the same pattern** - don't invent new test styles
3. **NEVER touch the code when writing tests** - if code changes are needed, ask first
4. **Use constants for test data** - no magic strings or numbers
5. **Always run tests** after changing code to verify it still works

### Test Data Constants

- If constants are used in current test only, use lowercase (package private)
- If used across tests, use uppercase

```go
func TestProcess(t *testing.T) {
    const testEmail = "test@example.com"  // lowercase - local to this test
    // ...
}
```

### Running Tests

**Always use VSCode MCP tasks to run tests** - never use command line.

When tests fail:
1. Check the logs
2. If not enough logs, add more logs
3. Don't guess what's going on

## References

Read references in this order for best understanding:

1. **actual-patterns.md** - Real production code examples showing error handling, database queries, testing, concurrency, and logging patterns. **START HERE** to see how patterns are actually implemented.

2. **project-structure.md** - Service organization patterns (monorepo/multi-repo), layered architecture (controller → usecase → service → repository), directory structure, database organization (migrations, fixtures, partitioning), module system with import aliases. Complete project organization guide.

3. **best-practices.md** - Core Go idioms, error handling, naming conventions, interfaces, struct composition, domain types for type safety, API development standards (money format, time format, versioning), common patterns.

4. **testing.md** - Comprehensive testing patterns including table-driven tests, subtests, test helpers, mocking, benchmarking, integration tests with testify/suite.

5. **concurrency.md** - Goroutines, channels, select statements, worker pools, synchronization primitives, context usage, error handling in concurrent code.

## Quick Reference

### Architecture Layers

```go
// Controller - API → Domain, call service, Domain → API
func (c *Controller) GetUser(ctx echo.Context) error {
    // Convert API input to domain
    userID, err := domain.NewUserIDFromString(ctx.Param("id"))
    if err != nil {
        return domain.NewBadRequestError("invalid user ID", err)
    }

    // Pass domain object to service
    user, err := c.service.GetUser(ctx.Request().Context(), userID)
    if err != nil {
        return err  // Return as-is, middleware logs
    }

    // Convert domain to API response
    return ctx.JSON(200, domainUser(*user).toAPI())
}

// Service - business logic with domain objects, wrap errors
func (s *Service) GetUser(ctx context.Context, id domain.UserID) (*domain.User, error) {
    user, err := s.repo.FindByID(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("failed to get user: %w", err)
    }
    return user, nil
}

// Repository - Domain → DB, query, DB → Domain
func (r *Repository) FindByID(ctx context.Context, id domain.UserID) (*domain.User, error) {
    var m model.User
    if err := r.db.Get(&m, query, id); err != nil {
        return nil, fmt.Errorf("failed to query user: %w", err)
    }
    return repositoryUser(m).toDomain(), nil
}
```

### Domain Error Handling

```go
// Create domain errors
domain.NewNotFoundError("User not found", err).
    WithCode(domain.ErrorCodeUserNotFound)

// Check error codes
if parsedErr, parseErr := domain.ParseError(err.Error()); parseErr == nil {
    if parsedErr.Code != nil && *parsedErr.Code == domain.ErrorCodeSessionExpired {
        // Handle session expiration
    }
}
```

### Import Naming

```go
import (
    domain2 "github.com/org/lib-common/domain"
    config2 "github.com/org/lib-common/config"
    domain "github.com/org/service/internal/domain"
    config "github.com/org/service/internal/config"
)
```

### Logging with Context

```go
// critical operations with trace IDs - use Msgf short form
log.Info().Ctx(ctx).Msgf("operation completed for user %s, session %s, amount %d", userID, sessionID, amount)

// don't log and return
if err != nil {
    return err  // middleware logs
}
```

### Domain Types

```go
type UserID uuid.UUID
type ItemID string

func GetUser(ctx context.Context, id domain.UserID) (*domain.User, error)
```

### Mapper Pattern

```go
// Type aliases for conversions
type (
    repositoryUser model.User
    domainUser     domain.User
)

// DB → Domain
func (r repositoryUser) toDomain() *domain.User {
    return &domain.User{
        ID:    domain.UserID(r.ID),
        Email: domain.Email(r.Email),
    }
}

// Domain → DB
func (d domainUser) asModel() model.User {
    return model.User{
        ID:    uuid.UUID(d.ID),
        Email: d.Email.String(),
    }
}

// Domain → API
type domainUserResponse domain.User

func (d domainUserResponse) toAPI() api.UserResponse {
    return api.UserResponse{
        ID:    d.ID.String(),
        Email: d.Email.String(),
    }
}

// Usage in layers
// Controller: API → Domain → Service → Repository
order := domain.Order{CustomerID: customerID, Amount: req.Amount}
result, err := c.service.PlaceOrder(ctx, order)
return ctx.JSON(200, domainOrderResult(result).toAPI())

// Repository: Domain → DB, DB → Domain
m := domainUser(user).asModel()
return repositoryUser(m).toDomain()
```

For detailed patterns and examples, see the reference documentation files.
