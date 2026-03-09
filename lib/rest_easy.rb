# frozen_string_literal: true

require "rubygems"
require "dry/inflector"
require "dry/auto_inject"
require "dry/types"
require "faraday"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/__rest_easy")
loader.inflector.inflect(
  "psk" => "PSK"
)
loader.setup

module RestEasy
  Application.register("rest_easy.logger", ->(msg) { puts "RestEasy: #{msg}" })
  Application.register("rest_easy.loader", Loader)

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

    def configure
      yield self::Settings.config if block_given?
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

    def get(path:, params: {})
      request_with_auth(:get, path, params:)
    end

    def post(path:, body: nil)
      request_with_auth(:post, path, body:)
    end

    def put(path:, body: nil)
      request_with_auth(:put, path, body:)
    end

    def delete(path:)
      request_with_auth(:delete, path)
    end

    private

    def request_with_auth(method, path, body: nil, params: {})
      auth = config.authentication
      max_retries = config.max_retries
      attempts = 0

      begin
        response = faraday_connection.run_request(method, path, body, nil) do |req|
          req.params.update(params) if params.any?
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

    public

    def register(...)
      self::Application.register(...)
    end

    def resolve(...)
      self::Application.resolve(...)
    end

    alias_method :[], :resolve
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

  class << self
    def extended(base)
      super
      # Make sure we are not allowing double registrations
      if base.const_defined?("Application")
        raise StandardError, "Double registration of #{base}, or you have a constant named 'Application' in your main module."
      end
      # "Clone" application class to give caller its own namespaced instance
      application = Class.new(Application)
      settings = Class.new(Settings)

      base.const_set("Deps", Dry::AutoInject(application))
      base.const_set("Application", application)
      base.const_set("Settings", settings)
      base.const_set("ExtendedByRestEasy", true)
      base.extend ClassMethods
    end
  end
end
