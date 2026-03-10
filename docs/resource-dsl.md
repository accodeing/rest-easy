# Resource DSL

RestEasy maps between two worlds: the **API** (JSON data from a remote service) and
the **model** (Ruby objects your application works with). A Resource class describes
how to translate between the two.

This guide starts with the simplest declarations and builds towards the more
flexible patterns.

## Module setup

Before defining resources you need a module that acts as the namespace for your API
client. This is where shared configuration and resources live.

```ruby
module Fortnox
  extend RestEasy

  configure do |config|
    config.base_url          = "https://api.fortnox.se/3"
    config.attribute_convention = :PascalCase
  end
end
```

## Defining a resource

A resource is a Ruby class that inherits from `RestEasy::Resource`. You declare
attributes, and RestEasy handles parsing API responses into model objects and
serialising them back.

```ruby
class Fortnox::Invoice < RestEasy::Resource
  path "invoices"

  key :document_number, Integer, :read_only
  attr :customer_name,  String, :required
  attr :due_date,       String
  attr :total,          Float,  :read_only
end
```

That's it. This gives you:

```ruby
invoice = Fortnox::Invoice.parse({
  "DocumentNumber" => 1001,
  "CustomerName"   => "Acme Corp",
  "DueDate"        => "2024-06-15",
  "Total"          => 2500.0
})

invoice.customer_name       # => "Acme Corp"
invoice.document_number     # => 1001
invoice.unique_id           # => 1001

invoice.serialise
# => { "CustomerName" => "Acme Corp", "DueDate" => "2024-06-15" }
# (read_only fields excluded)
```

## Attributes

### Basic declaration

```ruby
attr :name, String
```

The first argument is the model name (a Ruby symbol). The second is the type, used
for coercion. The model name is converted to an API name using the active attribute
convention (`:PascalCase` by default), so `:name` becomes `"Name"` in JSON.

### Available types

RestEasy provides shortcuts for common types. Inside a Resource class body these
resolve to Dry::Types equivalents with automatic coercion:

| DSL constant | Coercion behaviour                       |
|--------------|------------------------------------------|
| `String`     | Anything to string                       |
| `Integer`    | Numeric strings to integer               |
| `Float`      | Numeric strings to float                 |
| `Boolean`    | `"true"`, `"1"`, `true` etc. to boolean  |
| `Date`       | Date strings (`"2024-01-15"`) to Date    |

You also have access to the full `Dry::Types` vocabulary through the `Types` module:

```ruby
attr :status, Types::Strict::String.enum("active", "inactive", "archived")
```

### Type constraints

Constraints can be added to any type:

```ruby
attr :name, String.constrained(max_size: 100)
attr :age,  Integer.constrained(gteq: 0)
```

A constraint violation during parsing raises `RestEasy::ConstraintError`.

### Flags

Flags are symbols passed after the type:

```ruby
attr :id,       Integer, :key, :read_only
attr :name,     String,  :required
attr :nickname, String,  :optional
attr :balance,  Float,   :read_only
```

| Flag         | Effect                                                             |
|--------------|--------------------------------------------------------------------|
| `:key`       | Marks the unique identifier. Used by `unique_id` and CRUD routing. |
| `:required`  | Raises `MissingAttributeError` if the API field is `nil`.          |
| `:optional`  | Documents that `nil` is expected. No runtime effect.               |
| `:read_only` | Parsed from API data but excluded from serialisation.              |

### The `key` shorthand

Since every resource typically has one identifier, there's a shorthand:

```ruby
key :document_number, Integer, :read_only
```

This is equivalent to:

```ruby
attr :document_number, Integer, :key, :read_only
```

Defining more than one key emits a warning.

## Attribute conventions

The convention controls how model names (`:customer_name`) map to API names
(`"CustomerName"`). Set it on the module or override it per resource.

### Built-in conventions

```ruby
# Module-level default (applies to all resources in the namespace)
configure do |config|
  config.attribute_convention = :PascalCase
end

# Per-resource override
class Fortnox::Invoice < RestEasy::Resource
  attribute_convention :camelCase
end
```

| Convention    | `:document_number` becomes |
|---------------|----------------------------|
| `:PascalCase` | `"DocumentNumber"`         |
| `:camelCase`  | `"documentNumber"`         |
| `:snake_case` | `"document_number"`        |

