require 'dry/system/container'

module RestEasy
  class Application < Dry::System::Container
    extend Dry::Configurable

    config.root = Pathname('./')
  end
end
