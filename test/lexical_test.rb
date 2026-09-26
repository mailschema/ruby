# frozen_string_literal: true

require "test_helper"

# Every lexical form of the core and form fields schemas reads in Ruby exactly as
# ECMA-262 reads it, line terminators included. Each vector
# carries the verdict of the reference implementation.
class LexicalTest < Minitest::Test
  def test_shared_vectors
    bundled = Mailschema.const_get(:BUNDLED)
    validation = Mailschema.const_get(:Validation)
    schemas = Hash.new { |built, url| built[url] = validation.schema(bundled.fetch(url)) }
    definitions = Hash.new { |compiled, (url, name)| compiled[[url, name]] = schemas[url].ref("#/$defs/#{name}") }
    Fixtures.json("map-0.2/lexical-vectors.json").each do |vector|
      schema, definition, value = vector.values_at("schema", "definition", "value")
      assert_equal vector.fetch("valid"), definitions[[schema, definition]].valid?(value),
                   "#{definition} #{value.inspect}"
    end
    covered = definitions.keys.group_by(&:first).transform_values { |pairs| pairs.map(&:last).sort }
    assert_equal({ Mailschema::CORE_SCHEMA => %w[address contractDigest date dateTime detailsKey digest httpsIdentifier
                                                 httpsOrigin httpsTarget identifier nonBlank token urlTemplate uuidUrn],
                   Mailschema::FORMS_SCHEMA => %w[autocomplete fieldName] }, covered)
  end
end
