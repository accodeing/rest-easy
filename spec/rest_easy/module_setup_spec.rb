# frozen_string_literal: true

RSpec.describe "Module setup with extend RestEasy" do
  after do
    Object.send(:remove_const, :SetupTestApi) if defined?(SetupTestApi)
  end

  describe "extending a module" do
    it "creates a Settings class" do
      module SetupTestApi
        extend RestEasy
      end

      expect(SetupTestApi.const_defined?(:Settings)).to be true
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

    it "does not attach the logger middleware when logger is unset" do
      module SetupTestApi
        extend RestEasy

        configure do |config|
          config.base_url = "https://api.example.com"
        end
      end

      handlers = SetupTestApi.faraday_connection.builder.handlers
      expect(handlers).not_to include(Faraday::Response::Logger)
    end

    it "attaches the Faraday logger middleware when logger is set" do
      module SetupTestApi
        extend RestEasy

        configure do |config|
          config.base_url = "https://api.example.com"
          config.logger = Logger.new(IO::NULL)
        end
      end

      handlers = SetupTestApi.faraday_connection.builder.handlers
      expect(handlers).to include(Faraday::Response::Logger)
    end

    describe "header redaction" do
      %w[Authorization Proxy-Authorization Cookie].each do |header_name|
        it "redacts the #{header_name} request header by default" do
          io = StringIO.new

          module SetupTestApi
            extend RestEasy

            configure do |config|
              config.base_url = "https://api.example.com"
            end
          end
          SetupTestApi.configure { |c| c.logger = Logger.new(io) }
          SetupTestApi.connection do |f|
            f.adapter :test do |stub|
              stub.get("/x") { [200, {}, "ok"] }
            end
          end

          SetupTestApi.get(path: "/x", headers: { header_name => "super-secret-value" })

          expect(io.string).to include("[FILTERED]")
          expect(io.string).not_to include("super-secret-value")
        end
      end

      it "redacts the Set-Cookie response header by default" do
        io = StringIO.new

        module SetupTestApi
          extend RestEasy

          configure do |config|
            config.base_url = "https://api.example.com"
          end
        end
        SetupTestApi.configure { |c| c.logger = Logger.new(io) }
        SetupTestApi.connection do |f|
          f.adapter :test do |stub|
            stub.get("/x") { [200, { "Set-Cookie" => "session=super-secret-value" }, "ok"] }
          end
        end

        SetupTestApi.get(path: "/x")

        expect(io.string).to include("[FILTERED]")
        expect(io.string).not_to include("super-secret-value")
      end
    end

    it "does not log bodies by default" do
      io = StringIO.new

      module SetupTestApi
        extend RestEasy

        configure do |config|
          config.base_url = "https://api.example.com"
        end
      end
      SetupTestApi.configure { |c| c.logger = Logger.new(io) }
      SetupTestApi.connection do |f|
        f.adapter :test do |stub|
          stub.get("/x") { [200, { "Content-Type" => "application/json" }, '{"secret":"abc123"}'] }
        end
      end

      SetupTestApi.get(path: "/x")

      # Sanity-check that the middleware actually ran — without this, the
      # absence of the secret could mean redaction worked OR that nothing
      # was logged at all.
      expect(io.string).to include("GET")
      expect(io.string).not_to include("abc123")
    end

    it "logs bodies when log_bodies is true" do
      io = StringIO.new

      module SetupTestApi
        extend RestEasy

        configure do |config|
          config.base_url = "https://api.example.com"
        end
      end
      SetupTestApi.configure do |c|
        c.logger     = Logger.new(io)
        c.log_bodies = true
      end
      SetupTestApi.connection do |f|
        f.adapter :test do |stub|
          stub.get("/x") { [200, { "Content-Type" => "application/json" }, '{"value":"visible"}'] }
        end
      end

      SetupTestApi.get(path: "/x")

      expect(io.string).to include("visible")
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
