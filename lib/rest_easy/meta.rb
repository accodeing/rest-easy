# frozen_string_literal: true

module RestEasy
  class Meta
    def initialize(new_record: false, saved: false, **defaults)
      @data = { new: new_record, saved: saved, **defaults }
    end

    def new?
      @data[:new]
    end

    def saved?
      @data[:saved]
    end

    def method_missing(name, *args)
      key = name.to_s
      if key.end_with?("=")
        @data[key.chomp("=").to_sym] = args.first
      elsif key.end_with?("?")
        !!@data[key.chomp("?").to_sym]
      else
        @data[name.to_sym]
      end
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end
end
