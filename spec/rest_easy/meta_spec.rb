# frozen_string_literal: true

require "yaml"

RSpec.describe RestEasy::Meta do
  describe "reading and writing" do
    it "reads a key it was constructed with" do
      meta = described_class.new(partial: true)

      expect(meta.partial).to be true
    end

    it "writes a key that did not exist" do
      meta = described_class.new
      meta.etag = "abc123"

      expect(meta.etag).to eq("abc123")
    end

    it "returns nil for a bare getter on an unset key" do
      expect(described_class.new.never_set).to be_nil
    end

    it "returns false for a predicate on an unset key" do
      expect(described_class.new.never_set?).to be false
    end
  end

  describe "#respond_to?" do
    it "claims a bare getter for a key it holds" do
      expect(described_class.new(partial: true).respond_to?(:partial)).to be true
    end

    it "does not claim a bare getter for a key it does not hold" do
      expect(described_class.new.respond_to?(:never_set)).to be false
    end

    it "claims setters, since writing is how a key comes into existence" do
      expect(described_class.new.respond_to?(:etag=)).to be true
    end

    it "claims predicates, since an unset predicate is meaningfully false" do
      expect(described_class.new.respond_to?(:never_set?)).to be true
    end

    # A blanket `true` here makes Ruby's implicit probes take the `nil` from
    # `method_missing` as a real implementation.
    it "does not claim protocol methods Ruby probes for implicitly" do
      meta = described_class.new(partial: true)

      probes = %i[marshal_dump marshal_load _dump init_with encode_with
                  to_ary to_hash to_str to_int to_io to_proc]

      expect(probes.reject { |probe| meta.respond_to?(probe) }).to eq(probes)
    end

    # `<=` ends with "=", so an unanchored setter check would claim it and
    # let `meta <= 5` read as a write to @data[:<].
    it "does not claim operators that happen to end in = or ?" do
      meta = described_class.new

      # Only operators Object does not already define — `==` and `<=>` are
      # real methods and respond_to? is rightly true for them.
      expect(%i[<= >=].reject { |op| meta.respond_to?(op) }).to eq(%i[<= >=])
    end

    # respond_to? must never raise. Ruby allocates before initialising, so
    # @data can legitimately be nil when a probe arrives.
    it "does not raise when probed on an uninitialised instance" do
      expect { described_class.allocate.respond_to?(:init_with) }.not_to raise_error
    end
  end

  describe "Marshal round-trip" do
    # Regression: Meta used to claim `marshal_dump`, so `dump` wrote an empty
    # payload and `load` raised NoMethodError from inside `method_missing`.
    # Rails' :memory_store marshals every cache entry, so any cached resource
    # blew up on the first cache hit.
    it "preserves meta state through dump and load" do
      meta = described_class.new(new_record: false, saved: true, partial: true)

      restored = Marshal.load(Marshal.dump(meta))

      expect(restored.new?).to be false
      expect(restored.saved?).to be true
      expect(restored.partial?).to be true
    end

    # Spot-checking individual keys would not have caught the original bug on
    # its own — @data came back nil, so *every* key was lost. Compare the
    # whole bag.
    it "preserves every key, not just the ones a caller thinks to check" do
      meta = described_class.new(saved: true, partial: true, etag: "abc", total_pages: 5)

      restored = Marshal.load(Marshal.dump(meta))

      expect(restored.instance_variable_get(:@data))
        .to eq(meta.instance_variable_get(:@data))
    end

    it "round-trips meta set by class-level defaults" do
      # Named, because Marshal refuses to dump an anonymous class.
      stub_const("MarshalableResource", Class.new(RestEasy::Resource) do
        attr :name, String
        metadata partial: true
      end)

      restored = Marshal.load(Marshal.dump(MarshalableResource.parse({ "Name" => "Test" })))

      expect(restored.name).to eq("Test")
      expect(restored.meta.partial?).to be true
      expect(restored.meta.new?).to be false
    end

    # The path consumers actually use: a before_parse hook writes to the
    # MetaCollector, whose to_h is merged into the instance's Meta.
    it "round-trips meta collected by a before_parse hook" do
      stub_const("HookMarshalResource", Class.new(RestEasy::Resource) do
        attr :name, String

        before_parse do |data, meta|
          meta.partial = true
          data
        end
      end)

      restored = Marshal.load(Marshal.dump(HookMarshalResource.parse({ "Name" => "Test" })))

      expect(restored.meta.partial?).to be true
    end

    # Collections are what get cached in practice — a list endpoint's worth
    # of records, each carrying its own meta.
    it "round-trips every instance in a parsed collection" do
      stub_const("CollectionMarshalResource", Class.new(RestEasy::Resource) do
        attr :name, String
        metadata partial: true
      end)

      parsed = CollectionMarshalResource.parse([{ "Name" => "A" }, { "Name" => "B" }])
      restored = Marshal.load(Marshal.dump(parsed))

      expect(restored.map(&:name)).to eq(%w[A B])
      expect(restored.map { |instance| instance.meta.partial? }).to all(be true)
    end

    it "round-trips a stubbed instance's lifecycle meta" do
      stub_const("StubMarshalResource", Class.new(RestEasy::Resource) do
        attr :name, String
      end)

      restored = Marshal.load(Marshal.dump(StubMarshalResource.stub(name: "Draft")))

      expect(restored.meta.new?).to be true
      expect(restored.meta.saved?).to be false
    end
  end

  describe "YAML round-trip" do
    # Psych's `revive` allocates the object and then probes `init_with`
    # before any ivar exists, so this exercises the uninitialised path.
    it "preserves meta state through dump and load" do
      meta = described_class.new(saved: true, partial: true)

      restored = YAML.unsafe_load(YAML.dump(meta))

      expect(restored.saved?).to be true
      expect(restored.partial?).to be true
    end
  end

  describe "loading a payload written before this fix" do
    # Meta used to claim `marshal_dump`, so dump wrote `nil` as the object's
    # whole state. Such payloads can still be sitting in a warm cache. They
    # cannot be revived, but they must fail legibly rather than as a
    # NoMethodError from inside respond_to?.
    it "raises a legible TypeError rather than NoMethodError" do
      stale = "\x04\bU:\x13RestEasy::Meta0"

      expect { Marshal.load(stale) }
        .to raise_error(TypeError, /needs to have method `marshal_load'/)
    end
  end

  describe "implicit coercion" do
    # These assert on the message, not just the class. Both the broken and
    # fixed versions raise TypeError; only the broken one offers a `to_hash`
    # that returns nil, which Ruby reports as "#to_hash gives NilClass".
    it "is not offered as a hash to an implicit conversion" do
      expect { { **described_class.new } }
        .to raise_error(TypeError, /no implicit conversion/)
    end

    it "is not offered as an array to an implicit conversion" do
      expect { [1] + described_class.new }
        .to raise_error(TypeError, /no implicit conversion/)
    end

    it "is not offered as a string to an implicit conversion" do
      expect { "x" + described_class.new }
        .to raise_error(TypeError, /no implicit conversion/)
    end
  end
end
