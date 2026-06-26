# frozen_string_literal: true

RSpec.describe RestEasy::Attribute do
  describe "#validate_required!" do
    let(:type) { RestEasy::Types::Coercible::String }

    context "when the attribute is not :required" do
      let(:attr) { described_class.new(model_name: :name, api_name: "Name", type:) }

      it "does not raise even when the value is nil" do
        expect { attr.validate_required!(nil) }.not_to raise_error
      end

      it "does not raise with multiple nil values" do
        expect { attr.validate_required!(nil, nil) }.not_to raise_error
      end
    end

    context "when the attribute is :required" do
      let(:attr) { described_class.new(model_name: :name, api_name: "Name", type:, flags: [:required]) }

      it "does not raise when the single value is non-nil" do
        expect { attr.validate_required!("Acme") }.not_to raise_error
      end

      it "raises when the single value is nil" do
        expect { attr.validate_required!(nil) }.to raise_error(RestEasy::MissingAttributeError) { |e|
          expect(e.attribute_name).to eq(:name)
        }
      end

      it "does not raise when all of multiple values are non-nil" do
        expect { attr.validate_required!("Alice", "Smith") }.not_to raise_error
      end

      it "raises when any of multiple values is nil" do
        expect { attr.validate_required!("Alice", nil) }.to raise_error(RestEasy::MissingAttributeError)
        expect { attr.validate_required!(nil, "Smith") }.to raise_error(RestEasy::MissingAttributeError)
      end

      it "does not raise when called with no values (treats empty splat as nothing-to-check)" do
        # Documented behavior: callers must pass the values they intend to
        # validate. An empty splat is treated as "nothing to check" rather
        # than as "missing" so that future call sites with conditionally
        # empty arrays don't spuriously raise.
        expect { attr.validate_required! }.not_to raise_error
      end
    end
  end

  describe "#combine?" do
    let(:type) { RestEasy::Types::Coercible::String }

    it "is true when synthetic with no source_fields" do
      attr = described_class.new(
        model_name: :address, api_name: "Address", type:,
        flags: [:synthetic], target_fields: [:street, :city]
      )
      expect(attr.combine?).to be true
    end

    it "is false when synthetic with source_fields (merge / split)" do
      attr = described_class.new(
        model_name: :full_name, api_name: "FullName", type:,
        flags: [:synthetic], source_fields: [:first_name, :last_name]
      )
      expect(attr.combine?).to be false
    end

    it "is false for a non-synthetic standard attribute" do
      attr = described_class.new(model_name: :name, api_name: "Name", type:)
      expect(attr.combine?).to be false
    end
  end
end
