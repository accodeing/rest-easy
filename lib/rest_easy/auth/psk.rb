# frozen_string_literal: true

module RestEasy
  module Auth
    class PSK
      def acquire(config)
        {
          api_key: config.api_key,
          header_name: config.respond_to?(:header_name) ? config.header_name : "Authorization",
          header_prefix: config.respond_to?(:header_prefix) ? config.header_prefix : "Bearer"
        }
      end

      def apply(credentials, request)
        header_name = credentials[:header_name] || "Authorization"
        header_prefix = credentials[:header_prefix] || "Bearer"
        request.headers[header_name] = "#{header_prefix} #{credentials[:api_key]}"
      end

      def expired?(_credentials)
        false
      end

      def on_rejected(_credentials, _response)
        raise RestEasy::RequestError, "Request failed"
      end
    end
  end
end
