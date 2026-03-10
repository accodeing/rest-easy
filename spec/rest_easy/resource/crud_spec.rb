# frozen_string_literal: true

RSpec.describe "Resource CRUD operations" do
  before(:all) do
    module CrudTestApi
      extend RestEasy

      configure do |config|
        config.base_url = "https://api.example.com/v1"
        config.attribute_convention = :PascalCase
        config.max_retries = 3
      end
    end

    class CrudTestApi::Resource < RestEasy::Resource
      settings do
        setting :wrapper_name
      end

      before_parse do |api_data|
        api_data[config.wrapper_name]
      end

      after_serialise do |api_data|
        { config.wrapper_name => api_data }
      end
    end

    class CrudTestApi::Invoice < CrudTestApi::Resource
      configure do
        path "invoices"
        wrapper_name "Invoice"
      end

      key :document_number, Integer, :read_only
      attr :customer_name, String, :required
      attr :amount, Float
    end
  end

  after(:all) do
    Object.send(:remove_const, :CrudTestApi)
  end

  # These specs stub the HTTP layer to verify the CRUD operations
  # compose correctly with parse/serialise pipelines.

  describe ".find" do
    it "makes a GET request to endpoint/id and returns a parsed instance" do
      api_response = {
        "Invoice" => {
          "DocumentNumber" => 123,
          "CustomerName" => "Acme Corp",
          "Amount" => 500.0
        }
      }

      allow(CrudTestApi::Invoice).to receive(:get)
        .with(hash_including(path: "invoices/123"))
        .and_return(api_response)

      invoice = CrudTestApi::Invoice.find(123)

      expect(invoice.model.document_number).to eq(123)
      expect(invoice.model.customer_name).to eq("Acme Corp")
      expect(invoice.model.amount).to eq(500.0)
      expect(invoice.meta.new?).to be false
    end
  end

  describe ".all" do
    it "makes a GET request to endpoint and returns an array of instances" do
      api_response = [
        { "Invoice" => { "DocumentNumber" => 1, "CustomerName" => "Acme", "Amount" => 100.0 } },
        { "Invoice" => { "DocumentNumber" => 2, "CustomerName" => "Beta", "Amount" => 200.0 } }
      ]

      allow(CrudTestApi::Invoice).to receive(:get)
        .with(hash_including(path: "invoices"))
        .and_return(api_response)

      invoices = CrudTestApi::Invoice.all

      expect(invoices.length).to eq(2)
      expect(invoices[0].model.customer_name).to eq("Acme")
      expect(invoices[1].model.customer_name).to eq("Beta")
    end
  end

  describe ".save" do
    context "with a new instance" do
      it "delegates to create (POST)" do
        instance = CrudTestApi::Invoice.stub(customer_name: "New Corp", amount: 300.0)

        api_response = {
          "Invoice" => {
            "DocumentNumber" => 456,
            "CustomerName" => "New Corp",
            "Amount" => 300.0
          }
        }

        allow(CrudTestApi::Invoice).to receive(:post).and_return(api_response)

        saved = CrudTestApi::Invoice.save(instance)

        expect(CrudTestApi::Invoice).to have_received(:post)
        expect(saved.model.document_number).to eq(456)
        expect(saved.meta.new?).to be false
      end
    end

    context "with an existing instance" do
      it "delegates to update (PUT)" do
        instance = CrudTestApi::Invoice.parse({
          "Invoice" => {
            "DocumentNumber" => 123,
            "CustomerName" => "Acme",
            "Amount" => 500.0
          }
        })

        updated_instance = instance.update(amount: 600.0)

        api_response = {
          "Invoice" => {
            "DocumentNumber" => 123,
            "CustomerName" => "Acme",
            "Amount" => 600.0
          }
        }

        allow(CrudTestApi::Invoice).to receive(:put).and_return(api_response)

        saved = CrudTestApi::Invoice.save(updated_instance)

        expect(CrudTestApi::Invoice).to have_received(:put)
        expect(saved.model.amount).to eq(600.0)
      end
    end
  end

  describe ".delete" do
    it "makes a DELETE request to endpoint/id" do
      allow(CrudTestApi).to receive(:delete)

      CrudTestApi::Invoice.delete(123)

      expect(CrudTestApi).to have_received(:delete)
        .with(hash_including(path: "invoices/123"))
    end
  end

  describe "overriding CRUD methods" do
    before(:all) do
      # API that uses POST for updates instead of PUT
      class CrudTestApi::PostUpdateResource < RestEasy::Resource
        def self.update(instance)
          response = post(
            path: "#{config.path}/#{instance.unique_id}",
            body: instance.serialise
          )
          parse(response)
        end
      end

      class CrudTestApi::Order < CrudTestApi::PostUpdateResource
        configure do
          path "orders"
        end

        key :id, Integer, :read_only
        attr :total, Float
      end
    end

    after(:all) do
      CrudTestApi.send(:remove_const, :Order)
      CrudTestApi.send(:remove_const, :PostUpdateResource)
    end

    it "uses POST instead of PUT for updates" do
      instance = CrudTestApi::Order.parse({ "Id" => 1, "Total" => 100.0 })
      updated = instance.update(total: 200.0)

      api_response = { "Id" => 1, "Total" => 200.0 }
      allow(CrudTestApi::Order).to receive(:post).and_return(api_response)

      CrudTestApi::Order.save(updated)

      expect(CrudTestApi::Order).to have_received(:post)
    end
  end
end
