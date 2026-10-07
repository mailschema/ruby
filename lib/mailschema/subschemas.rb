# frozen_string_literal: true

module Mailschema
  # The schemas within a JSON Schema 2020-12 schema, by the JSON Pointers that name them.
  module Subschemas
    SCHEMA = %w[additionalProperties propertyNames items contains not if then else unevaluatedItems
                unevaluatedProperties].freeze
    SCHEMA_LISTS = %w[allOf anyOf oneOf prefixItems].freeze
    SCHEMA_MAPS = %w[properties patternProperties $defs dependentSchemas].freeze
    # The keywords that apply their subschemas to the value itself, not to a member or item.
    IN_PLACE = %w[not if then else allOf anyOf oneOf dependentSchemas].freeze

    class << self
      # Every schema within a schema, object or boolean, with its JSON Pointer, the schema
      # itself first.
      def all(schema, pointer)
        return [[pointer, schema]] if [true, false].include?(schema)
        return [] unless schema.is_a?(Hash)

        [[pointer, schema], *children(schema, pointer).flat_map { |_keyword, at, item| all(item, at) }]
      end

      # Whether applying the schema can never finish: from its root, a chain of $ref and
      # in-place keywords returns to a schema without moving into a member or item.
      def endless?(schema)
        links = all(schema, "").to_h { |at, node| [at, node.is_a?(Hash) ? links(at, node) : []] }
        reachable = [""]
        seen = Set[""]
        reachable.each { |at| links.fetch(at, []).map(&:first).each { |to| reachable << to if seen.add?(to) } }
        state = {}
        visit = lambda do |at|
          return state[at] == :open if state.key?(at)

          state[at] = :open
          looped = links.fetch(at, []).any? { |to, in_place| in_place && visit.call(to) }
          state[at] = :done
          looped
        end
        reachable.any? { |at| visit.call(at) }
      end

      private

      # The values a schema object holds where schemas belong, as [keyword, pointer, value].
      def children(schema, pointer)
        lists = SCHEMA_LISTS.select { |keyword| schema[keyword].is_a?(Array) }
        maps = SCHEMA_MAPS.select { |keyword| schema[keyword].is_a?(Hash) }
        [
          *SCHEMA.filter_map { |keyword| [keyword, "#{pointer}/#{keyword}", schema[keyword]] if schema.key?(keyword) },
          *lists.flat_map do |keyword|
            schema[keyword].each_with_index.map { |item, index| [keyword, "#{pointer}/#{keyword}/#{index}", item] }
          end,
          *maps.flat_map do |keyword|
            schema[keyword].map { |name, item| [keyword, "#{pointer}/#{keyword}/#{escape(name)}", item] }
          end
        ]
      end

      # Where a schema object sends its value: [pointer, whether it is the same value].
      def links(at, node)
        applied = children(node, at).reject { |keyword, _at, _item| keyword == "$defs" }
                                    .map { |keyword, to, _item| [to, IN_PLACE.include?(keyword)] }
        node.key?("$ref") ? [*applied, [node["$ref"][1..], true]] : applied
      end

      def escape(name) = name.gsub("~", "~0").gsub("/", "~1")
    end
  end
  private_constant :Subschemas
end
