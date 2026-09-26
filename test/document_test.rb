# frozen_string_literal: true

require "test_helper"

class DocumentTest < Minitest::Test
  # Each vector is JSON text, or bytes in base64 where the text is not UTF-8. A valid
  # one carries the RFC 8785 form of the value JavaScript reads from it.
  def test_shared_vectors
    Fixtures.json("map-0.2/ijson-vectors.json").each do |vector|
      name = vector.fetch("name")
      text = vector.key?("base64") ? vector.fetch("base64").unpack1("m0") : vector.fetch("json")
      if vector.fetch("valid")
        assert_equal vector.fetch("canonical"), Mailschema.canonicalize(Mailschema.parse(text)), name
      else
        assert_raises(Mailschema::InvalidDocument, name) { Mailschema.parse(text) }
      end
    end
  end

  # I-JSON numbers are doubles, so a number with no fractional part is one value.
  def test_integral_numbers_parse_as_integers
    parsed = Mailschema.parse("[1, 1.0, -0.0, 1.5, 9007199254740991.0]")
    assert_equal [1, 1, 0, 1.5, 9_007_199_254_740_991], parsed
    assert_equal [Integer, Integer, Integer, Float, Integer], parsed.map(&:class)
    assert_equal({ "a" => [2] }, Mailschema.parse('{"a":[2.0]}'))
  end

  def test_binary_text_is_read_as_utf8
    assert_equal({ "a" => "é" }, Mailschema.parse("{\"a\":\"é\"}".b))
  end

  def test_only_json_text
    assert_raises(Mailschema::InvalidDocument) { Mailschema.parse(nil) }
    assert_raises(Mailschema::InvalidDocument) { Mailschema.parse({ "a" => 1 }) }
  end
end
