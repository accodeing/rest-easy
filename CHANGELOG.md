# Changelog

## [Unreleased]

## [1.4.1] - 2026-08-18

### Fixed

- **`Meta` no longer claims to implement methods it has no value for.**
  `Meta#respond_to_missing?` returned `true` for every name, so any caller
  that asks an object what it can do before calling it got a false yes, then
  received the `nil` that `method_missing` returns for an unknown key as
  though it were a real answer. Ruby does this constantly and implicitly —
  coercion probes when a value is splatted or interpolated, serialisation
  hooks, and any library that duck-types with `respond_to?` — so the failure
  surfaced far from `Meta` and looked unrelated to it. Marshalling was the
  sharpest case: `dump` silently wrote an empty payload and `load` then
  raised `NoMethodError` from inside `method_missing`, which broke every
  consumer caching resources in a store that marshals its entries.

  Bare getters are now claimed only for keys the instance actually holds.
  Setters and predicates are still claimed unconditionally, since writing is
  how a key comes into existence and an unset predicate is meaningfully
  `false`; no core Ruby probe uses those two shapes. Library-level
  duck-typing can, though — ActiveSupport's `acts_like?(:date)` asks for
  `acts_like_date?`, and `Meta` still answers yes — so the guarantee is
  narrower than "nothing probes for `=` or `?`", and closing it properly is
  tracked in #7. Operators are no longer claimed either: the check is
  anchored to identifier-shaped names, so `<=` is not mistaken for a setter
  (`method_missing` still is — #6).
  `Resource::MetaCollector` had the identical defect and is fixed the same
  way.

  **Upgrading with a warm cache:** entries written by an earlier version are
  not recoverable. A payload dumped before this fix carries `nil` where the
  meta state should be, and loading it now raises `TypeError: instance of
  RestEasy::Meta needs to have method 'marshal_load'` — legible, but still
  an error. Consumers on a cache that survives deploys (`:file_store`,
  Redis, Memcached) must flush it or bump the cache key namespace when
  upgrading. A process-local `:memory_store` clears itself on restart and
  needs nothing.

  `method_missing` is unchanged: a bare getter for a key that was never set
  still returns `nil` rather than raising, as the "gem author extensions"
  example in `docs/model-architecture.md` depends on. `respond_to?`
  therefore under-reports for those keys; reconciling the two halves
  requires declaring meta keys up front and is tracked in #7.

## [1.4.0] - 2026-06-26

### Fixed

- **`:required` is now enforced on serialise as well as parse.** Previously
  the flag raised `MissingAttributeError` only when an API response omitted
  the field; it was silently ignored when sending (`save`), letting
  incomplete payloads reach the backend and surface as a generic
  `RequestError`. The flag now also fires at `serialise` time (and therefore
  on `save`) when a required attribute is `nil`, before any HTTP request,
  with the attribute name on the exception (`#attribute_name`). Inbound
  behavior is unchanged — `parse` still raises on missing required fields.
  A field is treated as missing whether the API response omits the key
  entirely or includes it as explicit `null`; both are rejected as
  incomplete data.
- **`:required` is now enforced on synthetic attributes (merge / combine /
  split patterns).** Previously the flag was silently a no-op for any
  attribute with a multi-parameter parse or serialise block. It now
  enforces presence on all underlying API or model fields: a merge
  attribute requires every source API field on parse; a combine attribute
  requires every named model attribute on serialise; a split attribute
  requires the underlying API field on parse. `:read_only` continues to
  skip the serialise-time check.

### Changed

- **The DSL auto-applies `:synthetic` to multi-parameter serialise blocks**
  (and mapper `serialise` methods), mirroring the existing behavior for
  multi-parameter parse. Previously only the parse side was tagged,
  leaving the flag inconsistent with its intent of marking attributes whose
  storage shape diverges from the standard one-slot layout.
- **Combine attributes no longer read from their `api_name` on parse.**
  A combine attribute's API name does not correspond to a real inbound
  field by design — the value is built from `target_fields` at serialise
  time. The previous code looked up `api_data[api_name]`, stored it at
  the model slot, and ran the standard `:required` check, raising
  spuriously when the field was absent (the documented case). Inbound
  values for the shadowed API key are now ignored and the model slot is
  set to `nil`, avoiding the contradiction where `instance.address` could
  return one value while serialise would overwrite it with another.

## [1.3.1] - 2026-05-27

### Fixed

- **`ConstraintError` messages now include the attribute name.**
  When attribute coercion fails, the raised `RestEasy::ConstraintError`
  previously surfaced only the underlying dry-types reason
  (e.g. `invalid value for Integer(): ""`), leaving the user to guess which
  attribute on which resource had failed. The message now prefixes the
  model-side attribute name:
  `Attribute 'count': invalid value for Integer(): ""`.
  The exception's `#attribute_name` reader is unchanged.

## [1.3.0] - 2026-05-19

### Added

- `base64` is now an explicit runtime dependency. It stopped being a
  default gem in Ruby 3.4, so it must be declared for the basic-auth
  strategy to load.

### Changed

- **Minimum Ruby version raised to 3.2.** Ruby 3.1 reached end-of-life
  in March 2025 and is no longer supported or tested. Consumers on Ruby
  3.1 are held at the previous release by Bundler.

## [1.2.0] - 2026-05-17

### Added

- **`logger` setting.** When set to a `Logger`-compatible instance, Faraday's built-in logger middleware is attached to the connection and logs HTTP request/response lines and headers. Unset by default — no overhead when not in use. The standard auth-bearing headers (`Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`) are always filtered to `[FILTERED]`; consumer gems are responsible for redacting domain-specific secrets in non-standard headers or response bodies (see README "Redacting domain-specific secrets").
- **`log_bodies` setting** (default `false`). Opt-in toggle for logging request/response bodies. Off by default because bodies often carry domain-specific secrets that RestEasy cannot recognize.

## [1.1.2] - 2026-05-15

### Changed

- **`dry-configurable` requirement bumped from `~> 0.14` to `~> 1.0`.** The 0.14 pin blocked any downstream that pulled in `dry-configurable >= 1.0`.

## [1.1.1] - 2026-05-15

### Fixed

- **`conversions.query_parameters` default changed from `:PascalCase` to `nil`.** In 1.1.0 the new automatic query parameter transformation combined with a `:PascalCase` default silently rewrote keys for every consumer, regardless of intent — `Resource.get(params: { city: "X" })` produced `?City=X` instead of `?city=X`. With the new default, `Resource.get` does not transform parameter keys unless `conversions.query_parameters` is explicitly configured, restoring 1.0.0 behaviour. The `json_attributes` default remains `:PascalCase`, since that preserves 1.0.0's `attribute_convention` default.

## [1.1.0] - 2026-05-15

### Added

- **`conversions` configuration** with independent `query_parameters` and `json_attributes` sub-keys. This allows APIs that use different naming conventions for query parameters vs JSON body attributes to be configured correctly:

  ```ruby
  module MyAPI
    extend RestEasy

    configure do
      conversions.json_attributes = :camelCase
      conversions.query_parameters = :PascalCase
    end
  end
  ```

- **Automatic query parameter key transformation.** `Resource.get` now transforms parameter keys according to the `query_parameters` convention before sending the request. This removes the need for manual `transform_keys` calls in consuming gems.

- `conversions` can be overridden per Resource class, with inheritance falling back to the parent API module configuration.

### Deprecated

- **`attribute_convention`** is deprecated in favour of `conversions.json_attributes`. The old setting continues to work — it is propagated to `conversions.json_attributes` at the module level and respected as a fallback at the resource level — but emits a deprecation warning in both cases.

### Removed

- **`dry-inflector` runtime dependency.** The gem never used `Dry::Inflector` — Zeitwerk's own inflector is the only one used.
- **Default value for `attribute_convention`.** Previously defaulted to `:PascalCase`. The setting is now unset by default; reading `MyAPI::Settings.config.attribute_convention` directly returns `nil` unless explicitly configured. The effective default for naming conversion now lives on `conversions.json_attributes` (also `:PascalCase`).

## [1.0.0] - 2026-03-19

Initial release.

[Unreleased]: https://github.com/accodeing/rest-easy/compare/v1.4.1...HEAD
[1.4.1]: https://github.com/accodeing/rest-easy/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/accodeing/rest-easy/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/accodeing/rest-easy/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/accodeing/rest-easy/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/accodeing/rest-easy/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/accodeing/rest-easy/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/accodeing/rest-easy/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/accodeing/rest-easy/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/accodeing/rest-easy/releases/tag/v1.0.0
