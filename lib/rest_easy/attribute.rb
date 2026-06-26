# frozen_string_literal: true

module RestEasy
  # Stores the definition of a single attribute declared via the Resource DSL.
  class Attribute
    attr_reader :model_name, :api_name, :type, :flags, :parse_block, :serialise_block, :source_fields, :target_fields

    def initialize(model_name:, api_name:, type:, flags: [], parse_block: nil, serialise_block: nil, source_fields: [], target_fields: [])
      @model_name = model_name.to_sym
      @api_name = api_name.to_s
      @type = type
      @flags = Array(flags).map(&:to_sym)
      @parse_block = parse_block
      @serialise_block = serialise_block
      @source_fields = source_fields
      @target_fields = target_fields
    end

    def required?
      @flags.include?(:required)
    end

    def optional?
      @flags.include?(:optional)
    end

    def read_only?
      @flags.include?(:read_only)
    end

    def key?
      @flags.include?(:key)
    end

    def synthetic?
      @flags.include?(:synthetic)
    end

    def validate_required!(*values)
      return unless required?
      return if values.none?(&:nil?)

      raise RestEasy::MissingAttributeError.new(model_name)
    end

    def coerce(value)
      @type[value]
    rescue Dry::Types::ConstraintError, Dry::Types::CoercionError => e
      raise RestEasy::ConstraintError.new(
        @model_name,
        value,
        "Attribute '#{@model_name}': #{e.message}"
      )
    end

    def parse_value(*raw_values)
      value = @parse_block ? @parse_block.call(*raw_values) : raw_values.first
      coerce(value)
    end

    def serialise_value(*model_values)
      if @serialise_block
        @serialise_block.call(*model_values)
      else
        to_json_value(model_values.first)
      end
    end

    private

    def to_json_value(value)
      case value
      when ::String, ::Integer, ::Float, ::NilClass, true, false, ::Array, ::Hash
        value
      else
        value.to_s
      end
    end
  end
end
