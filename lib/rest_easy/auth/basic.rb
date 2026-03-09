# frozen_string_literal: true

require "base64"

module RestEasy
  module Auth
    # HTTP Basic authentication.
    # Encodes username:password as Base64 and sets the Authorization header.
    class Basic
      def initialize(username:, password:)
        @encoded = Base64.strict_encode64("#{username}:#{password}")
      end

      def apply(request)
        request.headers["Authorization"] = "Basic #{@encoded}"
      end

      def on_rejected(response)
        raise RestEasy::AuthenticationError, "Authentication failed: #{response.status}"
      end
    end
  end
end