### Custom conventions

Pass any object that responds to `parse(api_name)` and `serialise(model_name)`:

```ruby
class ScreamingSnakeCase
  def parse(api_name)
    api_name.downcase.to_sym
  end

  def serialise(model_name)
    model_name.to_s.upcase
  end
end

attribute_convention ScreamingSnakeCase.new
```

### Explicit name mapping with `<=>`

Some API field names don't follow a consistent convention. The `<=>` operator lets
you map an exact API name to a model name:

```ruby
using RestEasy::Refinements

attr '@urlTaxReductionList' <=> :tax_reduction_list_url, String, :read_only
```

This bypasses the convention entirely for that attribute. The API name
`"@urlTaxReductionList"` maps to and from `:tax_reduction_list_url` directly.

The `using RestEasy::Refinements` line must appear in any file that uses `<=>`.
If you'd rather not then you can pass the two names as an array instead:
`attr ['@urlTaxReductionList', :tax_reduction_list_url], String, :read_only`

## Ignoring fields

APIs often include fields your application doesn't need. By default, RestEasy warns
about API fields that aren't declared as attributes. Use `ignore` to silence the
warning and document the decision:

```ruby
class Fortnox::Invoice < RestEasy::Resource
  attr :name, String
  ignore :internal_id, :legacy_flag, :created_at
end
```

Ignored fields are preserved in the shadow copy and round-tripped on serialisation,
so the API gets back what it sent.

## Custom parse and serialise

### Single-value transform

When a field exists in the API with a straightforward mapping but needs
transformation, use a block with `parse` and `serialise`:

```ruby
attr :status, String do
  parse     { |raw| raw.strip.downcase }
  serialise { |val| val.upcase }
end
```

The `parse` block receives the raw API value and returns the model value.
The `serialise` block receives the model value and returns the API value.

You can define just one or both. Without a `parse` block, the value is passed
through with type coercion. Without a `serialise` block, JSON-native types pass
through and everything else gets `.to_s`.

This works with explicit name mapping too:

```ruby
using RestEasy::Refinements

attr 'raw_field' <=> :clean_field, String do
  parse     { |raw| raw.strip.downcase }
  serialise { |val| val.upcase }
end
```

## Merging fields (many API fields to one model attribute)

Sometimes the API sends data across multiple fields that you want to combine into a
single model attribute. The block parameter names tell RestEasy which API fields to
extract:

```ruby
attr :full_name, String do
  parse     { |first_name, last_name| "#{first_name} #{last_name}" }
  serialise { |full_name| full_name.split(" ", 2) }
end
```

RestEasy introspects the parse block parameters. Because `|first_name, last_name|`
has two parameters, it knows to:

1. Look up `"FirstName"` and `"LastName"` in the API data (via the active convention)
2. Pass both values into the block

On serialisation, the block returns an array. RestEasy zips the array with the
source field names and writes each value back under its original API name.

The shorthand for read-only merged fields is a bare block:

```ruby
attr :full_name, String, :read_only do |first_name, last_name|
  "#{first_name} #{last_name}"
end
```

A block with parameters directly on `attr` is treated as an implicit parse block.

## Splitting fields (one API field to many model attributes)

The reverse pattern: one API field (like a nested object) feeds into multiple model
attributes.

```ruby
attr :street, String do |address|
  address["street"]
end

attr :city, String do |address|
  address["city"]
end
```

Each bare block has a single parameter (`address`), so RestEasy looks up the
`"Address"` field from the API data and passes the value to the block.

Without a serialise block, each attribute serialises under its own API name using
the default behaviour (JSON-native types pass through, everything else gets `.to_s`).

## Reconstructing fields (many model attributes to one API field)

When multiple model attributes need to be combined into a single API field during
serialisation, use a multi-parameter serialise block:

```ruby
attr :street, String
attr :city,   String

attr :address, String do
  serialise { |street, city| "#{street}, #{city}" }
end
```

RestEasy introspects the serialise block parameters. Because `|street, city|` names
two model attributes, it gathers their current values and passes them in.

## Lifecycle hooks

