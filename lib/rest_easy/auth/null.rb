# frozen_string_literal: true

module RestEasy
  module Auth
    # No-op auth for APIs that don't require authentication,
    # or when auth is handled at the transport level (e.g. mTLS).
    class Null
      def apply(request)
        # no-op
      end

      def on_rejected(response)
        raise RestEasy::RequestError.new(response)
      end
    end
  end
end
