# RestEasy Resource Architecture

## Overview

A RestEasy-based API gem is structured as a Ruby module that acts as a singleton
container. The module holds shared state — connection, auth, configuration — and
the Resource classes within it handle individual API endpoints.

```
Fortnox (module, singleton container)
├── connection (Faraday, configured once)
├── authentication (auth module instance)
├── configuration (base_url, max_retries, etc.)
├── Resource (optional API-level base class, inherits RestEasy::Resource)
├── Invoice < Resource
├── Customer < Resource
└── Article < Resource
```

## Module Setup

The API gem author extends their module with RestEasy. This creates a DI
container, settings, and dependency injection for the module. Connection and
auth are configured once at the module level.

```ruby
module Fortnox
  extend RestEasy

  configure do |config|
    config.base_url = "https://api.fortnox.se/3"
    config.authentication = MachineKeyAuth.new(api_key: ENV['FORTNOX_KEY'])
    config.attribute_convention = :PascalCase
    config.max_retries = 3
  end

  # Optional: transport-level setup (mTLS, custom middleware, etc.)
  connection do |conn|
    conn.ssl.client_cert = OpenSSL::X509::Certificate.new(...)
  end
end
```

Resources reach into their parent module's container to get the shared
connection and configuration. No connection state lives on the Resource.

## Domain Dictionary

- **parse** — API data to model. The process of reading an API response into
  your domain model.
- **serialise** — Model to API. The process of preparing your domain model data
  for the API.

These terms are used consistently at every level: per-attribute converters,
model-level hooks, and throughout the codebase.

## Inheritance Chain

API gem authors can create an intermediate Resource class to handle API-wide
quirks once, rather than repeating overrides in every resource.

```
RestEasy::Resource          (gem defaults: PUT for update, standard REST)
  └── Fortnox::Resource     (API-level overrides: POST for updates, envelope wrapping, etc.)
        ├── Invoice         (endpoint-specific: path, attributes)
        ├── Customer
        └── Article
```

```ruby
module Fortnox
  # API-wide behaviour — all Fortnox resources inherit this
  class Resource < RestEasy::Resource
    # Fortnox uses POST for updates instead of PUT
    def self.update(instance)
      post(path: "#{endpoint_path}/#{instance.unique_id}", body: instance.serialise)
    end

    settings do
      setting :instance_wrapper
      setting :collection_wrapper
    end

    # Fortnox always wraps responses in an envelope
    before_parse do |api_data|
      api_data[config.instance_wrapper]
    end

    after_serialise do |api_data|
      { config.instance_wrapper => api_data }
    end
  end
end
```

Individual resources then only declare what is specific to that endpoint —
attributes and any further overrides:

```ruby
module Fortnox
  class Invoice < Resource
    endpoint_path "invoices"

    with_stub customer_number: ''

    key :document_number, Integer, :read_only
    attr :customer_name, String, :required
    attr :customer_number, String
    attr :balance, Float, :read_only
    attr :booked, Boolean, :read_only
    attr :credit, Boolean, :read_only
    attr :due_date, Date
    attr :invoice_date, Date
    attr :invoice_type, String
    attr :ocr, String
    attr :language, String
    attr :nox_finans, Boolean, :read_only
    attr :invoice_rows, [InvoiceRow]

    # Explicit API name needed — auto-matching can't resolve this one
    attr '@urlTaxReductionList' <=> :tax_reduction_list_url, String, :read_only, :optional

    ignore :some_internal_field

    synthetic :full_address, String do
      parse do |api|
        "#{api['Street']}, #{api['City']}"
      end
      serialise do |value|
        parts = value.split(', ')
        { 'Street' => parts[0], 'City' => parts[1] }
      end
    end
  end
end
```

## Usage

Resources are used directly via the module. No client instantiation needed.

```ruby
invoice = Fortnox::Invoice.find(123)
invoice = invoice.update(name: "New name")
Fortnox::Invoice.save(invoice)
```

## Request Layer and CRUD

### HTTP Primitives

