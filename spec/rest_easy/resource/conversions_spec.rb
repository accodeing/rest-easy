# frozen_string_literal: true

RSpec.describe "Resource conversions" do
  # Helper to set up a Faraday test adapter with stubs
  def setup_test_connection(api_module, &block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    api_module.instance_variable_set(:@faraday_connection, nil)
    api_module.connection do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.adapter :test, stubs
    end
    stubs
  end

  # ── Module-level configuration ──────────────────────────────────────

  describe "module-level conversions" do
    before(:all) do
      module ConvTestApi
        extend RestEasy

        configure do
          conversions.json_attributes = :PascalCase
          conversions.query_parameters = :camelCase
        end
      end

      class ConvTestApi::Invoice < RestEasy::Resource
        configure { path "invoices" }

        key :document_number, Integer, :read_only
        attr :customer_name, String
      end
    end

    after(:all) do
      Object.send(:remove_const, :ConvTestApi)
    end

    it "resolves json_attributes from module config" do
      expect(ConvTestApi::Invoice.json_attribute_converter).to be_a(RestEasy::Conventions::PascalCase)
    end

    it "resolves query_parameters from module config" do
      expect(ConvTestApi::Invoice.query_parameter_converter).to be_a(RestEasy::Conventions::CamelCase)
    end

    it "parses API data using json_attributes convention" do
      instance = ConvTestApi::Invoice.parse({
        "DocumentNumber" => 1,
        "CustomerName" => "Acme"
      })

      expect(instance.document_number).to eq(1)
      expect(instance.customer_name).to eq("Acme")
    end

    it "serialises using json_attributes convention" do
      instance = ConvTestApi::Invoice.parse({
        "DocumentNumber" => 1,
        "CustomerName" => "Acme"
      })
      serialised = instance.serialise

      # DocumentNumber is :read_only, so excluded from serialise
      expect(serialised).to have_key("CustomerName")
      expect(serialised["CustomerName"]).to eq("Acme")
    end

    it "transforms query parameter keys using query_parameters convention" do
      captured_params = nil

      setup_test_connection(ConvTestApi) do |stub|
        stub.get("/invoices") do |env|
          captured_params = env.params
          [200, { "Content-Type" => "application/json" },
           '[{"DocumentNumber": 1, "CustomerName": "Test"}]']
        end
      end

      ConvTestApi::Invoice.get(
        path: "invoices",
        params: { customer_name: "Test", sort_order: "asc" }
      )

      expect(captured_params).to include("customerName" => "Test", "sortOrder" => "asc")
    end

    it "does not mutate the caller-provided params hash" do
      setup_test_connection(ConvTestApi) do |stub|
        stub.get("/invoices") do
          [200, { "Content-Type" => "application/json" }, "[]"]
        end
      end

      params = { customer_name: "Test" }
      ConvTestApi::Invoice.get(path: "invoices", params: params)

      expect(params).to eq(customer_name: "Test")
    end

    it "accepts a frozen params hash without raising" do
      setup_test_connection(ConvTestApi) do |stub|
        stub.get("/invoices") do
          [200, { "Content-Type" => "application/json" }, "[]"]
        end
      end

      params = { customer_name: "Test" }.freeze

      expect {
        ConvTestApi::Invoice.get(path: "invoices", params: params)
      }.not_to raise_error
    end
  end

  # ── Resource-level override ─────────────────────────────────────────

  describe "resource-level override" do
    before(:all) do
      module ResOverrideApi
        extend RestEasy

        configure do
          conversions.json_attributes = :camelCase
          conversions.query_parameters = :camelCase
        end
      end

      class ResOverrideApi::Base < RestEasy::Resource
      end

      class ResOverrideApi::Standard < ResOverrideApi::Base
        attr :item_name, String
      end

      class ResOverrideApi::Custom < ResOverrideApi::Base
        configure do
          conversions.json_attributes = :PascalCase
          conversions.query_parameters = :PascalCase
        end

        attr :item_name, String
      end
    end

    after(:all) do
      Object.send(:remove_const, :ResOverrideApi)
    end

    it "inherits module-level convention when not overridden" do
      expect(ResOverrideApi::Standard.json_attribute_converter).to be_a(RestEasy::Conventions::CamelCase)
      expect(ResOverrideApi::Standard.query_parameter_converter).to be_a(RestEasy::Conventions::CamelCase)
    end

    it "uses resource-level convention when overridden" do
      expect(ResOverrideApi::Custom.json_attribute_converter).to be_a(RestEasy::Conventions::PascalCase)
      expect(ResOverrideApi::Custom.query_parameter_converter).to be_a(RestEasy::Conventions::PascalCase)
    end

    it "parses with inherited convention" do
      instance = ResOverrideApi::Standard.parse({ "itemName" => "Widget" })
      expect(instance.item_name).to eq("Widget")
    end

    it "parses with overridden convention" do
      instance = ResOverrideApi::Custom.parse({ "ItemName" => "Widget" })
      expect(instance.item_name).to eq("Widget")
    end

    it "does not affect sibling resources" do
      expect(ResOverrideApi::Standard.json_attribute_converter).to be_a(RestEasy::Conventions::CamelCase)
      expect(ResOverrideApi::Custom.json_attribute_converter).to be_a(RestEasy::Conventions::PascalCase)
    end
  end

  # ── Partial override (one key only) ─────────────────────────────────

  describe "partial override" do
    before(:all) do
      module PartialApi
        extend RestEasy

        configure do
          conversions.json_attributes = :camelCase
          conversions.query_parameters = :camelCase
        end
      end

      class PartialApi::Resource < RestEasy::Resource
        configure do
          conversions.query_parameters = :PascalCase
          # json_attributes not set — inherits from module
        end

        attr :item_name, String
      end
    end

    after(:all) do
      Object.send(:remove_const, :PartialApi)
    end

    it "uses overridden query_parameters" do
      expect(PartialApi::Resource.query_parameter_converter).to be_a(RestEasy::Conventions::PascalCase)
    end

    it "inherits json_attributes from module" do
      expect(PartialApi::Resource.json_attribute_converter).to be_a(RestEasy::Conventions::CamelCase)
    end
  end

  # ── Independent conventions ─────────────────────────────────────────

  describe "independent query_parameters and json_attributes" do
    before(:all) do
      module MixedApi
        extend RestEasy

        configure do
          conversions.json_attributes = :camelCase
          conversions.query_parameters = :PascalCase
        end
      end

      class MixedApi::Item < RestEasy::Resource
        configure { path "items" }
        attr :item_name, String
      end
    end

    after(:all) do
      Object.send(:remove_const, :MixedApi)
    end

    it "uses different conventions for attributes and parameters" do
      expect(MixedApi::Item.json_attribute_converter).to be_a(RestEasy::Conventions::CamelCase)
      expect(MixedApi::Item.query_parameter_converter).to be_a(RestEasy::Conventions::PascalCase)
    end

    it "serialises attributes as camelCase" do
      instance = MixedApi::Item.parse({ "itemName" => "Widget" })
      serialised = instance.serialise
      expect(serialised).to have_key("itemName")
    end

    it "transforms query params as PascalCase" do
      captured_params = nil

      setup_test_connection(MixedApi) do |stub|
        stub.get("/items") do |env|
          captured_params = env.params
          [200, { "Content-Type" => "application/json" },
           '[{"itemName": "Widget"}]']
        end
      end

      MixedApi::Item.get(path: "items", params: { item_name: "Widget" })

      expect(captured_params).to include("ItemName" => "Widget")
    end
  end

  # ── Backwards compatibility ─────────────────────────────────────────

  describe "backwards compatibility" do
    describe "module-level attribute_convention" do
      before(:all) do
        module BCModuleApi
          extend RestEasy

          configure do |config|
            config.attribute_convention = :PascalCase
          end
        end

        class BCModuleApi::Invoice < RestEasy::Resource
          attr :customer_name, String
        end
      end

      after(:all) do
        Object.send(:remove_const, :BCModuleApi)
      end

      it "propagates to conversions.json_attributes" do
        expect(BCModuleApi::Invoice.json_attribute_converter).to be_a(RestEasy::Conventions::PascalCase)
      end

      it "defaults query_parameters to snake_case" do
        expect(BCModuleApi::Invoice.query_parameter_converter).to be_a(RestEasy::Conventions::SnakeCase)
      end

      it "parses with the propagated convention" do
        instance = BCModuleApi::Invoice.parse({ "CustomerName" => "Acme" })
        expect(instance.customer_name).to eq("Acme")
      end
    end

    describe "resource-level attribute_convention" do
      it "sets json_attributes and emits a deprecation warning" do
        resource_class = Class.new(RestEasy::Resource)

        expect {
          resource_class.attribute_convention :camelCase
        }.to output(/deprecated/).to_stderr

        expect(resource_class.json_attribute_converter).to be_a(RestEasy::Conventions::CamelCase)
      end

      it "still works as a getter" do
        resource_class = Class.new(RestEasy::Resource) do
          configure { conversions.json_attributes = :PascalCase }
          attr :item_name, String
        end

        # Suppress deprecation warning — we're testing the getter path
        expect(resource_class.attribute_convention).to be_a(RestEasy::Conventions::PascalCase)
      end
    end
  end

  # ── Default resolution ──────────────────────────────────────────────

  describe "default resolution" do
    before(:all) do
      module DefaultApi
        extend RestEasy
        # No conversions or attribute_convention set
      end

      class DefaultApi::Thing < RestEasy::Resource
        attr :my_field, String
      end
    end

    after(:all) do
      Object.send(:remove_const, :DefaultApi)
    end

    it "defaults json_attributes to snake_case" do
      expect(DefaultApi::Thing.json_attribute_converter).to be_a(RestEasy::Conventions::SnakeCase)
    end

    it "defaults query_parameters to snake_case" do
      expect(DefaultApi::Thing.query_parameter_converter).to be_a(RestEasy::Conventions::SnakeCase)
    end
  end
end
