# frozen_string_literal: true

require "base64"

module RestEasy
  module Auth
    class Basic
      def acquire(config)
        encoded = Base64.strict_encode64("#{config.username}:#{config.password}")
        { encoded: encoded }
      end

      def apply(credentials, request)
        request.headers["Authorization"] = "Basic #{credentials[:encoded]}"
      end

      def expired?(_credentials)
        false
      end

      def on_rejected(_credentials, _response)
        raise RestEasy::AuthenticationError, "Authentication failed"
      end
    end
  end
end
