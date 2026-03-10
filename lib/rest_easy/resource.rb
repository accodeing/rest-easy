# frozen_string_literal: true

require "json"

module RestEasy
  class Resource
    extend Dry::Configurable

    # ── Types ─────────────────────────────────────────────────────────────
    # Include Types so the full Dry::Types vocabulary (Strict::String,
    # Coercible::Integer, Params::Date, etc.) is available without prefix.
    include Types

    # Shadow Ruby's built-in type names so that inside a regular class body
    # (not Class.new blocks), `String`, `Integer`, etc. resolve to
    # Dry::Types equivalents with coercion and constraint support.
    String  = Types::Coercible::String
    Integer = Types::Coercible::Integer
    Float   = Types::Coercible::Float
    Boolean = Types::Params::Bool
    Date    = Types::Params::Date

    # Map Ruby's built-in classes to Dry::Types equivalents.
    # Used by `attr` to resolve types passed from Class.new blocks
    # where constant lookup doesn't find our shadowed constants.
    TYPE_MAP = {
      ::String  => Types::Coercible::String,
      ::Integer => Types::Coercible::Integer,
      ::Float   => Types::Coercible::Float
    }.freeze

    # ── Configure DSL proxy ─────────────────────────────────────────────
    # Evaluates a block in a context where bare method calls map to config
    # setters:  `adapter :grpc`  →  config.adapter = :grpc
    # No-arg calls read, so nested access works naturally:
    #   `database.dsn = "sqlite:memory"`  →  config.database is returned,
    #   then .dsn= is called on the nested config directly.

    class ConfigureDSL < BasicObject
      def initialize(config)
        @config = config
      end

      def method_missing(name, *args)
        if args.empty?
          @config.__send__(name)
        else
          @config.__send__(:"#{name}=", args.length == 1 ? args.first : args)
        end
      end
    end

    # ── DSL helper for attribute parse/serialise blocks ─────────────────

    class AttributeBlockDSL
      attr_reader :parse_block, :serialise_block

      def parse(&block)
        @parse_block = block
      end

      def serialise(&block)
        @serialise_block = block
      end
    end

    # ── Simple wrappers for instance state ──────────────────────────────

    class ModelProxy
      def initialize(attributes)
        @attributes = attributes
        attributes.each_key do |attr_name|
          define_singleton_method(attr_name) { @attributes[attr_name] }
        end
      end

      def attributes
        @attributes
      end

      def respond_to_missing?(method_name, include_private = false)
        @attributes.key?(method_name.to_sym) || super
      end
    end

    class ShadowCopy
      def initialize(data)
        @data = data
      end

      def attributes
        @data
      end
    end

    # ── Class-level DSL ─────────────────────────────────────────────────

    class << self
      # -- settings -------------------------------------------------------

      def settings(&block)
        class_eval(&block)
      end

      def configure(&block)
        dsl = ConfigureDSL.new(config)
        dsl.instance_eval(&block)
      end

      # -- path / endpoint_path ------------------------------------------

      def path(value = :__unset__)
        if value == :__unset__
          @endpoint_path
        else
          @endpoint_path = value.to_s
        end
      end

      alias_method :endpoint_path, :path

      # -- metadata ------------------------------------------------------

      def metadata(**kwargs)
        if kwargs.any?
          own_metadata_defaults.merge!(kwargs)
        else
          all_metadata_defaults
        end
      end

      # -- attribute_convention ------------------------------------------

      def attribute_convention(value = nil)
        if value
          @attribute_convention = Conventions.resolve(value)
        else
          @attribute_convention ||
            (superclass.respond_to?(:attribute_convention) ? superclass.attribute_convention : nil) ||
            Conventions.resolve(parent&.config&.attribute_convention || :PascalCase)
        end
      end

      private

      def parent
        @parent ||= __get_parent
      end

      def __get_parent
        class_name = name
        return nil unless class_name

        parts = class_name.split("::")
        return nil if parts.length < 2

        # Walk up the namespace chain to find the namespace module that is extended with RestEasy.
        # For MyAPI::V2::Invoice, try MyAPI::V2 first, then MyAPI.
        (parts.length - 1).downto(1) do |i|
          candidate = Object.const_get(parts[0...i].join("::"))
          return candidate if candidate.const_defined?(:ExtendedByRestEasy, false)
        end

        nil
      rescue NameError
        nil
      end

      public

      # -- attr ----------------------------------------------------------

      def attr(name_or_mapping, *args, &block)
        # Determine attribute_api_name and attribute_model_name
        if name_or_mapping.is_a?(::Array)
          attribute_api_name = name_or_mapping[0].to_s
          attribute_model_name = name_or_mapping[1].to_sym
        else
          attribute_model_name = name_or_mapping.to_sym
          attribute_api_name = attribute_convention.serialise(attribute_model_name)
        end

        # Extract type (non-Symbol) and flags (Symbols)
        type = nil
        flags = []
        args.each do |arg|
          if arg.is_a?(::Symbol)
            flags << arg
          else
            type = resolve_type(arg)
          end
        end

        raise AttributeError, "Attribute :#{attribute_model_name} must have a type" if type.nil?

        # Handle block DSL for custom parse/serialise
        parse_block = nil
        serialise_block = nil
        source_fields = []
        target_fields = []
        if block
          block_params = block.parameters.select { |ptype, _| ptype == :opt || ptype == :req }

          if block_params.any?
            # Bare block with params = implicit parse block.
            # The parameter names are API field references (resolved via convention).
            parse_block = block
            source_fields = block_params.map { |_, pname| pname }
            flags << :synthetic unless flags.include?(:synthetic)
          else
            # DSL block — evaluate to extract parse/serialise sub-blocks
            dsl = AttributeBlockDSL.new
            dsl.instance_eval(&block)
            parse_block = dsl.parse_block
            serialise_block = dsl.serialise_block

            # Introspect parse block parameters: if 2+ params, this is a
            # synthetic attribute. The parameter names are the source API fields
            # (e.g. |first_name, last_name| → source_fields [:first_name, :last_name]).
            if parse_block
              params = parse_block.parameters.select { |ptype, _| ptype == :opt || ptype == :req }
              if params.length > 1
                flags << :synthetic unless flags.include?(:synthetic)
                source_fields = params.map { |_, pname| pname }
              end
            end

            # Introspect serialise block parameters: if 2+ params, the parameter
            # names are model field references to gather during serialisation.
            if serialise_block
              params = serialise_block.parameters.select { |ptype, _| ptype == :opt || ptype == :req }
              if params.length > 1
                target_fields = params.map { |_, pname| pname }
              end
            end
          end
        end

        # Handle :key flag
        if flags.include?(:key)
          if @key_attribute_name && @key_attribute_name != attribute_model_name
            warn "Warning: :#{@key_attribute_name} already defined as :key, ignoring :#{attribute_model_name} as :key"
          else
            @key_attribute_name = attribute_model_name
          end
        end

        # Register attribute definition
        own_attribute_definitions[attribute_model_name] = Attribute.new(
          model_name: attribute_model_name,
          api_name: attribute_api_name,
          type:,
          flags:,
          parse_block:,
          serialise_block:,
          source_fields:,
          target_fields:
        )

        # Define accessor method on the class
        define_method(attribute_model_name) { @model_attributes[attribute_model_name] }
      end

      # -- key -----------------------------------------------------------

      def key(attr_name, type = nil, *flags)
        if @key_attribute_name
          warn "Warning: key already defined as :#{@key_attribute_name}, overriding with :#{attr_name}"
        end
        if type
          self.attr(attr_name, type, *flags, :key)
        else
          self.attr(attr_name, *flags, :key)
        end
      end

      # -- ignore --------------------------------------------------------

      def ignore(*api_field_names)
        api_field_names.each do |field_name|
          own_ignored_fields << field_name.to_sym
        end
      end

      # -- hooks ---------------------------------------------------------

      def before_parse(&block)
        @before_parse_hook = block
      end

      def after_parse(&block)
        @after_parse_hook = block
      end

      def before_serialise(&block)
        @before_serialise_hook = block
      end

      def after_serialise(&block)
        @after_serialise_hook = block
      end

      # -- with_stub -----------------------------------------------------

      def with_stub(**defaults)
        @stub_defaults = defaults
      end

      # ── Attribute introspection ────────────────────────────────────────

      def attributes
        all_attribute_definitions.keys
      end

      def all_attribute_definitions
        parent = superclass.respond_to?(:all_attribute_definitions) ? superclass.all_attribute_definitions : {}
        parent.merge(own_attribute_definitions)
      end

      def all_ignored_fields
        parent = superclass.respond_to?(:all_ignored_fields) ? superclass.all_ignored_fields : []
        parent + own_ignored_fields
      end

      def key_attribute_name
        @key_attribute_name ||
          (superclass.respond_to?(:key_attribute_name) ? superclass.key_attribute_name : nil)
      end

      def stub_defaults
        parent = superclass.respond_to?(:stub_defaults) ? superclass.stub_defaults : {}
        (parent || {}).merge(@stub_defaults || {})
      end

      # ── Hook lookup (walks ancestor chain) ─────────────────────────────

      def resolve_before_parse_hook
        @before_parse_hook ||
          (superclass.respond_to?(:resolve_before_parse_hook) ? superclass.resolve_before_parse_hook : nil)
      end

      def resolve_after_parse_hook
        @after_parse_hook ||
          (superclass.respond_to?(:resolve_after_parse_hook) ? superclass.resolve_after_parse_hook : nil)
      end

      def resolve_before_serialise_hook
        @before_serialise_hook ||
          (superclass.respond_to?(:resolve_before_serialise_hook) ? superclass.resolve_before_serialise_hook : nil)
      end

      def resolve_after_serialise_hook
        @after_serialise_hook ||
          (superclass.respond_to?(:resolve_after_serialise_hook) ? superclass.resolve_after_serialise_hook : nil)
      end

      # ── Class-level operations ─────────────────────────────────────────

      def parse(api_data)
        allocate.tap { |instance| instance.send(:init_from_api, api_data) }
      end

      def stub(**model_data)
        defaults = stub_defaults || {}
        data = defaults.merge(model_data)
        allocate.tap { |instance| instance.send(:init_from_model, data) }
      end

      # CRUD operations

      def find(id)
        response = get(path: "#{endpoint_path}/#{id}")
        parse(response)
      end

      def all
        response = get(path: endpoint_path.to_s)
        unless response.is_a?(::Array)
          raise Error, "Expected Array from #{endpoint_path}, got #{response.class}. Does the response need unwrapping in before_parse?"
        end
        response.map { |data| parse(data) }
      end

      def save(instance)
        if instance.meta.new?
          create(instance)
        else
          update(instance)
        end
      end

      def create(instance)
        response = post(
          path: "#{endpoint_path}",
          body: instance.serialise
        )
        parse(response)
      end

      def update(instance)
        response = put(
          path: "#{endpoint_path}/#{instance.unique_id}",
          body: instance.serialise
        )
        parse(response)
      end

      def delete(id)
        parent.delete(path: "#{endpoint_path}/#{id}")
      end

      # HTTP primitives — delegate to the parent API module's connection

      def get(path:, params: {})
        parent.get(path:, params:)
      end

      def post(path:, body: nil)
        parent.post(path:, body:)
      end

      def put(path:, body: nil)
        parent.put(path:, body:)
      end

      private

      def own_attribute_definitions
        @own_attribute_definitions ||= {}
      end

      def own_ignored_fields
        @own_ignored_fields ||= []
      end

      def own_metadata_defaults
        @own_metadata_defaults ||= {}
      end

      def all_metadata_defaults
        if superclass.respond_to?(:metadata, true)
          superclass.metadata.merge(own_metadata_defaults)
        else
          own_metadata_defaults
        end
      end

      def resolve_type(type)
        return nil if type.nil?

        # If it's a Ruby built-in class, map to Dry::Types equivalent
        if type.is_a?(::Class)
          TYPE_MAP.fetch(type, type)
        else
          type # Already a Dry::Types type (including constrained), pass through
        end
      end
    end

    # ── Instance ─────────────────────────────────────────────────────────

    # Delegate class DSL methods so hooks can call them via instance_exec
    def endpoint_path
      self.class.endpoint_path
    end

    def config
      self.class.config
    end

    attr_reader :meta

    def initialize(api_data = {})
      init_from_api(api_data)
    end

    def model
      ModelProxy.new(@model_attributes)
    end

    def api
      ShadowCopy.new(@api_data)
    end

    def unique_id
      key_name = self.class.key_attribute_name
      key_name ? @model_attributes[key_name] : nil
    end

    def update(changes = {}, **kwargs)
      changes = changes.merge(kwargs) unless kwargs.empty?
      return self if changes.empty?

      new_model = @model_attributes.merge(changes)
      new_instance = self.class.allocate
      new_instance.send(:init_from_update, new_model, @api_data, changes)
      new_instance
    end

    def __changes__
      @changes || {}
    end

    def serialise
      klass = self.class

      # Run before_serialise hook on the instance
      # Input: model_attributes. Side-effect only; return value ignored.
      hook = klass.resolve_before_serialise_hook
      instance_exec(@model_attributes, &hook) if hook

      result = {}

      # Serialise all attributes
      klass.all_attribute_definitions.each do |_model_name, attr_def|
        next if attr_def.read_only?
        value = @model_attributes[attr_def.model_name]

        if attr_def.target_fields.any?
          # Multi-param serialise: gather model values by param names, splat into block
          model_values = attr_def.target_fields.map { |fn| @model_attributes[fn] }
          result[attr_def.api_name] = attr_def.serialise_value(*model_values)
        elsif attr_def.source_fields.any?
          serialised = attr_def.serialise_value(value)
          if serialised.is_a?(::Array)
            # Array return: zip with source field API names
            convention = klass.attribute_convention
            attr_def.source_fields.zip(serialised).each do |field_name, field_value|
              api_key = convention.serialise(field_name)
              result[api_key] = field_value
            end
          elsif serialised.is_a?(::Hash)
            # Hash return: merge into result
            result.merge!(serialised)
          else
            result[attr_def.api_name] = serialised
          end
        else
          result[attr_def.api_name] = attr_def.serialise_value(value)
        end
      end

      # Merge ignored fields from shadow copy
      if @api_data && !@api_data.empty?
        known_api_names = klass.all_attribute_definitions.values.map(&:api_name)
        @api_data.each do |api_key, value|
          unless known_api_names.include?(api_key) || result.key?(api_key)
            result[api_key] = value
          end
        end
      end

      # Run after_serialise hook on the instance
      # Input: serialised_data, model. Output: final serialised_data.
      hook = klass.resolve_after_serialise_hook
      if hook
        result = instance_exec(result, model, &hook)
      end

      result
    end

    def to_json(*_args)
      model_hash = @model_attributes.transform_keys(&:to_s)
      ::JSON.generate(model_hash)
    end

    def to_api
      ::JSON.generate(serialise)
    end

    def ==(other)
      other.is_a?(self.class) && self.class == other.class &&
        @model_attributes == other.send(:model_attributes_hash)
    end

    alias_method :eql?, :==

    def hash
      [self.class, @model_attributes].hash
    end

    private

    def model_attributes_hash
      @model_attributes
    end

    def init_from_api(api_data)
      klass = self.class

      # Set up instance state so hooks have access to api, model, meta
      @api_data = api_data.is_a?(::Hash) ? api_data.dup : {}
      @model_attributes = {}
      @changes = {}
      @meta = Meta.new(new_record: false, saved: true, **klass.metadata)

      # Run before_parse hook on the instance
      # Input: raw api_data. Output: transformed api_data (e.g. unwrapped envelope).
      hook = klass.resolve_before_parse_hook
      if hook
        api_data = instance_exec(api_data, &hook)
      end

      # Update shadow copy with possibly unwrapped data
      @api_data = api_data.is_a?(::Hash) ? api_data.dup : {}

      return unless api_data.is_a?(::Hash)

      # Parse all attributes
      klass.all_attribute_definitions.each do |model_name, attr_def|
        if attr_def.source_fields.any?
          # Source fields declared via block params: extract individual
          # values from api_data using convention, splat into parse block.
          convention = klass.attribute_convention
          raw_values = attr_def.source_fields.map do |field_name|
            api_key = convention.serialise(field_name)
            api_data[api_key]
          end
          @model_attributes[model_name] = attr_def.parse_value(*raw_values)
        else
          raw_value = api_data[attr_def.api_name]

          if raw_value.nil? && attr_def.required?
            raise MissingAttributeError.new(model_name)
          end

          if raw_value.nil?
            @model_attributes[model_name] = nil
          else
            @model_attributes[model_name] = attr_def.parse_value(raw_value)
          end
        end
      end

      # Warn about API fields that are neither declared attrs nor explicitly ignored
      convention = klass.attribute_convention
      known_api_keys = klass.all_attribute_definitions.values.flat_map do |ad|
        keys = [ad.api_name]
        ad.source_fields.each { |sf| keys << convention.serialise(sf) }
        keys
      end
      ignored_api_keys = klass.all_ignored_fields.map { |f| convention.serialise(f) }
      known_api_keys.concat(ignored_api_keys)

      api_data.each_key do |api_key|
        unless known_api_keys.include?(api_key)
          warn "RestEasy: unknown API field '#{api_key}' in #{klass.name || 'Resource'}. " \
               "Declare it with attr, or silence this warning with ignore."
        end
      end

      # Run after_parse hook on the instance
      # Input: model (parsed attributes), api (shadow copy). Side-effect only; return value ignored.
      hook = klass.resolve_after_parse_hook
      if hook
        instance_exec(model, api, &hook)
      end
    end

    def init_from_model(model_data)
      klass = self.class
      @api_data = {}
      @model_attributes = {}
      @changes = {}
      @meta = Meta.new(new_record: true, saved: false, **klass.metadata)

      # Set attributes from model data
      klass.all_attribute_definitions.each do |model_name, _attr_def|
        @model_attributes[model_name] = model_data[model_name] if model_data.key?(model_name)
      end
    end

    def init_from_update(new_model_attrs, original_api_data, changes)
      @api_data = original_api_data
      @model_attributes = new_model_attrs
      @changes = changes
      @meta = Meta.new(new_record: false, saved: true, **self.class.metadata)
    end
  end
end
