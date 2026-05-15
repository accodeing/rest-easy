# frozen_string_literal: true

require "rubygems"
require "dry/types"
require "faraday"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/__rest_easy")
loader.ignore("#{__dir__}/rest_easy/__*.rb")
loader.inflector.inflect(
  "psk" => "PSK"
)
loader.setup

module RestEasy
  # Make Boolean available as a bare type constant (Ruby has no built-in Boolean)
  ::Object.const_set(:Boolean, Dry::Types["params.bool"]) unless defined?(::Boolean)

  # ── Error hierarchy ──────────────────────────────────────────────────

  class Error < StandardError; end
  class AttributeError < Error; end

  class MissingAttributeError < AttributeError
    attr_reader :attribute_name

    def initialize(attribute_name)
      @attribute_name = attribute_name
      super("Missing required attribute: #{attribute_name}")
    end
  end

  class ConstraintError < AttributeError
    attr_reader :attribute_name, :value

    def initialize(attribute_name, value, message = nil)
      @attribute_name = attribute_name
      @value = value
      super(message || "Constraint violation for attribute '#{attribute_name}' with value: #{value.inspect}")
    end
  end

  class RequestError < Error
    attr_reader :response

    def initialize(response_or_message = nil)
      if response_or_message.respond_to?(:status)
        @response = response_or_message
        super("Request failed: #{response_or_message.status}")
      else
        super(response_or_message)
      end
    end
  end
  class AuthenticationError < Error; end
  class RemoteServerError < Error; end
  class RateLimitError < Error; end

  # ── Types ────────────────────────────────────────────────────────────

  module Types
    include Dry.Types()
  end

  # ── Module extension (ClassMethods) ──────────────────────────────────

  module ClassMethods
    def config
      self::Settings.config
    end

    def settings(&block)
      self::Settings.class_eval(&block) if block_given?
    end

    def configure(&block)
      if block_given?
        if block.arity == 0
          dsl = Resource::ConfigureDSL.new(self::Settings.config)
          dsl.instance_eval(&block)
        else
          yield self::Settings.config
        end

        # BC: propagate deprecated attribute_convention to conversions, but
        # only on changes — so repeated `configure` calls don't re-warn and
        # don't clobber a `conversions.json_attributes` set in a later call.
        ac = self::Settings.config.attribute_convention
        if ac && @_propagated_attribute_convention != ac
          warn "RestEasy: attribute_convention is deprecated, use `conversions.json_attributes = #{ac.inspect}` instead"
          self::Settings.config.conversions.json_attributes = ac
          @_propagated_attribute_convention = ac
        end
      end
    end

    def connection(&block)
      if block_given?
        @connection_block = block
      end
      @connection_block
    end

    def faraday_connection
      @faraday_connection ||= Faraday.new(url: config.base_url) do |f|
        f.request :json
        f.response :json
        @connection_block&.call(f)
      end
    end

    def authentication
      config.authentication
    end

    # ── HTTP primitives ─────────────────────────────────────────────────

    def get(path:, params: {}, headers: {})
      request_with_auth(:get, path, params:, headers:)
    end

    def post(path:, body: nil, headers: {})
      request_with_auth(:post, path, body:, headers:)
    end

    def put(path:, body: nil, headers: {})
      request_with_auth(:put, path, body:, headers:)
    end

    def delete(path:, headers: {})
      request_with_auth(:delete, path, headers:)
    end

    private

    def request_with_auth(method, path, body: nil, params: {}, headers: {})
      auth = config.authentication
      max_retries = config.max_retries
      attempts = 0

      begin
        response = faraday_connection.run_request(method, path, body, nil) do |req|
          req.params.update(params) if params.any?
          headers.each { |k, v| req.headers[k] = v }
          auth.apply(req)
        end

        raise RequestError.new(response) unless response.success?
        response.body

      rescue RequestError => e
        attempts += 1
        if attempts <= max_retries
          auth.on_rejected(e.response)
          retry
        end
        raise
      end
    end

  end

  # ── Type bridge ─────────────────────────────────────────────────────
  # Make bare Ruby types work with Dry::Types features like `constrained`
  # inside Class.new blocks where constant lookup uses lexical scope.

  TYPE_BRIDGE = {
    ::String  => Types::Coercible::String,
    ::Integer => Types::Coercible::Integer,
    ::Float   => Types::Coercible::Float
  }.freeze

  [::String, ::Integer, ::Float].each do |klass|
    unless klass.respond_to?(:constrained)
      klass.define_singleton_method(:constrained) do |**opts|
        RestEasy::TYPE_BRIDGE[self].constrained(**opts)
      end
    end
  end

  # ── Module setup ─────────────────────────────────────────────────────

  CHECK_ANCESTORS = false

  class << self
    def extended(base)
      super

      # Guard against double registration and constant collisions
      if base.const_defined?(:ExtendedByRestEasy, CHECK_ANCESTORS)
        raise Error, "Double registration of #{base}."
      end

      if base.const_defined?(:Settings, CHECK_ANCESTORS)
        raise Error, "#{base} already defines Settings. RestEasy needs this constant."
      end

      # Clone settings so each API module gets its own config state.
      settings = Class.new(Settings)

      base.const_set(:Settings, settings)
      base.const_set(:ExtendedByRestEasy, true)
      base.extend ClassMethods
    end
  end
end
