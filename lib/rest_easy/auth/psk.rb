# frozen_string_literal: true

module RestEasy
  module Auth
    # Pre-shared key (API key) authentication.
    # Applies a static key as a request header.
    class PSK
      def initialize(api_key:, header_name: "Authorization", header_prefix: "Bearer")
        @api_key = api_key
        @header_name = header_name
        @header_prefix = header_prefix
      end

      def apply(request)
        request.headers[@header_name] = "#{@header_prefix} #{@api_key}"
      end

      def on_rejected(response)
        raise RestEasy::RequestError.new(response)
      end
    end
  end
end
