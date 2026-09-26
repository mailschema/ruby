# frozen_string_literal: true

module Mailschema
  # The schema objects within a schema, as JSON Schema 2020-12 nests them.
  module SchemaWalk
    # The keywords whose value is a schema, a list of schemas, or a map from names to
    # schemas. A name in a map is never a keyword, whatever it is called.
    SUBSCHEMA = %w[additionalProperties propertyNames items contains not if then else unevaluatedItems
                   unevaluatedProperties contentSchema].freeze
    LISTS = %w[allOf anyOf oneOf prefixItems].freeze
    MAPS = %w[properties patternProperties $defs dependentSchemas].freeze

    module_function

    # Every schema object within a schema, the schema itself first.
    def nodes(schema)
      return [] unless schema.is_a?(Hash)

      [schema] +
        SUBSCHEMA.flat_map { |keyword| nodes(schema[keyword]) } +
        LISTS.flat_map { |keyword| schema[keyword].is_a?(Array) ? schema[keyword].flat_map { nodes(_1) } : [] } +
        MAPS.flat_map { |keyword| schema[keyword].is_a?(Hash) ? schema[keyword].values.flat_map { nodes(_1) } : [] }
    end

    # Every value a keyword has in the schema objects within a schema.
    def values(schema, keyword) = nodes(schema).filter_map { |node| node[keyword] if node.key?(keyword) }
  end
  private_constant :SchemaWalk
end
