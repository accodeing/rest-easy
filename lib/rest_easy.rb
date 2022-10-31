# frozen_string_literal: true
require 'rubygems'
require "dry/inflector"
require "dry/auto_inject"
require 'dry/types'
require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/__rest_easy")
loader.setup

module RestEasy
  Application.register('rest_easy.logger', ->(msg){ puts "RestEasy: #{msg}" })
  Application.register('rest_easy.loader', Loader)

  class Error < StandardError; end

  module Types
    include Dry.Types()
  end

  module ClassMethods
    def config
      self::Settings.config
    end
    def register(...)
      self::Application.register(...)
    end
    def resolve(...)
      self::Application.resolve(...)
    end
    alias :[] :resolve
  end

  class << self
    def extended(base)
      super
      # Make sure we are not allowing double registrations
      if base.const_defined?('Application')
        raise StandardError, "Double registration of #{base}, or you have a constant named 'Application' in your main module."
      end
      # "Clone" application class to give caller its own namespaced instance
      application = Class.new(Application)
      settings = Class.new(Settings)

      base.const_set('Deps', Dry::AutoInject(application))
      base.const_set('Application', application)
      base.const_set('Settings', settings)
      base.extend ClassMethods
    end
  end
end
