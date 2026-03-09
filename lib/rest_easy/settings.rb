# frozen_string_literal: true

require "dry/configurable"

module RestEasy
  class Settings
    extend Dry::Configurable

    setting :base_url, default: "https://example.com", reader: true
    setting :max_retries, default: 3, reader: true
    setting :authentication, default: Auth::Null.new, reader: true
    setting :attribute_convention, default: :PascalCase, reader: true
  end
end
