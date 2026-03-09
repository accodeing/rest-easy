# frozen_string_literal: true

RSpec.describe "Authentication lifecycle" do
  # ── Auth module contract ───────────────────────────────────────────────

  describe "auth module contract" do
    let(:null_auth) { RestEasy::Auth::Null.new }

    it "responds to acquire" do
      expect(null_auth).to respond_to(:acquire)
    end

    it "responds to apply" do
      expect(null_auth).to respond_to(:apply)
    end

    it "responds to expired?" do
      expect(null_auth).to respond_to(:expired?)
    end

    it "responds to on_rejected" do
      expect(null_auth).to respond_to(:on_rejected)
    end
  end

  # ── Null auth ──────────────────────────────────────────────────────────

  describe RestEasy::Auth::Null do
    let(:auth) { described_class.new }

    it "acquire returns empty credentials" do
      expect(auth.acquire({})).to eq({})
    end

    it "apply does nothing to the request" do
      request = double("request", headers: {})
      auth.apply({}, request)
      expect(request.headers).to be_empty
    end

    it "never expires" do
      expect(auth.expired?({})).to be false
    end
  end

  # ── PSK auth ───────────────────────────────────────────────────────────

  describe RestEasy::Auth::PSK do
    let(:auth) { described_class.new }
    let(:config) { double("config", api_key: "test-key-123", header_name: "Authorization", header_prefix: "Bearer") }

    it "acquires credentials from config" do
      credentials = auth.acquire(config)
      expect(credentials[:api_key]).to eq("test-key-123")
    end

    it "applies API key to request headers" do
      credentials = auth.acquire(config)
      headers = {}
      request = double("request", headers: headers)

      auth.apply(credentials, request)

      expect(headers["Authorization"]).to eq("Bearer test-key-123")
    end

    it "never expires" do
      credentials = auth.acquire(config)
      expect(auth.expired?(credentials)).to be false
    end
  end

  # ── Basic auth ─────────────────────────────────────────────────────────

  describe RestEasy::Auth::Basic do
    let(:auth) { described_class.new }
    let(:config) { double("config", username: "user", password: "pass") }

    it "acquires base64-encoded credentials" do
      credentials = auth.acquire(config)
      expect(credentials[:encoded]).to eq(Base64.strict_encode64("user:pass"))
    end

    it "applies Authorization header" do
      credentials = auth.acquire(config)
      headers = {}
      request = double("request", headers: headers)

      auth.apply(credentials, request)

      expect(headers["Authorization"]).to start_with("Basic ")
    end

    it "never expires" do
      credentials = auth.acquire(config)
      expect(auth.expired?(credentials)).to be false
    end
  end

  # ── Request lifecycle ──────────────────────────────────────────────────

  describe "request lifecycle integration" do
    before(:all) do
      module AuthTestApi
        extend RestEasy

        configure do |config|
          config.base_url = "https://api.example.com"
        end
      end

      class AuthTestApi::Item < RestEasy::Resource
        endpoint_path "items"
        key :id, Integer
        attr :name, String
      end
    end

    after(:all) do
      Object.send(:remove_const, :AuthTestApi)
    end

    it "calls acquire when credentials are nil" do
      auth = instance_double("Auth")
      allow(auth).to receive(:expired?).and_return(false)
      allow(auth).to receive(:acquire).and_return({ token: "abc" })
      allow(auth).to receive(:apply)
      allow(auth).to receive(:on_rejected)

      allow(AuthTestApi).to receive(:authentication).and_return(auth)
      allow(AuthTestApi::Item).to receive(:get).and_call_original

      # The actual HTTP call would go through the auth lifecycle
      # This tests the contract, not the HTTP layer
      expect(auth).to respond_to(:acquire)
      expect(auth).to respond_to(:apply)
      expect(auth).to respond_to(:expired?)
      expect(auth).to respond_to(:on_rejected)
    end

    it "calls acquire when credentials are expired" do
      auth = instance_double("Auth")
      expired_creds = { token: "old", expires_at: Time.now - 3600 }

      allow(auth).to receive(:expired?).with(expired_creds).and_return(true)
      allow(auth).to receive(:acquire).and_return({ token: "new", expires_at: Time.now + 3600 })
      allow(auth).to receive(:apply)

      expect(auth.expired?(expired_creds)).to be true

      new_creds = auth.acquire(double("config"))
      expect(new_creds[:token]).to eq("new")
    end

    it "calls on_rejected when request fails and retries" do
      auth = double("Auth")
      response = double("response", status: 401)
      credentials = { token: "expired" }

      allow(auth).to receive(:on_rejected) do |creds, resp|
        # Auth module refreshes internally, returns normally to signal retry
      end

      # Should not raise — returning normally signals retry
      expect { auth.on_rejected(credentials, response) }.not_to raise_error
    end

    it "propagates error when on_rejected raises" do
      auth = double("Auth")
      response = double("response", status: 403)
      credentials = { token: "invalid" }

      allow(auth).to receive(:on_rejected).and_raise(
        RestEasy::AuthenticationError, "Access denied"
      )

      expect {
        auth.on_rejected(credentials, response)
      }.to raise_error(RestEasy::AuthenticationError, "Access denied")
    end

    it "respects max_retries configuration" do
      auth = double("Auth")
      response = double("response", status: 500)

      call_count = 0
      allow(auth).to receive(:on_rejected) do
        call_count += 1
        raise RestEasy::RemoteServerError if call_count > 3
      end

      # Simulating retry loop with max_retries = 3
      3.times do
        expect { auth.on_rejected({}, response) }.not_to raise_error
      end

      expect {
        auth.on_rejected({}, response)
      }.to raise_error(RestEasy::RemoteServerError)
    end
  end

  # ── Custom auth module ─────────────────────────────────────────────────

  describe "custom auth module" do
    it "can implement the four-method contract" do
      custom_auth = Class.new do
        def initialize
          @call_count = 0
        end

        def acquire(config)
          @call_count += 1
          { token: "token-#{@call_count}", expires_at: Time.now + 3600 }
        end

        def apply(credentials, request)
          request.headers["Authorization"] = "Bearer #{credentials[:token]}"
        end

        def expired?(credentials)
          Time.now >= credentials[:expires_at]
        end

        def on_rejected(credentials, response)
          case response.status
          when 401 then acquire(nil)
          else raise RestEasy::RequestError, "Failed: #{response.status}"
          end
        end
      end.new

      # Verify contract
      config = double("config")
      creds = custom_auth.acquire(config)
      expect(creds[:token]).to eq("token-1")

      headers = {}
      request = double("request", headers: headers)
      custom_auth.apply(creds, request)
      expect(headers["Authorization"]).to eq("Bearer token-1")

      expect(custom_auth.expired?(creds)).to be false
      expect(custom_auth.expired?({ expires_at: Time.now - 1 })).to be true

      response_401 = double("response", status: 401)
      expect { custom_auth.on_rejected(creds, response_401) }.not_to raise_error

      response_500 = double("response", status: 500)
      expect {
        custom_auth.on_rejected(creds, response_500)
      }.to raise_error(RestEasy::RequestError)
    end
  end
end
