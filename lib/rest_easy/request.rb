require 'dry/configurable'
require 'faraday'
require 'ostruct'

module RestEasy
  class Request
    extend Dry::Configurable
    extend Registry

    include Deps[
      loader:,
      mapper:,
    ]

    setting :host, reader: true
    setting :url_prefix, reader: true

    setting :path, reader: true
    setting :faraday, reader: true do
      setting :request do
        setting :timeout, default: 5
      end
    end

    def initialize( id )
      @id = id
      @connection = Faraday.new( config.host, config.faraday.values )
      yield @connection if block_given?

      (api_values, model_values) = attributes.each.with_object([{},{}]) do |attribute, (api, model)|
        api[attribute[:api]] = nil
        model[attribute[:model]] = nil
      end

      @api = OpenStruct.new(api_values)
      @model = OpenStruct.new(model_values)

      load
    end

    def self.attribute( api_name, model_name, type )
      @__attributes ||= []

      @__attributes << Attribute.new(
        api_name: api_name,
        model_name: model_name,
        type: type
      )
    end

    def self.__attributes
      @__attributes
    end

    def attributes
      self.class.__attributes
    end

    def self.find( id )
      new( id )
    end

  private

    def load
      res = @connection.get( "#{config.url_prefix}#{config.path}/#{@id}" )
      if res.status == 200
        res.body.each do |(key, value)|
          attribute = attributes.find{|a| a[:api] == key.to_sym}
          next unless attribute
          @api[attribute[:api]] = value
          @model[attribute[:model]] = value
        end
      else
        raise StandardError("Request failed: #{res.status}")
      end
    end

    def config
      self.class.config
    end

  end
end
