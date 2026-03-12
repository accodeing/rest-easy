# frozen_string_literal: true

require "dry-struct"

module RestEasy
  # Base class for embedded value objects (e.g. InvoiceRow, EDIInformation).
  # These are nested data structures within a Resource, not standalone API resources.
  class Model < Dry::Struct
    transform_keys(&:to_sym)
  end
end
