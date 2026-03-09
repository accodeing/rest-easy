# frozen_string_literal: true

module RestEasy
  module Refinements
    refine Symbol do
      def <=>(other)
        [self, other]
      end
    end

    refine String do
      def <=>(other)
        [self, other]
      end
    end
  end
end
