# frozen_string_literal: true

RSpec.describe "Module setup with extend RestEasy" do
  after do
    Object.send(:remove_const, :SetupTestApi) if defined?(SetupTestApi)
  end

  describe "extending a module" do
    it "creates an Application container" do
      module SetupTestApi
        extend RestEasy
      end

      expect(SetupTestApi.const_defined?(:Application)).to be true
    end

    it "creates a Settings class" do
      module SetupTestApi
        extend RestEasy
      end

      expect(SetupTestApi.const_defined?(:Settings)).to be true
    end

    it "creates a Deps injector" do
      module SetupTestApi
        extend RestEasy
      end

      expect(SetupTestApi.const_defined?(:Deps)).to be true
    end

    it "prevents double registration" do
      module SetupTestApi
        extend RestEasy
      end

      expect {
        SetupTestApi.extend(RestEasy)
      }.to raise_error(StandardError, /Double registration/)
    end
  end

  describe "configure" do
    it "sets base_url" do
      module SetupTestApi
        extend RestEasy

        configure do |config|
          config.base_url = "https://api.example.com"
        end
      end

      expect(SetupTestApi.config.base_url).to eq("https://api.example.com")
    end

    it "sets max_retries" do
      module SetupTestApi
        extend RestEasy

        configure do |config|
          config.max_retries = 5
        end
      end

      expect(SetupTestApi.config.max_retries).to eq(5)
    end

    it "sets authentication module" do
      auth = RestEasy::Auth::Null.new

      module SetupTestApi
        extend RestEasy
      end

      SetupTestApi.configure do |config|
        config.authentication = auth
      end

      expect(SetupTestApi.config.authentication).to eq(auth)
    end
  end

  describe "connection" do
    it "stores the connection block for lazy execution" do
      module SetupTestApi
        extend RestEasy

        configure do |config|
          config.base_url = "https://api.example.com"
        end
      end

      SetupTestApi.connection do |conn|
        # configure middleware, SSL, etc.
      end

      expect(SetupTestApi.connection).to be_a(Proc)
    end

    it "creates a Faraday connection lazily" do
      module SetupTestApi
        extend RestEasy

        configure do |config|
          config.base_url = "https://api.example.com"
        end
      end

      expect(SetupTestApi.faraday_connection).to be_a(Faraday::Connection)
    end

    it "passes the connection block to Faraday" do
      block_called = false

      module SetupTestApi
        extend RestEasy

        configure do |config|
          config.base_url = "https://api.example.com"
        end
      end

      SetupTestApi.connection do |conn|
        block_called = true
      end

      SetupTestApi.faraday_connection # triggers lazy creation
      expect(block_called).to be true
    end
  end

  describe "container registration" do
    it "allows registering custom services" do
      module SetupTestApi
        extend RestEasy
        register("custom.service", -> { "hello" })
      end

      expect(SetupTestApi.resolve("custom.service")).to eq("hello")
    end

    it "supports bracket syntax for resolve" do
      module SetupTestApi
        extend RestEasy
        register("custom.service", -> { "hello" })
      end

      expect(SetupTestApi["custom.service"]).to eq("hello")
    end
  end

  describe "isolation between modules" do
    after do
      Object.send(:remove_const, :ApiOne) if defined?(ApiOne)
      Object.send(:remove_const, :ApiTwo) if defined?(ApiTwo)
    end

    it "gives each module its own container" do
      module ApiOne
        extend RestEasy
        configure do |config|
          config.base_url = "https://one.example.com"
        end
      end

      module ApiTwo
        extend RestEasy
        configure do |config|
          config.base_url = "https://two.example.com"
        end
      end

      expect(ApiOne.config.base_url).to eq("https://one.example.com")
      expect(ApiTwo.config.base_url).to eq("https://two.example.com")
    end
  end
end
