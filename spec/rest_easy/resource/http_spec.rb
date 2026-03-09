# frozen_string_literal: true

RSpec.describe "HTTP integration" do
  before(:all) do
    module HttpTestApi
      extend RestEasy

      configure do |config|
        config.base_url = "https://api.example.com/v1"
        config.max_retries = 3
      end
    end

    class HttpTestApi::Resource < RestEasy::Resource
      before_parse do |api_data|
        api_data[resource_name]
      end

      after_serialise do |api_data|
        { resource_name => api_data }
      end
    end

    class HttpTestApi::Invoice < HttpTestApi::Resource
      endpoint_path "invoices"

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
           '[{"Invoice": {"DocumentNumber": 1, "CustomerName": "Acme", "Amount": 100.0}},
             {"Invoice": {"DocumentNumber": 2, "CustomerName": "Beta", "Amount": 200.0}}]']
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
