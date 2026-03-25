# frozen_string_literal: true

require "dry/configurable"

module RestEasy
  class Settings
    extend Dry::Configurable

    setting :base_url, default: "https://example.com", reader: true
    setting :max_retries, default: 3, reader: true
    setting :authentication, default: Auth::Null.new, reader: true
    setting :attribute_convention, default: :PascalCase, reader: true # deprecated, kept for BC

    setting :conversions do
      setting :query_parameters, default: :snake_case, reader: true
      setting :json_attributes, default: :snake_case, reader: true
    end
  end
end
