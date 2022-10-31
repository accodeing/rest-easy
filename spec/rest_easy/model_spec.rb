# frozen_string_literal: true

require "rest-easy/refinements"
require "rest-easy/types"
require "rest-easy/model"

RSpec.describe RestEasy::Model do
  before do
    class TestModel < described_class
      using RestEasy::Refinements

      attr '@urlTaxReductionList' <=> :tax_reduction_list_url, RestEasy::Types::Coercible::String, :read_only, :optional
      attr :from_first_name <=> :first_name, RestEasy::Types::Coercible::String, :optional
      attr :id, RestEasy::Types::Coercible::Integer
    end
  end

  describe "validations" do
    context "for optional attribute" do
      let( :tax_reduction_list_url_validation ){ TestModel['validation_map'][:tax_reduction_list_url] }
      subject( :populated ){ tax_reduction_list_url_validation.call({tax_reduction_list_url: 1234}) }
      subject( :empty ){ tax_reduction_list_url_validation.call({}) }

      it "works on correct input" do
        expect( populated ).to be_success
        expect( populated.to_h ).to include(
          tax_reduction_list_url: "1234"
        )
        expect( populated.errors.to_h ).to eq({})
      end

      it "works on empty input" do
        expect( empty ).to be_success
        expect( empty.to_h ).to eq({})
        expect( empty.errors.to_h ).to eq({})
      end
    end

    context "for optional attribute" do
      let( :id_validation ){ TestModel['validation_map'][:id] }
      subject( :populated ){ id_validation.call({id: "1234"}) }
      subject( :empty ){ id_validation.call({}) }

      it "works on correct input" do
        expect( populated ).to be_success
        expect( populated.to_h ).to include(
          id: 1234
        )
        expect( populated.errors.to_h ).to eq({})
      end

      it "works on empty input" do
        expect( empty ).to be_failure
        expect( empty.to_h ).to eq({})
        expect( empty.errors.to_h ).to include(
          id: ["is missing"]
        )
      end
    end
  end

  describe "translations" do
    context "persistance" do
      subject( :string_to_symbol_mapper ){ TestModel['translations'][0] }
      subject( :symbol_to_symbol_mapper ){ TestModel['translations'][1] }
      subject( :symbol_without_mapper ){ TestModel['translations'][2] }

      it "works with 'string' <=> :symbol mapping" do
        expect( string_to_symbol_mapper ).to have_attributes(
          from: :@urlTaxReductionList,
          to: :tax_reduction_list_url
        )
      end

      it "works with :symbol <=> :symbol mapping" do
        expect( symbol_to_symbol_mapper ).to have_attributes(
          from: :from_first_name,
          to: :first_name
        )
      end

      it "works with just :symbol" do
        expect( symbol_without_mapper ).to have_attributes(
          from: :id,
          to: :id
        )
      end
    end

    context "when called" do
      let( :input ) do
        {
          '@urlTaxReductionList' => 'https://example.com',
          :from_first_name => 'Test',
          :id => 1234
        }
      end
      subject( :instance ){ TestModel.new.( input ) }

      it "transforms keys" do
        expect( instance ).to have_key( :tax_reduction_list_url )
        expect( instance ).to have_key( :first_name )
        expect( instance ).to have_key( :id )
        expect( instance.keys.length ).to be(3)
      end
    end
  end
end
