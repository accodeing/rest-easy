# RestEasy

[![Gem Version](https://badge.fury.io/rb/rest-easy.svg?icon=si%3Arubygems)](https://badge.fury.io/rb/rest-easy)

A Ruby framework for building REST API client libraries. Define your resources with a clean DSL, and RestEasy handles naming conventions, type coercion, serialisation, authentication, and HTTP plumbing — so you can ship an API gem with minimal boilerplate.

Built on [dry-rb](https://dry-rb.org/) (Types, Configurable) and [Faraday](https://lostisland.github.io/faraday/).

## Installation

Add to your gemspec:

```ruby
spec.add_runtime_dependency "rest-easy", "~> 1.0"
```

Or your Gemfile:

```ruby
gem "rest-easy", "~> 1.0"
```

Requires Ruby >= 3.1.

## Quick start

A complete API client in three steps:

```ruby
# 1. Define your API module
require "rest_easy"

module Acme
  extend RestEasy

  configure do
    base_url "https://api.acme.com/v1"
    authentication RestEasy::Auth::PSK.new(api_key: ENV["ACME_API_KEY"])
  end
end

# 2. Define a resource
class Acme::Widget < RestEasy::Resource
  configure do
    path "widgets"
  end

  key :id, Integer, :read_only
  attr :name, String, :required
  attr :price, Float
  attr :active, Boolean
end

# 3. Use it
widget = Acme::Widget.find(42)
widget.name                        # => "Sprocket"
widget.price                       # => 19.99

updated = widget.update(price: 24.99)
Acme::Widget.save(updated)
```

## Architecture

RestEasy uses a three-layer inheritance pattern:

```
RestEasy::Resource            # Framework base class
  └── YourAPI::Resource       # API-level base — shared config, hooks, custom settings
      ├── YourAPI::Invoice
      ├── YourAPI::Customer
      └── YourAPI::Article
```

The API module (`YourAPI`) owns the HTTP connection, authentication, and global settings. Resources define attributes and delegate HTTP calls up to their parent module.

## Setting up your API module

Extend any module with `RestEasy` to turn it into an API container:

```ruby
module Fortnox
  extend RestEasy

  configure do
    base_url "https://api.fortnox.se/3"
    max_retries 3
    authentication RestEasy::Auth::PSK.new(api_key: ENV["FORTNOX_KEY"])
  end
end
```

### Available settings

| Setting                          | Default                    | Description                                       |
|----------------------------------|----------------------------|---------------------------------------------------|
| `base_url`                       | `"https://example.com"`    | Base URL for all requests                         |
| `max_retries`                    | `3`                        | Retry count on request failure                    |
| `authentication`                 | `Auth::Null.new`           | Authentication strategy                           |
| `conversions.json_attributes`    | `:PascalCase`              | Naming convention for JSON response/request fields|
| `conversions.query_parameters`   | `:PascalCase`              | Naming convention for query parameter keys        |

### Faraday middleware

Configure the underlying Faraday connection with a `connection` block:

```ruby
module Acme
  extend RestEasy

  connection do |f|
    f.ssl[:client_cert] = OpenSSL::X509::Certificate.new(File.read("client.crt"))
    f.ssl[:client_key]  = OpenSSL::PKey::RSA.new(File.read("client.key"))
    f.ssl[:ca_file]     = "ca.crt"
  end
end
```

## Defining resources

### The base resource

For most APIs you'll want an intermediate base class that handles API-wide patterns like response envelopes, pagination metadata, or partial response detection:

```ruby
class Fortnox::Resource < RestEasy::Resource
  # Add custom settings for all resources in this API
  settings do
    setting :instance_wrapper, reader: true
    setting :collection_wrapper, reader: true
  end

  # Unwrap the response envelope before parsing
  before_parse do |data, meta|
    if data.key?("MetaInformation")
      meta.total_resources = data["MetaInformation"]["@TotalResources"]
      meta.pages = data["MetaInformation"]["@TotalPages"]
    end

    if data.key?(config.instance_wrapper)
      next data[config.instance_wrapper]
    elsif data.key?(config.collection_wrapper)
      next data[config.collection_wrapper]
    end
  end

  # Wrap the request body in the envelope
  after_serialise do |data|
    { config.instance_wrapper => data }
  end
end
```

### Concrete resources

Each resource configures its path and declares its attributes:

```ruby
class Fortnox::Article < Fortnox::Resource
  configure do
    path "articles"
    instance_wrapper "Article"
    collection_wrapper "Articles"
  end

  key :article_number, String
  attr :description, String, :required
  attr :purchase_price, Float
  attr :quantity_in_stock, Float
  attr :sales_price, Float, :read_only
  attr :active, Boolean
end
```

## Attributes

### Basic declaration

```ruby
attr :name, String
attr :count, Integer
attr :price, Float
attr :active, Boolean
attr :created_at, Date
```

Bare Ruby types (`String`, `Integer`, `Float`) are automatically mapped to their Dry::Types coercible equivalents. You also get `Boolean` and `Date` out of the box.

The full `Dry::Types` vocabulary is available inside resource bodies — `Strict::String`, `Coercible::Integer`, `Params::Date`, etc.

### Naming conventions

RestEasy automatically maps between Ruby's `snake_case` attribute names and the API's naming convention. The `conversions` config controls this independently for JSON attributes and query parameters. Both default to `:PascalCase`:

| Convention    | Ruby attr          | API field            |
|---------------|--------------------|----------------------|
| `:PascalCase` | `:document_number` | `"DocumentNumber"`   |
| `:camelCase`  | `:document_number` | `"documentNumber"`   |
| `:snake_case` | `:document_number` | `"document_number"`  |

Set conventions at the module level (applies to all resources):

```ruby
configure do
  conversions.json_attributes = :camelCase
  conversions.query_parameters = :PascalCase
end
```

Or override per resource:

```ruby
class MyAPI::Special < MyAPI::Resource
  configure do
    conversions.json_attributes = :PascalCase
  end
end
```

Query parameter keys are automatically transformed when calling `get` with `params:`. For example, with `query_parameters: :PascalCase`, `params: { sort_order: "asc" }` becomes `?SortOrder=asc` in the request.

You can also provide a custom convention object with `parse(api_name)` and `serialise(model_name)` methods.

### Explicit name mapping

When the API field name doesn't follow the convention, map it explicitly. In both forms the order is always model name first, API name second — `model_name <=> 'ApiName'` or `[:model_name, 'ApiName']`.

Using the `<=>` refinement:

```ruby
using RestEasy::Refinements

attr :tax_url <=> '@urlTaxReductionList', String, :read_only
attr :ean <=> 'EAN', String
attr :eu_account <=> 'EUAccount', Integer
```

Or use the array form without refinements:

```ruby
attr [:tax_url, '@urlTaxReductionList'], String, :read_only
```

### Flags

| Flag         | Effect                                                   |
|--------------|----------------------------------------------------------|
| `:required`  | Raises `MissingAttributeError` if absent in API response |
| `:optional`  | Documents that the field may be absent (default)         |
| `:read_only` | Excluded from serialisation (not sent back to the API)   |
| `:key`       | Marks the unique identifier for CRUD operations          |

```ruby
key :id, Integer, :read_only
attr :name, String, :required
attr :created_at, Date, :read_only
attr :nickname, String, :optional
```

The `key` method is shorthand for `attr` with the `:key` flag.

Beyond the built-in flags, you can use any symbol as a custom flag. Custom flags have no automatic behaviour — they're metadata you can query with `attributes_with_flag` and act on in hooks or query methods:

```ruby
class MyAPI::Invoice < MyAPI::Resource
  attr :internal_notes, String, :never_send_to_api
  attr :debug_info, String, :never_send_to_api
  attr :customer_name, String
end

class MyAPI::Resource < RestEasy::Resource
  after_serialise do |data|
    blocked = self.class.attributes_with_flag(:never_send_to_api).values.map(&:api_name)
    blocked.each { |key| data.delete(key) }
    data
  end
end
```

### Type constraints

Use Dry::Types constraints for validation:

```ruby
attr :name, String.constrained(max_size: 100)
attr :age, Integer.constrained(gteq: 0)
attr :status, Types::Strict::String.enum("active", "inactive")
```

Constraint violations raise `RestEasy::ConstraintError`.

### Custom parse and serialise

Transform values during parsing (API to model) and serialisation (model to API):

```ruby
attr :status, String do
  parse     { |raw| raw.strip.downcase }
  serialise { |val| val.upcase }
end
```

### Mapper objects

Extract parse/serialise logic into reusable objects. Any object that responds to `.parse` and `.serialise` works:

```ruby
module DateMapper
  def self.parse(value)
    Date.parse(value)
  end

  def self.serialise(value)
    value.strftime("%F")
  end
end

attr :invoice_date, Date, DateMapper
```

### Merge pattern — many API fields into one model attribute

When the parse method takes multiple parameters, RestEasy automatically extracts the corresponding API fields and passes them in:

```ruby
attr :full_name, String do
  parse     { |first_name, last_name| "#{first_name} #{last_name}" }
  serialise { |full_name| full_name.split(" ", 2) }
end
```

The parameter names (`first_name`, `last_name`) are resolved through the naming convention to find the API fields (`FirstName`, `LastName`). On serialisation, the array return value is zipped back to those field names.

This also works with mapper objects:

```ruby
module FullNameMapper
  def self.parse(first_name, last_name)
    "#{first_name} #{last_name}"
  end

  def self.serialise(full_name)
    full_name.split(" ", 2)
  end
end

attr :full_name, String, FullNameMapper
```

### Split pattern — one API field into many model attributes

Use a bare block with a parameter to extract from a single API field:

```ruby
attr :street, String do |address|
  address["street"]
end

attr :city, String do |address|
  address["city"]
end
```

The parameter name (`address`) determines which API field to read from.

### Ignoring fields

Tell RestEasy to silently skip API fields you don't need:

```ruby
ignore :internal_id, :legacy_code
```

With `debug: true` in your resource config, RestEasy warns about undeclared API fields. Use `ignore` to silence those warnings for fields you intentionally skip.

## Hooks

Hooks let you transform data at specific points in the parse and serialise lifecycle.

### `before_parse`

Runs before attribute parsing. Receives the raw API data hash and a meta collector. The return value replaces the data for parsing.

```ruby
before_parse do |data, meta|
  meta.response_code = data.delete("responseCode")
  next data["result"]
end
```

When the return value is an `Array`, RestEasy parses each item and returns an array of instances.

### `after_parse`

Runs after all attributes have been parsed. Access `model`, `api`, and `meta` on the instance. Return value is ignored.

```ruby
after_parse do
  meta.partial = api.attributes.length < model.attributes.length
end
```

### `before_serialise`

Runs before serialisation. Receives the model attributes hash. Return value is ignored (side-effects only).

```ruby
before_serialise do |attrs|
  raise "Name required" unless attrs[:name]
end
```

### `after_serialise`

Runs after serialisation. Receives the serialised hash. The return value becomes the final output.

```ruby
after_serialise do |data|
  { "Invoice" => data }
end
```

### Hook inheritance

Hooks resolve up the ancestor chain. A hook defined on `Fortnox::Resource` applies to all Fortnox resources. Override a hook in a child class to replace (not append to) the parent's hook.

If you want to extend rather than fully replace a parent hook, call the parent's hook explicitly via `superclass`:

```ruby
class Fortnox::Invoice < Fortnox::Resource
  before_parse do |data, meta|
    # Run the parent's before_parse first (envelope unwrapping, etc.)
    data = instance_exec(data, meta, &superclass.resolve_before_parse_hook)

    # Then do invoice-specific transforms
    data.delete("InternalFields")
    next data
  end
end
```

## Meta

Every instance carries a `meta` object for tracking state and custom metadata:

```ruby
widget = Acme::Widget.find(42)
widget.meta.new?                # => false (came from API)
widget.meta.saved?              # => true  (persisted)

draft = Acme::Widget.stub(name: "Draft")
draft.meta.new?                 # => true  (created locally)
draft.meta.saved?               # => false (not persisted)
```

### Custom metadata

Set and query arbitrary metadata — useful in hooks:

```ruby
before_parse do |data, meta|
  meta.total_pages = data["MetaInformation"]["@TotalPages"]
end

# Later:
result = Fortnox::Invoice.all
result.first.meta.total_pages   # => 5
```

### Metadata defaults

Declare defaults at the class level:

```ruby
class Fortnox::Resource < RestEasy::Resource
  metadata partial: false
end

instance.meta.partial?          # => false (default)
```

Defaults are inherited and merged down the class hierarchy.

## Authentication

RestEasy ships with three auth strategies:

### Null (default)

No authentication. Use when auth is handled at the transport level (mTLS, VPN, etc.):

```ruby
authentication RestEasy::Auth::Null.new
```

### PSK (Pre-Shared Key / API Key)

Static API key sent as a header:

```ruby
authentication RestEasy::Auth::PSK.new(
  api_key: ENV["API_KEY"],
  header_name: "Authorization",  # default
  header_prefix: "Bearer"        # default
)
```

### Basic

HTTP Basic authentication:

```ruby
authentication RestEasy::Auth::Basic.new(
  username: ENV["API_USER"],
  password: ENV["API_PASS"]
)
```

### Custom authentication

Implement `apply(request)` and `on_rejected(response)`:

```ruby
class OAuth2Auth
  def apply(request)
    refresh_token! if expired?
    request.headers["Authorization"] = "Bearer #{@access_token}"
  end

  def on_rejected(response)
    # Returning normally triggers a retry (up to max_retries).
    # Raising propagates the error immediately.
    refresh_token!
  end
end
```

The retry lifecycle:

1. `auth.apply(request)` — attach credentials
2. Make HTTP request
3. On failure: `auth.on_rejected(response)`
   - Return normally → retry (up to `max_retries`)
   - Raise → propagate error

## CRUD operations

Resources provide standard CRUD methods:

```ruby
# Fetch
invoice = Fortnox::Invoice.find(123)
invoices = Fortnox::Invoice.all

# Create
draft = Fortnox::Invoice.stub(customer_name: "Acme", amount: 500.0)
created = Fortnox::Invoice.create(draft)

# Update
updated = invoice.update(amount: 750.0)
saved = Fortnox::Invoice.save(updated)

# Delete
Fortnox::Invoice.delete(123)
```

`save` routes to `create` or `update` based on `meta.new?`.

### Custom query methods

Override or extend CRUD at the base resource level:

```ruby
class Fortnox::Resource < RestEasy::Resource
  class << self
    def find(id_or_hash)
      return find_all_by(id_or_hash) if id_or_hash.is_a?(Hash)
      find_one_by(id)
    end

    def search(hash)
      attribute, value = hash.first
      response = get(path: config.path, params: { attribute => value })
      parse(response)
    end

    def only(filter)
      response = get(path: config.path, params: { filter: filter })
      parse(response)
    end
  end
end
```

## Instance state

### Three namespaces

Every parsed instance exposes three namespaces:

```ruby
invoice = Fortnox::Invoice.parse(api_response)

# model — parsed attributes with Ruby names
invoice.model.customer_name       # => "Acme Corp"
invoice.customer_name             # => "Acme Corp" (shortcut)
invoice.model.attributes          # => { customer_name: "Acme Corp", ... }

# api — shadow copy of the original API data
invoice.api.attributes            # => { "CustomerName" => "Acme Corp", ... }

# meta — instance metadata
invoice.meta.new?                 # => false
```

### Immutable updates

`update` returns a new instance — the original is unchanged:

```ruby
original = Fortnox::Invoice.find(1)
changed = original.update(amount: 999.0)

original.amount                   # => 500.0  (unchanged)
changed.amount                    # => 999.0
changed.__changes__               # => { amount: 999.0 }
```

### Serialisation

```ruby
invoice.serialise                 # => { "CustomerName" => "Acme", ... } (Ruby hash, API names)
invoice.to_api                    # => '{"CustomerName":"Acme",...}'      (JSON string, API names)
invoice.to_json                   # => '{"customer_name":"Acme",...}'     (JSON string, model names)
```

Read-only attributes are excluded from `serialise` and `to_api`.

## Stubs

Create local instances that haven't been persisted:

```ruby
draft = Fortnox::Invoice.stub(customer_name: "Acme", amount: 100.0)
draft.meta.new?                   # => true
draft.meta.saved?                 # => false
```

Define defaults with `with_stub`:

```ruby
class Acme::Invoice < RestEasy::Resource
  with_stub amount: 0.0, currency: "SEK"
end

invoice = Acme::Invoice.stub(customer_name: "Test")
invoice.amount                    # => 0.0 (from default)
invoice.currency                  # => "SEK"
```

## Resource-level settings

Add custom `Dry::Configurable` settings to any resource:

```ruby
class Fortnox::Resource < RestEasy::Resource
  settings do
    setting :instance_wrapper, reader: true
    setting :collection_wrapper, reader: true
    setting :filters, default: {}
  end
end

class Fortnox::Invoice < Fortnox::Resource
  configure do
    path "invoices"
    instance_wrapper "Invoice"
    collection_wrapper "Invoices"
    filters({ filter: String.enum("cancelled", "unpaid") })
  end
end

Fortnox::Invoice.config.instance_wrapper   # => "Invoice"
```

Settings are inherited and isolated — child class changes don't affect parents.

## Debug mode

Enable per-resource warnings about API field mismatches:

```ruby
class Acme::Invoice < RestEasy::Resource
  configure do
    debug true
  end
end
```

With debug on, RestEasy warns about:
- API fields not declared as attributes or explicitly ignored
- Declared attributes missing from the API response

## Error hierarchy

```
RestEasy::Error
├── RestEasy::AttributeError
│   ├── RestEasy::MissingAttributeError    # Required attribute absent
│   └── RestEasy::ConstraintError          # Type constraint violated
├── RestEasy::RequestError                 # HTTP request failed
├── RestEasy::AuthenticationError          # Auth rejected
├── RestEasy::RemoteServerError            # 5xx response
└── RestEasy::RateLimitError               # Rate limited
```

## Full walkthrough: building an API gem

Here's how to build a complete API client gem, using patterns from real implementations.

### 1. Set up the gem structure

```
my_api/
├── lib/
│   ├── my_api.rb
│   └── my_api/
│       ├── resource.rb
│       └── resources/
│           ├── customer.rb
│           └── invoice.rb
├── my_api.gemspec
└── spec/
```

### 2. Create the API module

```ruby
# lib/my_api.rb
require "rest_easy"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.collapse("#{__dir__}/my_api/resources")
loader.setup

module MyAPI
  extend RestEasy

  configure do
    base_url "https://api.example.com/v1"
    max_retries 3
    authentication RestEasy::Auth::PSK.new(api_key: ENV["MY_API_KEY"])
    conversions.json_attributes = :PascalCase
  end
end
```

### 3. Create the base resource

```ruby
# lib/my_api/resource.rb
class MyAPI::Resource < RestEasy::Resource
  settings do
    setting :instance_wrapper, reader: true
    setting :collection_wrapper, reader: true
  end

  before_parse do |data, meta|
    if data.key?("Meta")
      meta.total = data["Meta"]["TotalRecords"]
      meta.page = data["Meta"]["CurrentPage"]
    end

    if data.key?(config.instance_wrapper)
      next data[config.instance_wrapper]
    elsif data.key?(config.collection_wrapper)
      next data[config.collection_wrapper]
    end
  end

  after_serialise do |data|
    { config.instance_wrapper => data }
  end
end
```

### 4. Define resources

```ruby
# lib/my_api/resources/customer.rb
class MyAPI::Customer < MyAPI::Resource
  configure do
    path "customers"
    instance_wrapper "Customer"
    collection_wrapper "Customers"
  end

  key :customer_number, String
  attr :name, String, :required
  attr :email, String
  attr :organisation_number, String
  attr :created_at, Date, :read_only
end
```

```ruby
# lib/my_api/resources/invoice.rb
class MyAPI::Invoice < MyAPI::Resource
  using RestEasy::Refinements

  configure do
    path "invoices"
    instance_wrapper "Invoice"
    collection_wrapper "Invoices"
  end

  key :document_number, Integer, :read_only

  attr :customer_number, String, :required
  attr :invoice_date, Date
  attr :due_date, Date
  attr :total_amount, Float, :read_only
  attr :currency, String
  attr :vat <=> 'VAT', Float
  attr :pdf_url <=> '@urlPDF', String, :read_only

  ignore :internal_status_code
end
```

### 5. Use your gem

```ruby
require "my_api"

# Configure auth at runtime
MyAPI.configure do |config|
  config.authentication = RestEasy::Auth::PSK.new(api_key: "live-key-123")
end

# Fetch records
customers = MyAPI::Customer.all
invoice = MyAPI::Invoice.find(10001)

# Create a new record
draft = MyAPI::Customer.stub(
  name: "Acme Corp",
  email: "billing@acme.com",
  organisation_number: "556677-8899"
)
customer = MyAPI::Customer.create(draft)

# Update
updated = customer.update(email: "new@acme.com")
MyAPI::Customer.save(updated)

# Access metadata from hooks
invoices = MyAPI::Invoice.all
invoices.first.meta.total         # => 142
invoices.first.meta.page          # => 1
```

## License

MIT
