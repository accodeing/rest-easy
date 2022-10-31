require 'dry/configurable'

module RestEasy
  class Settings
    extend Dry::Configurable

    settings do
      setting :host, default: 'https://example.com', reader: true
      setting :url_prefix, default: '/api', reader: true

      setting :path, reader: true
      setting :faraday, reader: true do
        setting :request do
          setting :timeout, default: 5
        end
      end
    end
  end
end
