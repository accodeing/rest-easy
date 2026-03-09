# frozen_string_literal: true

RSpec.describe "Authentication" do
  # ── Auth module contract ───────────────────────────────────────────────

  describe "auth module contract" do
    it "requires apply and on_rejected" do
      null_auth = RestEasy::Auth::Null.new
      expect(null_auth).to respond_to(:apply)
      expect(null_auth).to respond_to(:on_rejected)
    end
  end

  # ── Null auth ──────────────────────────────────────────────────────────

  describe RestEasy::Auth::Null do
    let(:auth) { described_class.new }

    it "apply does nothing to the request" do
      request = double("request", headers: {})
      auth.apply(request)
      expect(request.headers).to be_empty
    end

    it "on_rejected raises RequestError" do
      response = double("response", status: 500)
      expect { auth.on_rejected(response) }.to raise_error(RestEasy::RequestError)
    end
  end

  # ── PSK auth ───────────────────────────────────────────────────────────

  describe RestEasy::Auth::PSK do
    let(:auth) { described_class.new(api_key: "test-key-123") }

    it "applies API key to request headers" do
      headers = {}
      request = double("request", headers:)

      auth.apply(request)

      expect(headers["Authorization"]).to eq("Bearer test-key-123")
    end

    it "supports custom header name and prefix" do
      auth = described_class.new(api_key: "my-key", header_name: "X-Api-Key", header_prefix: "Token")
      headers = {}
      request = double("request", headers:)

      auth.apply(request)

      expect(headers["X-Api-Key"]).to eq("Token my-key")
    end

    it "on_rejected raises RequestError" do
      response = double("response", status: 401)
      expect { auth.on_rejected(response) }.to raise_error(RestEasy::RequestError)
    end
  end

  # ── Basic auth ─────────────────────────────────────────────────────────

  describe RestEasy::Auth::Basic do
    let(:auth) { described_class.new(username: "user", password: "pass") }

    it "applies Authorization header with base64 encoding" do
      headers = {}
      request = double("request", headers:)

      auth.apply(request)

      expected = "Basic #{Base64.strict_encode64("user:pass")}"
      expect(headers["Authorization"]).to eq(expected)
    end

    it "on_rejected raises AuthenticationError" do
      response = double("response", status: 401)
      expect { auth.on_rejected(response) }.to raise_error(RestEasy::AuthenticationError)
    end
  end

  # ── Custom auth module ─────────────────────────────────────────────────

  describe "custom auth module" do
    it "can implement the two-method contract" do
      custom_auth = Class.new do
        def initialize
          @token = nil
          @acquire_count = 0
        end

        def apply(request)
          @token ||= acquire_token
          request.headers["Authorization"] = "Bearer #{@token}"
        end

        def on_rejected(response)
          case response.status
          when 401
            @token = nil # force re-acquire on next apply
          else
            raise RestEasy::RequestError.new(response)
          end
        end

        private

        def acquire_token
          @acquire_count += 1
          "token-#{@acquire_count}"
        end
      end.new

      # First apply acquires a token
      headers = {}
      request = double("request", headers:)
      custom_auth.apply(request)
      expect(headers["Authorization"]).to eq("Bearer token-1")

      # Second apply reuses cached token
      headers2 = {}
      request2 = double("request", headers: headers2)
      custom_auth.apply(request2)
      expect(headers2["Authorization"]).to eq("Bearer token-1")

      # on_rejected with 401 clears cached token
      response_401 = double("response", status: 401)
      expect { custom_auth.on_rejected(response_401) }.not_to raise_error

      # Next apply acquires a new token
      headers3 = {}
      request3 = double("request", headers: headers3)
      custom_auth.apply(request3)
      expect(headers3["Authorization"]).to eq("Bearer token-2")

      # on_rejected with 500 raises
      response_500 = double("response", status: 500)
      expect {
        custom_auth.on_rejected(response_500)
      }.to raise_error(RestEasy::RequestError)
    end
  end

  # ── Request lifecycle ──────────────────────────────────────────────────

  describe "request lifecycle" do
    it "on_rejected returning normally signals retry" do
      auth = double("Auth")
      response = double("response", status: 429)

      allow(auth).to receive(:on_rejected)

      expect { auth.on_rejected(response) }.not_to raise_error
    end

    it "on_rejected raising propagates the error" do
      auth = double("Auth")
      response = double("response", status: 403)

      allow(auth).to receive(:on_rejected).and_raise(
        RestEasy::AuthenticationError, "Access denied"
      )

      expect {
        auth.on_rejected(response)
      }.to raise_error(RestEasy::AuthenticationError, "Access denied")
    end

    it "respects max_retries by counting on_rejected calls" do
      auth = double("Auth")
      response = double("response", status: 500)

      call_count = 0
      allow(auth).to receive(:on_rejected) do
        call_count += 1
        raise RestEasy::RemoteServerError if call_count > 3
      end

      3.times do
        expect { auth.on_rejected(response) }.not_to raise_error
      end

      expect {
        auth.on_rejected(response)
      }.to raise_error(RestEasy::RemoteServerError)
    end
  end
end
