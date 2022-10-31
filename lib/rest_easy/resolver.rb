require 'dry/container'

module RestEasy
  class Resolver < Dry::Container::Resolver
    def call(container, key)
      container.fetch(key) do
        container.fetch("rest_easy.#{key}")
      end.call
    end
  end
end