RestEasy::Resource provides class-level HTTP methods that handle the connection
(from the parent module), auth lifecycle, and return raw response data:

- `get(path:, params:)` — GET request
- `post(path:, body:)` — POST request
- `put(path:, body:)` — PUT request
- `delete(path:)` — DELETE request

These are the building blocks. All higher-level operations are composed from
them.

### Default CRUD Operations

RestEasy::Resource provides standard REST operations out of the box:

```ruby
# Class-level operations
Resource.find(id)       # GET /endpoint/id → parse → instance
Resource.all            # GET /endpoint → parse each → array of instances
Resource.save(instance) # POST (if new) or PUT (if existing) → parse → instance
Resource.create(instance) # POST /endpoint → parse → instance
Resource.update(instance) # PUT /endpoint/id → parse → instance
Resource.delete(id)     # DELETE /endpoint/id
```

### Overriding

Any CRUD method can be overridden at the API level (in a shared base Resource)
or at the endpoint level. Overrides can call `super` to reuse the default
behaviour:

```ruby
# API-wide: Fortnox uses POST for updates
class Fortnox::Resource < RestEasy::Resource
  def self.update(instance)
    post(path: "#{endpoint_path}/#{instance.unique_id}", body: instance.serialise)
  end
end

# Endpoint-specific: custom create that unwraps a non-standard response
class Fortnox::Invoice < Fortnox::Resource
  def self.create(instance)
    response = super
    response['CreatedInvoice']
  end
end
```

### Custom Operations

API-specific operations like search, filtering, or bulk actions are defined by
the gem author using the same HTTP primitives:

```ruby
class Fortnox::Invoice < Fortnox::Resource
  def self.search(query:, limit: 50)
    response = get(params: { filter: query, limit: limit })
    response.map { |data| parse(data) }
  end

  def self.by_customer(customer_number)
    response = get(params: { customernumber: customer_number })
    response.map { |data| parse(data) }
  end
end
```

## Attribute Categories

### `attr` — Direct mapping

For attributes that map 1:1 between the API and resource. Handles the simple
majority case. Attributes are defined using model-side names (snake_case).

**Attribute convention:** The module-level `attribute_convention` config
determines how model attribute names (snake_case) are converted to/from API
field names. RestEasy ships with three built-in conventions:

- `:PascalCase` — `document_number` ↔ `DocumentNumber`
- `:camelCase` — `document_number` ↔ `documentNumber`
- `:snake_case` — no-op, pass through

A custom converter can be used instead — any object responding to `parse`
(API name → model name) and `serialise` (model name → API name).

```ruby
module Fortnox
  extend RestEasy

  configure do |config|
    config.attribute_convention = :PascalCase
  end
end
```

The `<=>` operator overrides the convention per attribute for outliers.

**Types:** Inside a Resource class body, bare Ruby type names (`String`,
`Integer`, `Float`, `Boolean`, `Date`) resolve to Dry::Types equivalents with
full constraint support. No `Types::` prefix needed for common cases.

```ruby
# Convention converts to/from API's DocumentNumber automatically
attr :document_number, Integer, :read_only

# Convention converts to/from API's CustomerName automatically
attr :customer_name, String, :required

# Type with constraints — full Dry::Types power, no prefix
attr :customer_name, String.constrained(max_size: 1024), :required

# Explicit API name when convention can't resolve it
# (e.g. @urlTaxReductionList doesn't follow any standard convention)
attr '@urlTaxReductionList' <=> :tax_reduction_list_url, String, :read_only

# With custom parse/serialise logic (block form)
attr :some_field <=> :model_name do
  parse do |raw_value|
    raw_value[5...-10]
  end
  serialise SomeMapper
end

# With custom parse/serialise logic (mapper object, must expose parse/serialise)
attr :some_field <=> :model_name, SomeMapper
```

### `ignore` — Explicitly excluded API fields

For API fields that the resource author has seen and deliberately chosen not to
surface. Makes the resource a complete declaration of the API relationship.

```ruby
ignore :some_api_attribute
```

