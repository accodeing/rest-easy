# frozen_string_literal: true

RSpec.describe "HTTP integration" do
  before(:all) do
    module HttpTestApi
      extend RestEasy

      configure do |config|
        config.base_url = "https://api.example.com/v1"
        config.max_retries = 3
        config.conversions.json_attributes = :PascalCase
      end
    end

    class HttpTestApi::Resource < RestEasy::Resource
      settings do
        setting :wrapper_name
        setting :collection_wrapper_name
      end

      before_parse do |api_data|
        api_data[config.wrapper_name] || api_data[config.collection_wrapper_name]
      end

      after_serialise do |api_data|
        { config.wrapper_name => api_data }
      end
    end

    class HttpTestApi::Invoice < HttpTestApi::Resource
      configure do
        path "invoices"
        wrapper_name "Invoice"
        collection_wrapper_name "Invoices"
      end

      key :document_number, Integer, :read_only
      attr :customer_name, String
      attr :amount, Float
    end
  end

  after(:all) do
    Object.send(:remove_const, :HttpTestApi)
  end

  # Helper to set up a Faraday test adapter with stubs
  def setup_test_connection(api_module, &block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    api_module.instance_variable_set(:@faraday_connection, nil) # reset cached connection
    api_module.connection do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.adapter :test, stubs
    end
    stubs
  end

  # ── GET ──────────────────────────────────────────────────────────────

  describe "GET requests" do
    it "fetches a resource by id" do
      setup_test_connection(HttpTestApi) do |stub|
        stub.get("/v1/invoices/123") do
          [200, { "Content-Type" => "application/json" },
           '{"Invoice": {"DocumentNumber": 123, "CustomerName": "Acme", "Amount": 500.0}}']
        end
      end

      invoice = HttpTestApi::Invoice.find(123)

      expect(invoice.document_number).to eq(123)
      expect(invoice.customer_name).to eq("Acme")
      expect(invoice.amount).to eq(500.0)
      expect(invoice.meta.new?).to be false
    end

    it "fetches all resources" do
      setup_test_connection(HttpTestApi) do |stub|
        stub.get("/v1/invoices") do
          [200, { "Content-Type" => "application/json" },
           '{"Invoices": [{"DocumentNumber": 1, "CustomerName": "Acme", "Amount": 100.0},
             {"DocumentNumber": 2, "CustomerName": "Beta", "Amount": 200.0}]}']
        end
      end

      invoices = HttpTestApi::Invoice.all

      expect(invoices.length).to eq(2)
      expect(invoices[0].customer_name).to eq("Acme")
      expect(invoices[1].customer_name).to eq("Beta")
    end
  end

  # ── POST ─────────────────────────────────────────────────────────────

  describe "POST requests" do
    it "creates a new resource" do
      setup_test_connection(HttpTestApi) do |stub|
        stub.post("/v1/invoices") do |env|
          body = JSON.parse(env.body)
          expect(body["Invoice"]["CustomerName"]).to eq("New Corp")

          [201, { "Content-Type" => "application/json" },
           '{"Invoice": {"DocumentNumber": 456, "CustomerName": "New Corp", "Amount": 300.0}}']
        end
      end

      instance = HttpTestApi::Invoice.stub(customer_name: "New Corp", amount: 300.0)
      saved = HttpTestApi::Invoice.save(instance)

      expect(saved.document_number).to eq(456)
      expect(saved.meta.new?).to be false
    end
  end

  # ── PUT ──────────────────────────────────────────────────────────────

  describe "PUT requests" do
    it "updates an existing resource" do
      setup_test_connection(HttpTestApi) do |stub|
        stub.get("/v1/invoices/123") do
          [200, { "Content-Type" => "application/json" },
           '{"Invoice": {"DocumentNumber": 123, "CustomerName": "Acme", "Amount": 500.0}}']
        end
        stub.put("/v1/invoices/123") do
          [200, { "Content-Type" => "application/json" },
           '{"Invoice": {"DocumentNumber": 123, "CustomerName": "Acme", "Amount": 600.0}}']
        end
      end

      invoice = HttpTestApi::Invoice.find(123)
      updated = invoice.update(amount: 600.0)
      saved = HttpTestApi::Invoice.save(updated)

      expect(saved.amount).to eq(600.0)
    end
  end

  # ── DELETE ───────────────────────────────────────────────────────────

  describe "DELETE requests" do
    it "deletes a resource by id" do
      delete_called = false

      setup_test_connection(HttpTestApi) do |stub|
        stub.delete("/v1/invoices/123") do
          delete_called = true
          [204, {}, ""]
        end
      end

      HttpTestApi::Invoice.delete(123)

      expect(delete_called).to be true
    end
  end

  # ── Auth integration ─────────────────────────────────────────────────

  describe "auth integration" do
    it "calls apply on every request" do
      apply_count = 0
      auth = Class.new do
        define_method(:apply) do |request|
          apply_count += 1
          request.headers["Authorization"] = "Bearer test-token"
        end

        def on_rejected(response)
          raise RestEasy::RequestError.new(response)
        end
      end.new

      HttpTestApi.configure { |c| c.authentication = auth }

      setup_test_connection(HttpTestApi) do |stub|
        stub.get("/v1/invoices/1") do |env|
          expect(env.request_headers["Authorization"]).to eq("Bearer test-token")
          [200, { "Content-Type" => "application/json" },
           '{"Invoice": {"DocumentNumber": 1, "CustomerName": "Test", "Amount": 0.0}}']
        end
        stub.get("/v1/invoices/2") do |env|
          expect(env.request_headers["Authorization"]).to eq("Bearer test-token")
          [200, { "Content-Type" => "application/json" },
           '{"Invoice": {"DocumentNumber": 2, "CustomerName": "Test2", "Amount": 0.0}}']
        end
      end

      HttpTestApi::Invoice.find(1)
      HttpTestApi::Invoice.find(2)

      expect(apply_count).to eq(2)
    ensure
      HttpTestApi.configure { |c| c.authentication = RestEasy::Auth::Null.new }
    end

    it "retries when on_rejected returns normally" do
      attempt = 0
      auth = Class.new do
        def apply(request)
          request.headers["Authorization"] = "Bearer token"
        end

        define_method(:on_rejected) do |response|
          # return normally to signal retry
        end
      end.new

      HttpTestApi.configure { |c| c.authentication = auth }

      setup_test_connection(HttpTestApi) do |stub|
        stub.get("/v1/invoices/1") do
          attempt += 1
          if attempt < 3
            [500, {}, "Server Error"]
          else
            [200, { "Content-Type" => "application/json" },
             '{"Invoice": {"DocumentNumber": 1, "CustomerName": "Test", "Amount": 0.0}}']
          end
        end
      end

      invoice = HttpTestApi::Invoice.find(1)
      expect(invoice.document_number).to eq(1)
      expect(attempt).to eq(3)
    ensure
      HttpTestApi.configure { |c| c.authentication = RestEasy::Auth::Null.new }
    end

    it "propagates error when on_rejected raises" do
      auth = Class.new do
        def apply(request); end

        def on_rejected(response)
          raise RestEasy::AuthenticationError, "Access denied"
        end
      end.new

      HttpTestApi.configure { |c| c.authentication = auth }

      setup_test_connection(HttpTestApi) do |stub|
        stub.get("/v1/invoices/1") do
          [401, {}, "Unauthorized"]
        end
      end

      expect {
        HttpTestApi::Invoice.find(1)
      }.to raise_error(RestEasy::AuthenticationError, "Access denied")
    ensure
      HttpTestApi.configure { |c| c.authentication = RestEasy::Auth::Null.new }
    end

    it "stops retrying after max_retries" do
      on_rejected_count = 0
      auth = Class.new do
        def apply(request); end

        define_method(:on_rejected) do |response|
          on_rejected_count += 1
          # always return normally to keep retrying
        end
      end.new

      HttpTestApi.configure do |c|
        c.authentication = auth
        c.max_retries = 2
      end

      setup_test_connection(HttpTestApi) do |stub|
        stub.get("/v1/invoices/1") do
          [500, {}, "Server Error"]
        end
      end

      expect {
        HttpTestApi::Invoice.find(1)
      }.to raise_error(RestEasy::RequestError)

      expect(on_rejected_count).to eq(2)
    ensure
      HttpTestApi.configure do |c|
        c.authentication = RestEasy::Auth::Null.new
        c.max_retries = 3
      end
    end
  end

  # ── Transient errors ─────────────────────────────────────────────────

  describe "retry_transient_errors" do
    let(:rejected) { [] }
    let(:auth) do
      rejected_statuses = rejected
      Class.new do
        def apply(request); end

        define_method(:on_rejected) do |response|
          rejected_statuses << response.status
          raise RestEasy::RequestError.new(response)
        end
      end.new
    end
    let(:invoice) { '{"Invoice": {"DocumentNumber": 1, "CustomerName": "Test", "Amount": 0.0}}' }

    def respond_with(*responses, method: :get)
      setup_test_connection(HttpTestApi) do |stub|
        stub.public_send(method, "/v1/invoices/1") do
          response = responses.shift
          raise response if response.is_a?(Exception)

          response
        end
      end
    end

    before do
      HttpTestApi.configure do |c|
        c.authentication = auth
        c.retry_transient_errors = true
      end
      allow(Kernel).to receive(:sleep)
    end

    after do
      HttpTestApi.configure do |c|
        c.authentication = RestEasy::Auth::Null.new
        c.retry_transient_errors = false
      end
    end

    it "is off by default" do
      expect(RestEasy::Settings.config.retry_transient_errors).to be(false)
    end

    it "retries a 5xx without asking the authentication" do
      respond_with([500, {}, "Error"], [200, { "Content-Type" => "application/json" }, invoice])

      expect(HttpTestApi::Invoice.find(1).document_number).to eq(1)
      expect(rejected).to be_empty
      expect(Kernel).to have_received(:sleep).with(RestEasy::DEFAULT_RETRY_AFTER_IN_SECONDS)
    end

    it "waits for Retry-After before retrying a 503" do
      respond_with([503, { "Retry-After" => "3" }, ""], [200, { "Content-Type" => "application/json" }, invoice])

      HttpTestApi::Invoice.find(1)

      expect(Kernel).to have_received(:sleep).with(3)
      expect(rejected).to be_empty
    end

    it "waits for Retry-After before retrying a 429" do
      respond_with([429, { "Retry-After" => "2" }, ""], [200, { "Content-Type" => "application/json" }, invoice])

      HttpTestApi::Invoice.find(1)

      expect(Kernel).to have_received(:sleep).with(2)
      expect(rejected).to be_empty
    end

    it "waits a default time on a 429 without Retry-After" do
      respond_with([429, {}, ""], [200, { "Content-Type" => "application/json" }, invoice])

      HttpTestApi::Invoice.find(1)

      expect(Kernel).to have_received(:sleep).with(RestEasy::DEFAULT_RETRY_AFTER_IN_SECONDS)
    end

    it "reads Retry-After as a date" do
      now = Time.utc(2026, 1, 1, 12, 0, 0) + 0.5
      allow(Time).to receive(:now).and_return(now)
      respond_with([429, { "Retry-After" => (now + 5).httpdate }, ""],
                   [200, { "Content-Type" => "application/json" }, invoice])

      HttpTestApi::Invoice.find(1)

      expect(Kernel).to have_received(:sleep).with(5)
    end

    it "does not wait for a Retry-After date in the past" do
      respond_with([429, { "Retry-After" => (Time.now - 60).httpdate }, ""],
                   [200, { "Content-Type" => "application/json" }, invoice])

      HttpTestApi::Invoice.find(1)

      expect(Kernel).to have_received(:sleep).with(0)
    end

    it "reads Retry-After in base 10" do
      respond_with([429, { "Retry-After" => "010" }, ""], [200, { "Content-Type" => "application/json" }, invoice])

      HttpTestApi::Invoice.find(1)

      expect(Kernel).to have_received(:sleep).with(10)
    end

    it "raises without retrying when Retry-After is over the max" do
      wait = RestEasy::MAX_RETRY_AFTER_IN_SECONDS + 1
      respond_with([429, { "Retry-After" => wait.to_s }, ""])

      expect { HttpTestApi::Invoice.find(1) }.to raise_error(RestEasy::RequestError, "Request failed: 429")
      expect(Kernel).not_to have_received(:sleep)
      expect(rejected).to be_empty
    end

    %i[put delete].each do |method|
      it "retries a 5xx on #{method.upcase}" do
        respond_with([503, {}, ""], [204, {}, ""], method:)

        HttpTestApi.public_send(method, path: "invoices/1")

        expect(rejected).to be_empty
      end
    end

    it "retries a 429 on POST" do
      respond_with([429, {}, ""], [204, {}, ""], method: :post)

      HttpTestApi.post(path: "invoices/1")

      expect(rejected).to be_empty
    end

    it "passes a 5xx on POST to the authentication" do
      respond_with([503, {}, ""], method: :post)

      expect { HttpTestApi.post(path: "invoices/1") }.to raise_error(RestEasy::RequestError)
      expect(rejected).to eq([503])
      expect(Kernel).not_to have_received(:sleep)
    end

    [Faraday::TimeoutError, Faraday::ConnectionFailed].each do |error|
      it "retries a #{error} on GET" do
        respond_with(error.new("network"), [200, { "Content-Type" => "application/json" }, invoice])

        expect(HttpTestApi::Invoice.find(1).document_number).to eq(1)
        expect(Kernel).to have_received(:sleep).with(RestEasy::DEFAULT_RETRY_AFTER_IN_SECONDS)
        expect(rejected).to be_empty
      end

      %i[put delete].each do |method|
        it "retries a #{error} on #{method.upcase}" do
          respond_with(error.new("network"), [204, {}, ""], method:)

          HttpTestApi.public_send(method, path: "invoices/1")

          expect(Kernel).to have_received(:sleep).once
        end
      end

      it "raises a #{error} on POST without retrying" do
        respond_with(error.new("network"), method: :post)

        expect { HttpTestApi.post(path: "invoices/1") }.to raise_error(error)
        expect(Kernel).not_to have_received(:sleep)
        expect(rejected).to be_empty
      end

      it "raises a #{error} once max_retries is used up" do
        respond_with(*Array.new(4) { error.new("network") })

        expect { HttpTestApi::Invoice.find(1) }.to raise_error(error)
        expect(Kernel).to have_received(:sleep).exactly(3).times
      end

      it "raises a #{error} without retrying when turned off" do
        HttpTestApi.configure { |c| c.retry_transient_errors = false }
        respond_with(error.new("network"))

        expect { HttpTestApi::Invoice.find(1) }.to raise_error(error)
        expect(Kernel).not_to have_received(:sleep)
        expect(rejected).to be_empty
      end
    end

    context "when the authentication raises a RequestError without a response" do
      let(:auth) do
        rejected_responses = rejected
        Class.new do
          def apply(_request)
            raise RestEasy::RequestError, "No credentials"
          end

          define_method(:on_rejected) do |response|
            rejected_responses << response
            raise RestEasy::RequestError, "Rejected"
          end
        end.new
      end

      it "passes it to the authentication" do
        respond_with([200, { "Content-Type" => "application/json" }, invoice])

        expect { HttpTestApi::Invoice.find(1) }.to raise_error(RestEasy::RequestError, "Rejected")
        expect(rejected).to eq([nil])
      end
    end

    it "still passes other failures to the authentication" do
      respond_with([401, {}, "Unauthorized"])

      expect { HttpTestApi::Invoice.find(1) }.to raise_error(RestEasy::RequestError)
      expect(rejected).to eq([401])
    end

    it "raises once max_retries is used up" do
      respond_with(*Array.new(4) { [503, {}, "Unavailable"] })

      expect { HttpTestApi::Invoice.find(1) }.to raise_error(RestEasy::RequestError, "Request failed: 503")
      expect(Kernel).to have_received(:sleep).exactly(3).times
      expect(rejected).to be_empty
    end

    it "passes transient errors to the authentication when turned off" do
      HttpTestApi.configure { |c| c.retry_transient_errors = false }
      respond_with([503, {}, "Unavailable"])

      expect { HttpTestApi::Invoice.find(1) }.to raise_error(RestEasy::RequestError)
      expect(rejected).to eq([503])
    end
  end

  # ── Connection configuration ─────────────────────────────────────────

  describe "connection block" do
    it "configures the Faraday connection" do
      middleware_applied = false

      HttpTestApi.instance_variable_set(:@faraday_connection, nil)
      HttpTestApi.connection do |f|
        middleware_applied = true
        f.adapter :test, Faraday::Adapter::Test::Stubs.new { |s|
          s.get("/v1/invoices/1") do
            [200, { "Content-Type" => "application/json" },
             '{"Invoice": {"DocumentNumber": 1, "CustomerName": "Test", "Amount": 0.0}}']
          end
        }
        f.response :json, content_type: /\bjson$/
      end

      HttpTestApi::Invoice.find(1)
      expect(middleware_applied).to be true
    ensure
      HttpTestApi.instance_variable_set(:@faraday_connection, nil)
      HttpTestApi.instance_variable_set(:@connection_block, nil)
    end
  end
end
