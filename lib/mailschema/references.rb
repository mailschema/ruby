# frozen_string_literal: true

module Mailschema
  # The references of a contract's schemas. Each must name a schema inside a pinned
  # dependency when the contract loads, so none can fail when a request arrives.
  module References
    # A plain JSON Pointer fragment: nothing percent-encoded, nothing to decode.
    FRAGMENT = %r{\A(?:/[A-Za-z0-9._~!$&'()*+,;=:@-]*)*\z}
    SCHEMA = [Hash, TrueClass, FalseClass].freeze
    # Keywords that resolve by scope rather than by a pinned address.
    UNPINNED = %w[$dynamicRef $recursiveRef $dynamicAnchor $recursiveAnchor $anchor].freeze

    module_function

    # Raises InvalidContract for the first keyword in the contract's schemas, or the
    # pinned schemas the gem does not bundle, that resolves by scope. In the contract's
    # own schemas, it raises for an $id or $schema anywhere but the request schema's
    # root, which would move references or change the dialect a subschema is read in;
    # for a type list; for autocomplete, the form fields block's annotation; and for a
    # reference that is not a string or names no schema in the pinned documents, by URL.
    def verify(inline, request_schema, pinned, unbundled)
      [*inline, request_schema, *unbundled].each do |schema|
        found = UNPINNED.find { |keyword| SchemaWalk.values(schema, keyword).any? }
        raise InvalidContract, "#{found} is not pinned by any digest" if found
      end
      [*inline, request_schema].each do |schema|
        nodes = SchemaWalk.nodes(schema)
        verify_keywords(schema.equal?(request_schema) ? nodes.drop(1) : nodes, nodes)
        refs = SchemaWalk.values(schema, "$ref")
        raise InvalidContract, "a $ref is not a string" unless refs.all?(String)

        refs.each { |ref| verify_one(ref, pinned) }
      end
    end

    # `nested` are the schema objects that may not declare $id or $schema.
    def verify_keywords(nested, nodes)
      raise InvalidContract, "a nested $id would move references" if nested.any? { _1.key?("$id") }
      raise InvalidContract, "a nested $schema would change the dialect" if nested.any? { _1.key?("$schema") }
      raise InvalidContract, "type names one type, never a list" if nodes.any? { _1["type"].is_a?(Array) }
      return unless nodes.any? { _1.key?("autocomplete") }

      raise InvalidContract, "autocomplete belongs to the form fields block"
    end

    def verify_one(ref, pinned)
      base, fragment = ref.split("#", 2)
      raise InvalidContract, "#{ref} is not a pinned dependency" unless pinned.key?(base)

      fragment = fragment.to_s
      unless fragment.empty? || fragment.start_with?("/")
        raise InvalidContract, "#{ref} names an anchor, not a JSON Pointer"
      end
      raise InvalidContract, "#{ref} is not a plain JSON Pointer" unless FRAGMENT.match?(fragment)

      target = Pointer.resolve(pinned[base], fragment)
      raise InvalidContract, "#{ref} does not name a schema" unless SCHEMA.include?(target.class)
    end
    private_class_method :verify_one
  end
  private_constant :References
end
