# frozen_string_literal: true

module RestEasy
  module Auth
    class Null
      def acquire(_config)
        {}
      end

      def apply(_credentials, _request)
        # no-op
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