### `synthetic` — Model-only attributes

For attributes that have no direct API counterpart. Assembled from API data or
computed. The block receives the full API data, not just a single field.

```ruby
synthetic :full_name, String do
  parse do |api|
    "#{api['FirstName']} #{api['LastName']}"
  end
  serialise do |value|
    { 'FirstName' => value.split(' ').first,
      'LastName'  => value.split(' ')[1..]&.join(' ') }
  end
end
```

## Resource-Level Hooks

Four hooks for pre/post processing around the parse and serialise processes.
These can be defined at any level of the inheritance chain (RestEasy::Resource,
API-level Resource, or individual endpoint Resource).

### Parse direction (API to model)

```ruby
before_parse do |api_data|
  api_data['Invoice']  # e.g. unwrap an API envelope
end

# ... per-attribute parse conversions run here ...

after_parse do |model|
  # cross-attribute validation, computed state, etc.
end
```

### Serialise direction (model to API)

```ruby
before_serialise do |model|
  # pre-serialisation logic
end

# ... per-attribute serialise conversions run here ...

after_serialise do |api_data|
  { 'Invoice' => api_data }  # e.g. re-wrap an API envelope
end
```

## Supporting Class Methods

- `endpoint_path "path"` — The URL path segment for this resource, appended to
  the module's base_url.
- `settings do ... end` — Declare custom `Dry::Configurable` settings that
  inherit through the resource hierarchy with per-subclass isolation. Access
  values via `config.setting_name` on the class or on instances (for use in hooks).
- `key :field_name, Type, ...` — Sugar for `attr` that also marks this attribute
  as the resource's unique identifier. Equivalent to
  `attr :field_name, Type, ..., :key`. A warning is logged if called more than
  once on a resource.
- `with_stub key: value, ...` — Declares default values for creating stub
  instances.

## Design Principles

1. **Singleton module** — Connection, auth, and configuration live on the
   module. Resources are stateless with regard to HTTP.
2. **Single file** — Everything about a resource lives in one place. No separate
   mapper files.
3. **Explicit completeness** — Every API field must be accounted for: mapped
   (`attr`), ignored (`ignore`), or consumed by a `synthetic`. Nothing is
   silently dropped.
4. **Simple by default** — The majority of attributes are simple 1:1 mappings.
   Define with model-side snake_case names, auto-matched to API names, bare
   Ruby types.
5. **Consistent vocabulary** — `parse` and `serialise` mean the same thing
   everywhere in the codebase.
6. **Override at the right level** — API-wide quirks in a shared base Resource,
   endpoint-specific overrides on individual Resources. `super` always available.

## Instance State

Each resource instance exposes three namespaces:

### `model` — The model-side attributes

The parsed, typed attributes as defined by `attr`, `key`, and `synthetic`
declarations. This is what the gem user works with.

### `api` — The shadow copy

The original API response data, retained to support:
- Change detection (comparing current model state against what was loaded)
- Round-tripping ignored fields (preserving API data that the resource doesn't
  surface)
- Providing `synthetic` attributes access to the full API data

### `meta` — Instance metadata

An officially supported, openly extensible metadata object for state that is
neither an API field nor a model attribute. RestEasy uses it internally for
core tracking, and gem authors can add their own domain-specific metadata.

**RestEasy-provided meta fields:**

- `meta.new?` — true if the instance was created locally, not loaded from API
- `meta.saved?` — true if the instance has been persisted to the API

**Gem author extensions (example):**

```ruby
module Fortnox
  class Resource < RestEasy::Resource
    after_parse do
      if api.attributes.keys.length != model.attributes.keys.length
        meta.partial = true
      end
    end

    def save
      raise PartialResourceError, "Load full resource before saving" if meta.partial
      super
    end

    def partial?
      meta.partial
    end
  end
end
```

`meta` is part of the public API — gem authors are encouraged to use it for
API-specific concerns like partial loading, caching timestamps, ETags, or any
other per-instance state that doesn't belong in the model or shadow copy.
