# frozen_string_literal: true

module Mailschema
  # JSON Pointer (RFC 6901).
  module Pointer
    # What a pointer names when nothing is there, as distinct from null.
    MISSING = Object.new.freeze
    INDEX = /\A(?:0|[1-9][0-9]*)\z/

    module_function

    def escape(name) = name.to_s.gsub("~", "~0").gsub("/", "~1")

    def segments(pointer) = pointer.split("/", -1).drop(1).map { |segment| segment.gsub("~1", "/").gsub("~0", "~") }

    # The pointer, or its nearest ancestor no longer than limit characters.
    def within(pointer, limit)
      tokens = pointer.split("/", -1)
      tokens.pop while tokens.join("/").length > limit
      tokens.join("/")
    end

    # The value a pointer names through objects and arrays, or MISSING.
    def resolve(value, pointer)
      segments(pointer).reduce(value) do |current, name|
        case current
        when Hash then current.fetch(name) { return MISSING }
        when Array then INDEX.match?(name) && name.to_i < current.size ? current[name.to_i] : (return MISSING)
        else return MISSING
        end
      end
    end

    # The value a pointer names through object members only, or MISSING. The contract
    # rules bind form fields only through object properties, so no binding indexes an
    # array.
    def member(value, pointer)
      segments(pointer).reduce(value) do |current, name|
        return MISSING unless current.is_a?(Hash) && current.key?(name)

        current[name]
      end
    end
  end
  private_constant :Pointer
end
