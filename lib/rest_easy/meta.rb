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

    # Accessor shapes `method_missing` synthesises. Anchored, so operators
    # stay out: `<=` ends with `=`, and claiming it would let `meta <= 5`
    # read as a setter. `method_missing` itself is still unanchored and
    # writes `@data[:<]` for that call — see issue #6.
    #
    # POSIX classes rather than `[a-zA-Z_]\w*`, because Ruby identifiers are
    # not ASCII-only: `meta.företag = x` is a valid setter that
    # `method_missing` stores, so `respond_to?` has to claim it too.
    ACCESSOR_PATTERN = /\A[[:alpha:]_][[:word:]]*[=?]\z/
    private_constant :ACCESSOR_PATTERN

    # `method_missing` answers to any name, but this must not, because callers
    # routinely ask an object what it can do before calling it — Ruby's own
    # coercion probes (`to_hash` on double-splat, `to_ary`, `to_str`),
    # serialisation hooks (`marshal_dump`, `init_with`), and any library that
    # duck-types with `respond_to?`. Claiming those hands the caller the `nil`
    # that `method_missing` returns for an unknown key as though it were an
    # answer.
    #
    # Bare getters are therefore claimed only for keys actually held. Setters
    # and predicates are claimed unconditionally: writing is how a key comes
    # into existence, and an unset predicate is meaningfully `false`. No core
    # Ruby probe uses those two shapes — though library-level duck-typing can,
    # and ActiveSupport's `acts_like?(:date)` asking for `acts_like_date?` is
    # a known false positive. Closing it properly means declaring meta keys
    # up front, which is a breaking change — see issue #7.
    #
    # `@data` is guarded because `respond_to?` must never raise, and Ruby
    # allocates an instance before initialising it: Psych's `revive` probes
    # `init_with` on a bare allocation, and so does `Marshal.load` on a
    # payload written before this fix.
    #
    # This under-claims a bare getter for a key that was never set, which
    # `method_missing` still answers with `nil`. Reconciling the two halves
    # means declaring meta keys up front, and that is a 2.0 — see issue #7.
    def respond_to_missing?(name, include_private = false)
      return true if ACCESSOR_PATTERN.match?(name.to_s)
      return super unless @data

      @data.key?(name.to_sym) || super
    end
  end
end
