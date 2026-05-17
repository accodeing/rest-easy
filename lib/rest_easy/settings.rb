# frozen_string_literal: true

require "dry/configurable"

module RestEasy
  class Settings
    extend Dry::Configurable

    setting :attribute_convention # deprecated — propagated to conversions.json_attributes in configure
    setting :authentication, default: Auth::Null.new, reader: true
    setting :base_url, default: "https://example.com", reader: true
    setting :log_bodies, default: false, reader: true
    setting :logger, reader: true
    setting :max_retries, default: 3, reader: true

    setting :conversions do
      setting :json_attributes, default: Conventions::DEFAULT, reader: true
      setting :query_parameters, default: nil, reader: true
    end
  end
end