Hooks let you transform data at specific points in the parse/serialise pipeline.
They run on the instance via `instance_exec`, giving you access to `model`, `api`,
`meta`, `config`, and `endpoint_path`.

### `before_parse`

Runs before attribute parsing. Receives the raw API data. **Return value replaces
the data** that will be parsed — use this to unwrap response envelopes:

```ruby
before_parse do |api_data|
  api_data[config.instance_wrapper]   # must return the unwrapped hash
end
```

### `after_parse`

Runs after all attributes have been parsed. Receives `model` and `api`.
**Return value is ignored** — use this for side effects like setting metadata:

```ruby
after_parse do |model, api|
  meta.partial = true if api.attributes.length < model.attributes.length
end
```

### `before_serialise`

Runs before attribute serialisation. Receives the model attributes hash.
**Return value is ignored** — use this for side effects like logging or validation:

```ruby
before_serialise do |attrs|
  # Inspect or log before sending
end
```

### `after_serialise`

Runs after serialisation. Receives the serialised hash and model. **Return value
becomes the final output** — use this to wrap in an envelope:

```ruby
after_serialise do |api_data|
  { config.instance_wrapper => api_data }   # must return the wrapped hash
end
```

## Inheritance

RestEasy supports a three-level inheritance chain:

```
RestEasy::Resource          # framework base
  Fortnox::Resource         # API-level base (shared hooks, convention)
    Fortnox::Invoice        # endpoint resource (attributes, path)
    Fortnox::Customer
```

### API-level base

Define shared behaviour once:

```ruby
class Fortnox::Resource < RestEasy::Resource
  settings do
    setting :instance_wrapper
    setting :collection_wrapper
  end

  before_parse do |api_data|
    api_data[config.instance_wrapper]       # unwrap { "Invoice" => { ... } }
  end

  after_serialise do |api_data|
    { config.instance_wrapper => api_data } # re-wrap for the API
  end
end
```

### Endpoint resources

Endpoint resources inherit hooks, convention, and attributes from their parent:

```ruby
class Fortnox::Invoice < Fortnox::Resource
  path "invoices"
  config.instance_wrapper = "Invoice"
  config.collection_wrapper = "Invoices"

  key :document_number, Integer, :read_only
  attr :customer_name,  String, :required
  attr :amount,         Float
end

class Fortnox::Customer < Fortnox::Resource
  path "customers"
  config.instance_wrapper = "Customer"
  config.collection_wrapper = "Customers"

  key :customer_number, Integer, :read_only
  attr :name, String
end
```

### Shared attributes

You can add an intermediate class for common fields:

```ruby
class Fortnox::Document < Fortnox::Resource
  attr :created_at, String, :read_only
  attr :updated_at, String, :read_only
end

class Fortnox::Order < Fortnox::Document
  path "orders"

  key :id, Integer, :read_only
  attr :total, Float
end
```

`Order` inherits `:created_at` and `:updated_at` from `Document`, plus the hooks
from `Resource`.

### Overriding hooks

A child class can replace a parent hook. The child's hook is used instead, not in
addition to the parent's:

```ruby
class Fortnox::SpecialInvoice < Fortnox::Resource
  path "special-invoices"

  before_parse do |api_data|
    api_data["SpecialWrapper"]["Data"]
  end

  # ...
end
```

## Instance state

Every parsed resource instance carries three layers of state:

### `model`

The parsed, coerced model attributes. Accessible as methods on the instance and
through the `model` proxy:

```ruby
invoice.customer_name          # direct accessor
invoice.model.customer_name    # via proxy
```

### `api` (shadow copy)

The original API response data, preserved exactly as received. Useful for
round-tripping fields you don't model:

```ruby
invoice.api.attributes
# => { "DocumentNumber" => 1001, "CustomerName" => "Acme Corp", ... }
```

### `meta`

Tracks lifecycle state and allows gem authors to attach custom metadata:

```ruby
invoice.meta.new?       # => false (came from API)
invoice.meta.saved?     # => true

stub = Fortnox::Invoice.stub(customer_name: "Draft")
stub.meta.new?          # => true (created locally)
stub.meta.saved?        # => false

# Custom metadata (set per-instance)
invoice.meta.partial = true
invoice.meta.partial?   # => true
```

