# frozen_string_literal: true

require "rest-easy/refinements"
require "rest-easy/types"
require "rest-easy/attribute"

RSpec.describe RestEasy::Attribute do
  before do
    class TestAttribute < described_class

    end
  end

  describe "" do
    context "" do
      subject( :populated ){ tax_reduction_list_url_validation.call({tax_reduction_list_url: 1234}) }

      it "works on correct input" do
        expect( populated ).to be_success
        expect( populated.to_h ).to include(
          tax_reduction_list_url: "1234"
        )
        expect( populated.errors.to_h ).to eq({})
      end
    end
  end
end
