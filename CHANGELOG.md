# Changelog

## [Unreleased]

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

[Unreleased]: https://github.com/accodeing/rest-easy/compare/v1.1.1...HEAD
[1.1.0]: https://github.com/accodeing/rest-easy/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/accodeing/rest-easy/releases/tag/v1.0.0
