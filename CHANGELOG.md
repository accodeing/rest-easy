# Changelog

## [Unreleased]

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

## [1.0.0]

Initial release.
