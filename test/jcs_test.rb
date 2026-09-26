# frozen_string_literal: true

require "test_helper"

class JCSTest < Minitest::Test
  def test_shared_vectors
    Fixtures.json("map-0.2/jcs-vectors.json").each do |vector|
      value = JSON.parse(vector.fetch("json"))
      assert_equal vector.fetch("canonical"), Mailschema.canonicalize(value), vector.fetch("name")
      assert_equal vector.fetch("digest"), Mailschema.digest(value), vector.fetch("name")
    end
  end

  # Expected strings come from ECMAScript itself; each value travels as its IEEE 754 bits.
  def test_numbers_match_ecmascript
    numbers = Fixtures.json("numbers.json")
    assert_operator numbers.size, :>=, 10_000
    numbers.each do |bits, expected|
      value = [bits].pack("H*").unpack1("G")
      assert_equal expected, Mailschema.canonicalize(value), bits
    end
  end

  def test_integers_beyond_the_exact_range_format_as_doubles
    assert_equal "9007199254740992", Mailschema.canonicalize(2**53)
    assert_equal "9007199254740992", Mailschema.canonicalize((2**53) + 1)
    assert_equal "1e+21", Mailschema.canonicalize(10**21)
  end

  def test_ascii_strings_in_other_encodings
    assert_equal '{"n":"42"}', Mailschema.canonicalize({ "n" => 42.to_s.encode(Encoding::US_ASCII) })
  end

  def test_values_that_are_not_json
    invalid = "\xFF".b.force_encoding(Encoding::UTF_8)
    [Float::NAN, Float::INFINITY, :symbol, Time.now, { symbol: 1 }, invalid].each do |value|
      assert_raises(ArgumentError) { Mailschema.canonicalize(value) }
    end
  end
end
