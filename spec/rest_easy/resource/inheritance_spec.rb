# frozen_string_literal: true

RSpec.describe "Resource inheritance chain" do
  # Tests the three-level pattern:
  #   RestEasy::Resource → API::Resource → API::Invoice

  before(:all) do
    module InheritanceTestApi
      extend RestEasy

      configure do |config|
        config.base_url = "https://api.example.com"
        config.attribute_convention = :PascalCase
      end
    end

    # API-level base resource with shared behaviour
    class InheritanceTestApi::Resource < RestEasy::Resource
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

    # Endpoint-specific resource
    class InheritanceTestApi::Invoice < InheritanceTestApi::Resource
      endpoint_path "invoices"
      config.wrapper_name = "Invoice"

      key :id, Integer, :read_only
      attr :name, String
    end

    class InheritanceTestApi::Customer < InheritanceTestApi::Resource
      endpoint_path "customers"
      config.wrapper_name = "Customer"

      key :id, Integer, :read_only
      attr :company_name, String
    end
  end

  after(:all) do
    Object.send(:remove_const, :InheritanceTestApi)
  end

  describe "API-level hooks" do
    it "applies before_parse from parent to Invoice" do
      instance = InheritanceTestApi::Invoice.parse({
        "Invoice" => { "Id" => 1, "Name" => "Test Invoice" }
      })

      expect(instance.model.name).to eq("Test Invoice")
    end

    it "applies before_parse from parent to Customer" do
      instance = InheritanceTestApi::Customer.parse({
        "Customer" => { "Id" => 1, "CompanyName" => "Acme" }
      })

      expect(instance.model.company_name).to eq("Acme")
    end

    it "wraps serialised output with resource name" do
      instance = InheritanceTestApi::Invoice.parse({
        "Invoice" => { "Id" => 1, "Name" => "Test" }
      })

      serialised = instance.serialise

      expect(serialised).to have_key("Invoice")
      expect(serialised["Invoice"]["Name"]).to eq("Test")
    end
  end

  describe "overriding at endpoint level" do
    before(:all) do
      class InheritanceTestApi::SpecialInvoice < InheritanceTestApi::Resource
        endpoint_path "special-invoices"

        key :id, Integer, :read_only
        attr :name, String

        # Override the parent's before_parse for this endpoint
        before_parse do |api_data|
          api_data["SpecialWrapper"]["Data"]
        end
      end
    end

    after(:all) do
      InheritanceTestApi.send(:remove_const, :SpecialInvoice)
    end

    it "uses the endpoint-level hook instead of parent" do
      instance = InheritanceTestApi::SpecialInvoice.parse({
        "SpecialWrapper" => { "Data" => { "Id" => 1, "Name" => "Special" } }
      })

      expect(instance.model.name).to eq("Special")
    end
  end

  describe "attribute inheritance" do
    before(:all) do
      # A base document with shared attributes
      class InheritanceTestApi::Document < InheritanceTestApi::Resource
        attr :created_at, String, :read_only
        attr :updated_at, String, :read_only
      end

      class InheritanceTestApi::Order < InheritanceTestApi::Document
        endpoint_path "orders"
        config.wrapper_name = "Order"

        key :id, Integer, :read_only
        attr :total, Float
      end
    end

    after(:all) do
      InheritanceTestApi.send(:remove_const, :Order)
      InheritanceTestApi.send(:remove_const, :Document)
    end

    it "inherits attributes from parent resource" do
      instance = InheritanceTestApi::Order.parse({
        "Order" => {
          "Id" => 1,
          "Total" => 250.0,
          "CreatedAt" => "2024-01-01",
          "UpdatedAt" => "2024-01-02"
        }
      })

      expect(instance.model.total).to eq(250.0)
      expect(instance.model.created_at).to eq("2024-01-01")
      expect(instance.model.updated_at).to eq("2024-01-02")
    end
  end
end
