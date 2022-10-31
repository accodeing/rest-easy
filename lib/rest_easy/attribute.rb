module RestEasy
  class Attribute
    def initialize( api_name:, model_name:, type: )
      @state = {
        api: api_name.to_sym,
        model: model_name.to_sym
      }
      @type = type
    end

    def [](name)
      @state[name]
    end

  end
end
