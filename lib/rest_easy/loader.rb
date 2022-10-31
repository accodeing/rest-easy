require "ostruct"

module RestEasy
  class Loader
    def call( json )
      return OpenStruct.new(json)
    end
  end
end

