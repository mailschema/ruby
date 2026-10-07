# frozen_string_literal: true

require "test_helper"

class JSONTest < Minitest::Test
  # Each vector is JSON text, or bytes in base64 where the text is not UTF-8. A valid one
  # carries the RFC 8785 form of the value JavaScript reads from it.
  def test_json_vectors
    Fixtures.json("json-vectors.json").each do |vector|
      name = vector.fetch("name")
      input = vector.key?("base64") ? vector.fetch("base64").unpack1("m0") : vector.fetch("json")
      if vector.fetch("valid")
        assert_equal vector.fetch("canonical"),
                     Mailschema.canonicalize(Mailschema.parse(input, Mailschema::DESCRIPTION_MAX_BYTES)), name
      else
        assert_raises(Mailschema::InvalidDocument, name) { Mailschema.parse(input, Mailschema::DESCRIPTION_MAX_BYTES) }
      end
    end
  end

  def test_jcs_vectors
    Fixtures.json("jcs-vectors.json").each do |vector|
      value = JSON.parse(vector.fetch("json"))
      assert_equal vector.fetch("canonical"), Mailschema.canonicalize(value), vector.fetch("name")
      assert_equal vector.fetch("digest"), Mailschema.digest(value), vector.fetch("name")
    end
  end

  def test_refuses_invalid_utf8_rather_than_replacing_it
    error = assert_raises(Mailschema::InvalidDocument) { Mailschema.parse([0x7b, 0x22, 0xff, 0x22, 0x7d].pack("C*"), 100) }
    assert_equal "The JSON is not valid UTF-8.", error.message
    assert_equal [error.message], error.errors
  end

  def test_reports_the_rule_and_offset
    {
      '{"a/":1,"a\/":2}' => "Invalid MAP JSON at offset 13: duplicate member \"a/\".",
      '{"a":1,}' => "Invalid MAP JSON at offset 7: expected a member name.",
      '{"a":"\ud800"}' => "Invalid MAP JSON at offset 13: lone surrogate.",
      '{"a":1e-400}' => "Invalid MAP JSON at offset 11: a number that underflows to zero.",
      '{"a":1e400}' => "Invalid MAP JSON at offset 10: a number outside the I-JSON range.",
      "#{"[" * 33}#{"]" * 33}" => "Invalid MAP JSON at offset 32: nesting deeper than 32."
    }.each do |json, message|
      assert_equal message, assert_raises(Mailschema::InvalidDocument) { Mailschema.parse(json, 100) }.message
    end
    error = assert_raises(Mailschema::InvalidDocument) { Mailschema.parse("[1,2]", 4) }
    assert_equal "The JSON exceeds 4 bytes.", error.message
    error = assert_raises(Mailschema::InvalidDocument) { Mailschema.parse("\"\u{1F600}\"\\", 100) }
    assert_equal "Invalid MAP JSON at offset 4: trailing content.", error.message
  end

  def test_integral_numbers_are_integers
    parsed = Mailschema.parse("[1, 1.0, -0.0, 1.5, 9007199254740991.0, 25e-1]", 100)
    assert_equal [1, 1, 0, 1.5, 9_007_199_254_740_991, 2.5], parsed
    assert_equal [Integer, Integer, Integer, Float, Integer, Float], parsed.map(&:class)
  end

  def test_reads_text_in_any_encoding_and_bytes_as_utf8
    assert_equal({ "a" => "é" }, Mailschema.parse("{\"a\":\"é\"}".b, 100))
    assert_equal({ "a" => "é" }, Mailschema.parse("{\"a\":\"é\"}".encode(Encoding::UTF_16LE), 100))
    assert_raises(TypeError) { Mailschema.parse(nil, 100) }
  end

  def test_canonicalizes_only_json_values
    invalid = "\xFF".b.force_encoding(Encoding::UTF_8)
    [Float::NAN, Float::INFINITY, :symbol, Time.now, { symbol: 1 }, invalid].each do |value|
      assert_raises(TypeError) { Mailschema.canonicalize(value) }
    end
    assert_equal "9007199254740992", Mailschema.canonicalize((2**53) + 1)
  end
end
