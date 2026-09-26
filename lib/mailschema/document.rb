# frozen_string_literal: true

# Parsing MAP documents as I-JSON within the core limits.
module Mailschema
  class Error < StandardError; end

  # A MAP document that is not I-JSON within the core limits.
  class InvalidDocument < Error; end

  MAX_BYTES = 64 * 1024
  # Unicode's noncharacters: U+FDD0 to U+FDEF, and the last two code points of every plane.
  NONCHARACTER = Regexp.new(
    "[\u{FDD0}-\u{FDEF}#{(0..16).flat_map { |plane| [0xFFFE, 0xFFFF].map { (plane << 16) + _1 } }.pack("U*")}]"
  )
  private_constant :NONCHARACTER
  MAX_DEPTH = 32
  EXACT_NUMBER = (2**53) - 1

  # Parse a MAP document as I-JSON (RFC 7493) within the core limits: valid UTF-8,
  # at most 64 KiB, no duplicate member names, no lone surrogates, noncharacters or
  # U+0000 in any string, every number within ±(2^53−1), and arrays and objects nested at most 32
  # deep, the outermost counting as one. Comments and every other leniency RFC 8259 forbids are refused.
  # A number with no fractional part parses as an Integer: I-JSON numbers are
  # doubles, so 1 and 1.0 are one number, as they are to JavaScript.
  def self.parse(json)
    raise InvalidDocument, "a MAP document is JSON text" unless json.is_a?(String)

    text = json.b.force_encoding(Encoding::UTF_8)
    raise InvalidDocument, "the MAP document exceeds #{MAX_BYTES} bytes" if text.bytesize > MAX_BYTES
    raise InvalidDocument, "the MAP document is not valid UTF-8" unless text.valid_encoding?

    i_json(
      JSON.parse(
        text,
        allow_duplicate_key: false, allow_comments: false, allow_nan: false,
        allow_trailing_comma: false, max_nesting: MAX_DEPTH, decimal_class: BigDecimal
      )
    )
  rescue JSON::ParserError => e
    raise InvalidDocument, e.message
  end

  # The parsed value, checked for what I-JSON forbids and the parser allows. A lone
  # surrogate escape parses into invalid UTF-8, and a number beyond the exact range
  # parses as a Ruby Integer or decimal. Each decimal becomes the double nearest its
  # exact value, as ECMAScript reads it; the parser's own float conversion misreads
  # long exponents. Depth is counted here because the parser's nesting limit does not
  # count empty arrays.
  def self.i_json(value, depth = 0)
    case value
    when Hash, Array
      raise InvalidDocument, "arrays and objects nest deeper than #{MAX_DEPTH}" if depth >= MAX_DEPTH

      if value.is_a?(Hash)
        value.to_h { |name, member| [i_json(name), i_json(member, depth + 1)] }
      else
        value.map { |item| i_json(item, depth + 1) }
      end
    when String
      raise InvalidDocument, "the MAP document contains a lone surrogate" unless value.valid_encoding?
      raise InvalidDocument, "the MAP document contains U+0000" if value.include?("\0")
      raise InvalidDocument, "the MAP document contains a noncharacter" if NONCHARACTER.match?(value)

      value
    when Numeric then number(value)
    else value
    end
  end

  # A number as ECMAScript reads it: a decimal becomes the nearest double, and a
  # number with no fractional part an Integer.
  def self.number(value)
    number = value.is_a?(BigDecimal) ? value.to_f : value
    raise InvalidDocument, "a number is outside ±(2^53−1)" unless number.finite? && number.abs <= EXACT_NUMBER

    number.to_i == number ? number.to_i : number
  end
  private_class_method :i_json, :number
end
