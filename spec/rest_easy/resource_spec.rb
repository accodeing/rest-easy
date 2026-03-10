# frozen_string_literal: true

RSpec.describe RestEasy::Resource do
  # ── Test fixtures ──────────────────────────────────────────────────────

  before(:all) do
    # Stub module acting as the singleton container
    module TestApi
      extend RestEasy

      configure do |config|
        config.base_url = "https://api.example.com/v1"
        config.max_retries = 3
      end
    end
  end

  after(:all) do
    Object.send(:remove_const, :TestApi)
  end

  # ── Class-level DSL ────────────────────────────────────────────────────

  describe "class-level DSL" do
    describe "path" do
      it "sets the endpoint path" do
        resource = Class.new(described_class) do
          path "invoices"
        end

        expect(resource.path).to eq("invoices")
      end
    end

  end

  # ── Metadata defaults ─────────────────────────────────────────────────

  describe "metadata" do
    it "sets default meta values on parsed instances" do
      resource = Class.new(described_class) do
        attr :name, String
        metadata partial: true
      end

      instance = resource.parse({ "Name" => "Test" })
      expect(instance.meta.partial?).to be true
    end

    it "sets default meta values on stubbed instances" do
      resource = Class.new(described_class) do
        attr :name, String
        metadata partial: true
      end

      instance = resource.stub(name: "Test")
      expect(instance.meta.partial?).to be true
    end

    it "preserves defaults through update" do
      resource = Class.new(described_class) do
        attr :name, String
        metadata partial: true
      end

      instance = resource.parse({ "Name" => "Test" })
      updated = instance.update(name: "Changed")
      expect(updated.meta.partial?).to be true
    end

    it "allows instance-level override of defaults" do
      resource = Class.new(described_class) do
        attr :name, String
        metadata partial: true
      end

      instance = resource.parse({ "Name" => "Test" })
      instance.meta.partial = false
      expect(instance.meta.partial?).to be false
    end

    it "inherits metadata from parent resource" do
      parent = Class.new(described_class) do
        metadata partial: true
      end

      child = Class.new(parent) do
        attr :name, String
        metadata author: "test"
      end

      instance = child.parse({ "Name" => "Test" })
      expect(instance.meta.partial?).to be true
      expect(instance.meta.author).to eq("test")
    end

    it "returns empty hash when no metadata defined" do
      resource = Class.new(described_class) do
        attr :name, String
      end

      expect(resource.metadata).to eq({})
    end
  end

  # ── Attribute declarations ─────────────────────────────────────────────

  describe "attr" do
    describe "simple declaration" do
      before do
        @resource_class = Class.new(described_class) do
          attr :name, String
          attr :age, Integer
          attr :active, Boolean
        end
      end

      it "registers attributes on the class" do
        expect(@resource_class.attributes).to include(:name, :age, :active)
      end

      it "parses API data into model attributes" do
        instance = @resource_class.new({ "Name" => "Alice", "Age" => 30, "Active" => true })

        expect(instance.name).to eq("Alice")
        expect(instance.age).to eq(30)
        expect(instance.active).to eq(true)
      end
    end

    describe "attribute convention" do
      context "with :PascalCase convention" do
        before do
          @resource_class = Class.new(described_class) do
            attribute_convention :PascalCase

            attr :document_number, Integer
            attr :customer_name, String
            attr :due_date, String
          end
        end

        it "converts snake_case model name to PascalCase API name" do
          api_data = {
            "DocumentNumber" => 12345,
            "CustomerName" => "Acme Corp",
            "DueDate" => "2024-01-15"
          }

          instance = @resource_class.parse(api_data)

          expect(instance.document_number).to eq(12345)
          expect(instance.customer_name).to eq("Acme Corp")
          expect(instance.due_date).to eq("2024-01-15")
        end

        it "serialises back to PascalCase API names" do
          instance = @resource_class.parse({
            "DocumentNumber" => 1,
            "CustomerName" => "Test",
            "DueDate" => "2024-01-15"
          })
          serialised = instance.serialise

          expect(serialised).to have_key("DocumentNumber")
          expect(serialised).to have_key("CustomerName")
          expect(serialised).to have_key("DueDate")
        end
      end

      context "with :camelCase convention" do
        before do
          @resource_class = Class.new(described_class) do
            attribute_convention :camelCase

            attr :document_number, Integer
            attr :customer_name, String
          end
        end

        it "converts snake_case model name to camelCase API name" do
          api_data = {
            "documentNumber" => 12345,
            "customerName" => "Acme Corp"
          }

          instance = @resource_class.parse(api_data)

          expect(instance.document_number).to eq(12345)
          expect(instance.customer_name).to eq("Acme Corp")
        end

        it "serialises back to camelCase API names" do
          instance = @resource_class.parse({
            "documentNumber" => 1,
            "customerName" => "Test"
          })
          serialised = instance.serialise

          expect(serialised).to have_key("documentNumber")
          expect(serialised).to have_key("customerName")
        end
      end

      context "with :snake_case convention" do
        before do
          @resource_class = Class.new(described_class) do
            attribute_convention :snake_case

            attr :document_number, Integer
          end
        end

        it "passes through names unchanged" do
          instance = @resource_class.parse({ "document_number" => 12345 })

          expect(instance.document_number).to eq(12345)
        end

        it "serialises with snake_case names" do
          instance = @resource_class.parse({ "document_number" => 1 })
          serialised = instance.serialise

          expect(serialised).to have_key("document_number")
        end
      end

      context "with custom convention object" do
        before do
          custom_convention = Class.new do
            # API uses SCREAMING_SNAKE_CASE
            def parse(api_name)
              api_name.downcase.to_sym
            end

            def serialise(model_name)
              model_name.to_s.upcase
            end
          end

          convention = custom_convention.new

          @resource_class = Class.new(described_class) do
            attribute_convention convention

            attr :document_number, Integer
          end
        end

        it "uses custom parse for API → model" do
          instance = @resource_class.parse({ "DOCUMENT_NUMBER" => 12345 })
          expect(instance.document_number).to eq(12345)
        end

        it "uses custom serialise for model → API" do
          instance = @resource_class.parse({ "DOCUMENT_NUMBER" => 1 })
          serialised = instance.serialise

          expect(serialised).to have_key("DOCUMENT_NUMBER")
        end
      end

      context "with <=> override" do
        it "overrides convention for specific attributes" do
          resource_class = Class.new(described_class) do
            using RestEasy::Refinements

            attribute_convention :PascalCase

            attr :document_number, Integer
            attr '@urlTaxReductionList' <=> :tax_reduction_list_url, String, :optional
          end

          instance = resource_class.parse({
            "DocumentNumber" => 1,
            "@urlTaxReductionList" => "https://example.com"
          })

          expect(instance.document_number).to eq(1)
          expect(instance.tax_reduction_list_url).to eq("https://example.com")
        end

        it "serialises overridden attributes back to their explicit API name" do
          resource_class = Class.new(described_class) do
            using RestEasy::Refinements

            attribute_convention :PascalCase

            attr '@urlTaxReductionList' <=> :tax_reduction_list_url, String, :optional
          end

          instance = resource_class.parse({
            "@urlTaxReductionList" => "https://example.com"
          })
          serialised = instance.serialise

          expect(serialised).to have_key("@urlTaxReductionList")
          expect(serialised).not_to have_key("TaxReductionListUrl")
        end
      end
    end

    describe "explicit API name mapping with <=>" do
      before do
        @resource_class = Class.new(described_class) do
          using RestEasy::Refinements

          attr '@urlTaxReductionList' <=> :tax_reduction_list_url, String, :read_only, :optional
        end
      end

      it "maps the explicit API name to the model name" do
        api_data = { "@urlTaxReductionList" => "https://example.com/tax" }
        instance = @resource_class.parse(api_data)

        expect(instance.tax_reduction_list_url).to eq("https://example.com/tax")
      end
    end

    describe "attribute flags" do
      it "supports :required flag" do
        resource_class = Class.new(described_class) do
          attr :name, String, :required
        end

        expect {
          resource_class.parse({})
        }.to raise_error(RestEasy::MissingAttributeError)
      end

      it "supports :optional flag" do
        resource_class = Class.new(described_class) do
          attr :name, String, :optional
        end

        instance = resource_class.parse({})
        expect(instance.name).to be_nil
      end

      it "supports :read_only flag" do
        resource_class = Class.new(described_class) do
          attr :balance, Float, :read_only
        end

        instance = resource_class.parse({ "Balance" => 100.50 })
        serialised = instance.serialise

        expect(serialised).not_to have_key("Balance")
        expect(serialised).not_to have_key(:balance)
      end
    end

    describe "custom parse/serialise with block" do
      before do
        @resource_class = Class.new(described_class) do
          using RestEasy::Refinements

          attr :raw_field <=> :clean_field, String do
            parse do |raw_value|
              raw_value.strip.downcase
            end
            serialise do |value|
              value.upcase
            end
          end
        end
      end

      it "applies custom parse logic" do
        instance = @resource_class.parse({ "raw_field" => "  HELLO  " })
        expect(instance.clean_field).to eq("hello")
      end

      it "applies custom serialise logic" do
        instance = @resource_class.parse({ "raw_field" => "  HELLO  " })
        serialised = instance.serialise

        expect(serialised["raw_field"]).to eq("HELLO")
      end
    end
  end

  # ── key ────────────────────────────────────────────────────────────────

  describe "key" do
    it "declares the unique identifier attribute" do
      resource_class = Class.new(described_class) do
        key :document_number, Integer, :read_only
      end

      instance = resource_class.parse({ "DocumentNumber" => 12345 })

      expect(instance.unique_id).to eq(12345)
    end

    it "is equivalent to attr with :key flag" do
      resource_class = Class.new(described_class) do
        attr :id, Integer, :key
      end

      instance = resource_class.parse({ "Id" => 42 })

      expect(instance.unique_id).to eq(42)
    end

    it "warns when called more than once" do
      expect {
        Class.new(described_class) do
          key :id, Integer
          key :other_id, Integer
        end
      }.to output(/warning/i).to_stderr
    end
  end

  # ── ignore ─────────────────────────────────────────────────────────────

  describe "ignore" do
    before do
      @resource_class = Class.new(described_class) do
        attr :name, String
        ignore :internal_field
      end
    end

    it "excludes the field from model attributes" do
      instance = @resource_class.parse({
        "Name" => "Test",
        "InternalField" => "secret"
      })

      expect(instance.model).not_to respond_to(:internal_field)
    end

    it "retains ignored fields in the shadow copy for round-tripping" do
      instance = @resource_class.parse({
        "Name" => "Test",
        "InternalField" => "secret"
      })

      expect(instance.api.attributes).to include("InternalField" => "secret")
    end

    it "preserves ignored fields when serialising" do
      instance = @resource_class.parse({
        "Name" => "Test",
        "InternalField" => "secret"
      })

      serialised = instance.serialise
      expect(serialised["InternalField"]).to eq("secret")
    end

    it "does not warn about explicitly ignored fields" do
      resource_class = Class.new(described_class) do
        attr :name, String
        ignore :internal_field
      end

      expect {
        resource_class.parse({ "Name" => "Test", "InternalField" => "secret" })
      }.not_to output(/unknown API field/i).to_stderr
    end

    it "warns about undeclared API fields" do
      resource_class = Class.new(described_class) do
        attr :name, String
      end

      expect {
        resource_class.parse({ "Name" => "Test", "SurpriseField" => "wat" })
      }.to output(/unknown API field 'SurpriseField'/).to_stderr
    end
  end

  # ── synthetic (attr with multi-param parse block) ─────────────────────

  describe "synthetic attributes via attr block" do
    before do
      @resource_class = Class.new(described_class) do
        attr :first_name, String
        attr :last_name, String

        attr :full_name, String do
          parse { |first_name, last_name| "#{first_name} #{last_name}" }
          serialise { |full_name| full_name.split(' ', 2) }
        end
      end
    end

    it "auto-detects synthetic from parse block parameter count" do
      attr_def = @resource_class.all_attribute_definitions[:full_name]
      expect(attr_def.synthetic?).to be true
      expect(attr_def.source_fields).to eq([:first_name, :last_name])
    end

    it "creates model attribute from API data using source fields" do
      instance = @resource_class.parse({
        "FirstName" => "Jonas",
        "LastName" => "Erlandsson"
      })

      expect(instance.full_name).to eq("Jonas Erlandsson")
    end

    it "decomposes back to API fields when serialising" do
      instance = @resource_class.parse({
        "FirstName" => "Jonas",
        "LastName" => "Erlandsson"
      })

      serialised = instance.serialise

      expect(serialised["FirstName"]).to eq("Jonas")
      expect(serialised["LastName"]).to eq("Erlandsson")
    end

    it "does not expose synthetic attributes as API fields" do
      instance = @resource_class.parse({
        "FirstName" => "Jonas",
        "LastName" => "Erlandsson"
      })

      expect(instance.api.attributes).not_to have_key("full_name")
      expect(instance.api.attributes).not_to have_key("FullName")
    end

    it "does not include synthetic api_name key in serialised output" do
      instance = @resource_class.parse({
        "FirstName" => "Jonas",
        "LastName" => "Erlandsson"
      })

      serialised = instance.serialise

      expect(serialised).not_to have_key("FullName")
    end
  end

  # ── bare block (implicit parse) ───────────────────────────────────────

  describe "bare block as implicit parse" do
    it "treats a block with params as an implicit parse block" do
      resource_class = Class.new(described_class) do
        attr :full_name, String, :read_only do |first_name, last_name|
          "#{first_name} #{last_name}"
        end
      end

      instance = resource_class.parse({
        "FirstName" => "Jonas",
        "LastName" => "Erlandsson"
      })

      expect(instance.full_name).to eq("Jonas Erlandsson")
    end

    it "extracts source_fields from bare block param names" do
      resource_class = Class.new(described_class) do
        attr :full_name, String, :read_only do |first_name, last_name|
          "#{first_name} #{last_name}"
        end
      end

      attr_def = resource_class.all_attribute_definitions[:full_name]
      expect(attr_def.source_fields).to eq([:first_name, :last_name])
      expect(attr_def.synthetic?).to be true
    end

    it "works with single-param bare block for split pattern" do
      resource_class = Class.new(described_class) do
        attr :city, String do |address|
          address["city"]
        end
      end

      instance = resource_class.parse({
        "Address" => { "city" => "Stockholm", "street" => "Main St" }
      })

      expect(instance.city).to eq("Stockholm")
    end

    it "serialises under own API name when no serialise block is defined" do
      resource_class = Class.new(described_class) do
        attr :city, String do |address|
          address["city"]
        end
      end

      instance = resource_class.parse({
        "Address" => { "city" => "Stockholm", "street" => "Main St" }
      })

      serialised = instance.serialise

      expect(serialised["City"]).to eq("Stockholm")
    end
  end

  # ── multi-param serialise ─────────────────────────────────────────────

  describe "multi-param serialise block" do
    it "gathers model values by param names and splats into block" do
      resource_class = Class.new(described_class) do
        attr :street, String
        attr :city, String

        attr :address, String do
          serialise { |street, city| "#{street}, #{city}" }
        end
      end

      instance = resource_class.stub(street: "Main St", city: "Stockholm", address: "ignored")

      serialised = instance.serialise

      expect(serialised["Address"]).to eq("Main St, Stockholm")
    end

    it "stores target_fields from serialise block param names" do
      resource_class = Class.new(described_class) do
        attr :street, String
        attr :city, String

        attr :address, String do
          serialise { |street, city| "#{street}, #{city}" }
        end
      end

      attr_def = resource_class.all_attribute_definitions[:address]
      expect(attr_def.target_fields).to eq([:street, :city])
    end
  end

  # ── Resource-level hooks ───────────────────────────────────────────────

  describe "resource-level hooks" do
    describe "before_parse" do
      it "pre-processes API data before attribute parsing" do
        resource_class = Class.new(described_class) do
          before_parse do |api_data|
            api_data["Invoice"]
          end

          attr :name, String
        end

        instance = resource_class.parse({ "Invoice" => { "Name" => "Test" } })
        expect(instance.name).to eq("Test")
      end
    end

    describe "after_parse" do
      it "runs after all attributes have been parsed" do
        after_parse_called = false

        resource_class = Class.new(described_class) do
          attr :name, String

          after_parse do |model|
            after_parse_called = true
          end
        end

        resource_class.parse({ "Name" => "Test" })
        expect(after_parse_called).to be true
      end
    end

    describe "before_serialise" do
      it "runs before attribute serialisation" do
        before_serialise_called = false

        resource_class = Class.new(described_class) do
          attr :name, String

          before_serialise do |model|
            before_serialise_called = true
          end
        end

        instance = resource_class.parse({ "Name" => "Test" })
        instance.serialise
        expect(before_serialise_called).to be true
      end
    end

    describe "after_serialise" do
      it "post-processes API data after serialisation" do
        resource_class = Class.new(described_class) do
          attr :name, String

          after_serialise do |api_data|
            { "Invoice" => api_data }
          end
        end

        instance = resource_class.parse({ "Name" => "Test" })
        serialised = instance.serialise

        expect(serialised).to eq({ "Invoice" => { "Name" => "Test" } })
      end
    end

    describe "hook inheritance" do
      it "inherits hooks from parent classes" do
        parent = Class.new(described_class) do
          before_parse do |api_data|
            api_data["Wrapper"]
          end
        end

        child = Class.new(parent) do
          attr :name, String
        end

        instance = child.parse({ "Wrapper" => { "Name" => "Test" } })
        expect(instance.name).to eq("Test")
      end
    end
  end

  # ── Instance state ─────────────────────────────────────────────────────

  describe "instance state" do
    before do
      @resource_class = Class.new(described_class) do
        key :id, Integer
        attr :name, String
        ignore :internal
      end

      @instance = @resource_class.parse({
        "Id" => 1,
        "Name" => "Test",
        "Internal" => "hidden"
      })
    end

    describe "model" do
      it "exposes parsed model attributes" do
        expect(@instance.id).to eq(1)
        expect(@instance.name).to eq("Test")
      end

      it "does not expose ignored fields" do
        expect(@instance.model).not_to respond_to(:internal)
      end
    end

    describe "api (shadow copy)" do
      it "retains the original API response data" do
        expect(@instance.api.attributes).to include(
          "Id" => 1,
          "Name" => "Test",
          "Internal" => "hidden"
        )
      end
    end

    describe "meta" do
      it "tracks new? status for locally created instances" do
        stub_instance = @resource_class.stub(id: 99, name: "New")
        expect(stub_instance.meta.new?).to be true
      end

      it "tracks new? status for API-loaded instances" do
        expect(@instance.meta.new?).to be false
      end

      it "tracks saved? status" do
        stub_instance = @resource_class.stub(id: 99, name: "New")
        expect(stub_instance.meta.saved?).to be false
      end

      it "allows gem authors to set custom metadata" do
        @instance.meta.partial = true
        expect(@instance.meta.partial).to be true
      end
    end
  end

  # ── Change tracking ────────────────────────────────────────────────────

  describe "change tracking" do
    before do
      @resource_class = Class.new(described_class) do
        key :id, Integer
        attr :name, String
        attr :amount, Float
      end
    end

    it "detects changes after update" do
      instance = @resource_class.parse({ "Id" => 1, "Name" => "Old", "Amount" => 100.0 })
      updated = instance.update(name: "New")

      expect(updated.__changes__).to include(name: "New")
      expect(updated.__changes__).not_to have_key(:amount)
    end

    it "returns an immutable copy from update" do
      instance = @resource_class.parse({ "Id" => 1, "Name" => "Old", "Amount" => 100.0 })
      updated = instance.update(name: "New")

      expect(updated).not_to equal(instance)
      expect(instance.name).to eq("Old")
      expect(updated.name).to eq("New")
    end

    it "returns self when update hash is empty" do
      instance = @resource_class.parse({ "Id" => 1, "Name" => "Test", "Amount" => 50.0 })
      updated = instance.update({})

      expect(updated).to equal(instance)
    end
  end

  # ── Serialisation ──────────────────────────────────────────────────────

  describe "serialisation" do
    before do
      @resource_class = Class.new(described_class) do
        key :id, Integer, :read_only
        attr :name, String
        attr :balance, Float, :read_only
      end
    end

    it "excludes read_only attributes" do
      instance = @resource_class.parse({ "Id" => 1, "Name" => "Test", "Balance" => 100.0 })
      serialised = instance.serialise

      expect(serialised).not_to have_key("Id")
      expect(serialised).not_to have_key("Balance")
      expect(serialised["Name"]).to eq("Test")
    end

    it "maps model names back to API names" do
      instance = @resource_class.parse({ "Id" => 1, "Name" => "Test", "Balance" => 100.0 })
      serialised = instance.serialise

      expect(serialised).to have_key("Name")
      expect(serialised).not_to have_key(:name)
    end

    it "provides to_json for model representation" do
      instance = @resource_class.parse({ "Id" => 1, "Name" => "Test", "Balance" => 100.0 })
      json = instance.to_json

      parsed = JSON.parse(json)
      expect(parsed["id"]).to eq(1)
      expect(parsed["name"]).to eq("Test")
    end

    it "provides to_api for API representation" do
      instance = @resource_class.parse({ "Id" => 1, "Name" => "Test", "Balance" => 100.0 })
      api_json = instance.to_api

      parsed = JSON.parse(api_json)
      expect(parsed).not_to have_key("Id")
      expect(parsed["Name"]).to eq("Test")
    end
  end

  # ── Equality ───────────────────────────────────────────────────────────

  describe "equality" do
    before do
      @resource_class = Class.new(described_class) do
        key :id, Integer
        attr :name, String
      end
    end

    it "considers two instances equal if their model state is equal" do
      a = @resource_class.parse({ "Id" => 1, "Name" => "Test" })
      b = @resource_class.parse({ "Id" => 1, "Name" => "Test" })

      expect(a).to eq(b)
    end

    it "considers instances with different state unequal" do
      a = @resource_class.parse({ "Id" => 1, "Name" => "Test" })
      b = @resource_class.parse({ "Id" => 1, "Name" => "Other" })

      expect(a).not_to eq(b)
    end

    it "considers instances of different classes unequal" do
      other_class = Class.new(described_class) do
        key :id, Integer
        attr :name, String
      end

      a = @resource_class.parse({ "Id" => 1, "Name" => "Test" })
      b = other_class.parse({ "Id" => 1, "Name" => "Test" })

      expect(a).not_to eq(b)
    end
  end

  # ── Type coercion ──────────────────────────────────────────────────────

  describe "type coercion" do
    it "coerces string to integer" do
      resource_class = Class.new(described_class) do
        attr :count, Integer
      end

      instance = resource_class.parse({ "Count" => "42" })
      expect(instance.count).to eq(42)
    end

    it "coerces string to float" do
      resource_class = Class.new(described_class) do
        attr :amount, Float
      end

      instance = resource_class.parse({ "Amount" => "99.95" })
      expect(instance.amount).to eq(99.95)
    end

    it "supports type constraints" do
      resource_class = Class.new(described_class) do
        attr :name, String.constrained(max_size: 5)
      end

      expect {
        resource_class.parse({ "Name" => "Too Long Name" })
      }.to raise_error(RestEasy::ConstraintError)
    end
  end

  # ── Settings (Dry::Configurable on Resource) ──────────────────────────

  describe "settings" do
    it "declares a setting via the settings block" do
      resource = Class.new(described_class) do
        settings do
          setting :wrapper, default: true
        end
      end

      expect(resource.config.wrapper).to be true
    end

    it "allows reading settings via config" do
      resource = Class.new(described_class) do
        settings do
          setting :collection_name, default: "items"
        end
      end

      resource.config.collection_name = "records"
      expect(resource.config.collection_name).to eq("records")
    end

    it "supports reader: true for accessor methods" do
      resource = Class.new(described_class) do
        settings do
          setting :wrapper, default: true, reader: true
        end
      end

      expect(resource.wrapper).to be true
    end

    it "inherits settings from parent resource" do
      parent = Class.new(described_class) do
        settings do
          setting :wrapper, default: true
        end
      end

      child = Class.new(parent) do
        attr :name, String
      end

      expect(child.config.wrapper).to be true
    end

    it "isolates config between sibling classes" do
      parent = Class.new(described_class) do
        settings do
          setting :wrapper, default: true
        end
      end

      child_a = Class.new(parent)
      child_b = Class.new(parent)

      child_a.config.wrapper = false

      expect(child_a.config.wrapper).to be false
      expect(child_b.config.wrapper).to be true
      expect(parent.config.wrapper).to be true
    end

    it "allows child to override inherited defaults without affecting parent" do
      parent = Class.new(described_class) do
        settings do
          setting :wrapper, default: true
        end
      end

      child = Class.new(parent)
      child.config.wrapper = false

      expect(child.config.wrapper).to be false
      expect(parent.config.wrapper).to be true
    end

    it "accumulates settings from multiple levels" do
      grandparent = Class.new(described_class) do
        settings do
          setting :wrapper, default: true
        end
      end

      parent = Class.new(grandparent) do
        settings do
          setting :collection_name, default: "items"
        end
      end

      child = Class.new(parent) do
        attr :name, String
      end

      expect(child.config.wrapper).to be true
      expect(child.config.collection_name).to eq("items")
    end

    it "exposes config on instances for use in hooks" do
      resource = Class.new(described_class) do
        settings do
          setting :wrapper, default: true
        end
        attr :name, String
      end

      instance = resource.parse({ "Name" => "Test" })
      expect(instance.config.wrapper).to be true
    end
  end
end
