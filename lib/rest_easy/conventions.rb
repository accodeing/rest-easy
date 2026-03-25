# frozen_string_literal: true

module RestEasy
  module Conventions
    class PascalCase
      def parse(api_name)
        # "DocumentNumber" → :document_number
        api_name.to_s
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
          .to_sym
      end

      def serialise(model_name)
        # :document_number → "DocumentNumber"
        model_name.to_s
          .split("_")
          .map(&:capitalize)
          .join
      end
    end

    class CamelCase
      def parse(api_name)
        # "documentNumber" → :document_number
        api_name.to_s
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
          .to_sym
      end

      def serialise(model_name)
        # :document_number → "documentNumber"
        parts = model_name.to_s.split("_")
        (parts[0] + parts[1..].map(&:capitalize).join)
      end
    end

    class SnakeCase
      def parse(api_name)
        # "document_number" → :document_number
        api_name.to_s.to_sym
      end

      def serialise(model_name)
        # :document_number → "document_number"
        model_name.to_s
      end
    end

    REGISTRY = {
      PascalCase: PascalCase.new,
      camelCase: CamelCase.new,
      snake_case: SnakeCase.new
    }.freeze

    def self.resolve(convention)
      case convention
      when Symbol
        REGISTRY.fetch(convention) do
          raise ArgumentError, "Unknown convention: #{convention}. Available: #{REGISTRY.keys.join(', ')}"
        end
      else
        convention # Custom object, pass through
      end
    end
  end
end