#### Class-level metadata defaults

Use `metadata` to set default meta values for every instance of a resource:

```ruby
class Fortnox::Resource < RestEasy::Resource
  metadata partial: true
end
```

Every instance created via `parse`, `stub`, or `update` will have
`meta.partial?` return `true`. Instances can still override defaults:

```ruby
invoice.meta.partial = false
invoice.meta.partial?   # => false
```

Metadata defaults are inherited and merged. A child class can add to or
override its parent's defaults:

```ruby
class Fortnox::Invoice < Fortnox::Resource
  metadata wrapper: "Invoice"
  # inherits partial: true from parent, adds wrapper: "Invoice"
end
```

## Change tracking and immutability

`update` returns a new instance with the changes applied. The original is unchanged:

```ruby
invoice = Fortnox::Invoice.parse({ "DocumentNumber" => 1, "CustomerName" => "Old", "Amount" => 100.0 })

updated = invoice.update(customer_name: "New")

invoice.customer_name           # => "Old"
updated.customer_name           # => "New"
updated.__changes__             # => { customer_name: "New" }
```

## Creating local instances

`stub` creates an instance from model-side data, marked as new:

```ruby
invoice = Fortnox::Invoice.stub(
  customer_name: "New Customer",
  amount: 500.0
)

invoice.meta.new?   # => true
```

## Serialisation outputs

| Method      | Output                                                  |
|-------------|---------------------------------------------------------|
| `serialise` | Ruby hash with API-side names, `:read_only` excluded    |
| `to_api`    | JSON string of `serialise` output                       |
| `to_json`   | JSON string with model-side names (all attributes)      |

## CRUD operations

CRUD methods compose the parse/serialise pipeline with HTTP primitives:

```ruby
Fortnox::Invoice.find(1001)         # GET /invoices/1001 -> parse
Fortnox::Invoice.all                # GET /invoices      -> parse each
Fortnox::Invoice.save(instance)     # POST or PUT depending on meta.new?
Fortnox::Invoice.create(instance)   # POST /invoices     -> parse response
Fortnox::Invoice.update(instance)   # PUT /invoices/:id  -> parse response
Fortnox::Invoice.delete(1001)       # DELETE /invoices/1001
```

These can be overridden at the API-level for non-standard APIs:

```ruby
class Fortnox::Resource < RestEasy::Resource
  def self.update(instance)
    response = post(
      path: "#{endpoint_path}/#{instance.unique_id}",
      body: instance.serialise
    )
    parse(response)
  end
end
```

## Quick reference

```ruby
class Fortnox::Invoice < Fortnox::Resource
  path "invoices"                                            # endpoint path
  config.instance_wrapper = "Invoice"                        # envelope key (setting)
  config.collection_wrapper = "Invoices"                     # list envelope key (setting)
  attribute_convention :PascalCase                            # override convention
  metadata partial: true                                     # default meta on instances

  key :document_number, Integer, :read_only                  # unique identifier

  attr :customer_name, String, :required                     # required field
  attr :due_date, Date                                       # auto-coerced
  attr :balance, Float, :read_only                           # read-only
  attr :nickname, String, :optional                          # explicitly optional

  attr '@url' <=> :url, String, :read_only                   # explicit API name

  attr :status, String do                                    # custom transform
    parse     { |raw| raw.downcase }
    serialise { |val| val.upcase }
  end

  attr :full_name, String do                                 # merge (many -> one)
    parse     { |first_name, last_name| "#{first_name} #{last_name}" }
    serialise { |full_name| full_name.split(" ", 2) }
  end

  attr :city, String do |address|                            # split (one -> many)
    address["city"]
  end

  attr :address, String do                                   # reconstruct (many -> one)
    serialise { |street, city| "#{street}, #{city}" }
  end

  ignore :internal_id, :legacy_flag                          # silence warnings

  before_parse     { |data| data[config.instance_wrapper] }  # unwrap envelope
  after_parse      { |model, api| ... }                      # post-parse logic
  before_serialise { |attrs| ... }                           # pre-serialise logic
  after_serialise  { |data| { config.instance_wrapper => data } }  # wrap envelope

  with_stub customer_name: "Default"                         # stub defaults
end
```
