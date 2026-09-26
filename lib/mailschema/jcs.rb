# frozen_string_literal: true

module Mailschema
  # The JSON Canonicalization Scheme of RFC 8785: members sorted by their UTF-16
  # code units, the minimal string escapes of ECMAScript and its number format.
  module JCS
    ESCAPES = {
      '"' => '\\"', "\\" => "\\\\", "\b" => "\\b", "\f" => "\\f",
      "\n" => "\\n", "\r" => "\\r", "\t" => "\\t"
    }.freeze
    # Integers up to this magnitude are exact as IEEE 754 doubles.
    EXACT = 2**53

    module_function

    def canonicalize(value)
      case value
      when Hash then object(value)
      when Array then "[#{value.map { |item| canonicalize(item) }.join(",")}]"
      when String then quote(value)
      when Integer then value.abs <= EXACT ? value.to_s : number(value.to_f)
      when Float then number(value)
      when true then "true"
      when false then "false"
      when nil then "null"
      else raise ArgumentError, "#{value.class} is not a JSON value"
      end
    end

    def object(value)
      members = value.map do |name, member|
        raise ArgumentError, "object member names must be strings" unless name.is_a?(String)

        [utf8(name).encode(Encoding::UTF_16BE).unpack("n*"), name, member]
      end
      pairs = members.sort_by(&:first).map { |_, name, member| "#{quote(name)}:#{canonicalize(member)}" }
      "{#{pairs.join(",")}}"
    end

    def quote(value)
      escaped = utf8(value).gsub(/["\\\x00-\x1f]/) { |char| ESCAPES.fetch(char) { format("\\u%04x", char.ord) } }
      %("#{escaped}")
    end

    def utf8(value)
      string = value.encoding == Encoding::UTF_8 ? value : value.encode(Encoding::UTF_8)
      raise ArgumentError, "strings must be valid UTF-8" unless string.valid_encoding?

      string
    rescue EncodingError
      raise ArgumentError, "strings must be valid UTF-8"
    end

    # ECMA-262 Number::toString, from the shortest round-trip digits Float#to_s gives.
    def number(value)
      raise ArgumentError, "numbers must be finite" unless value.finite?
      return "0" if value.zero?
      return "-#{number(-value)}" if value.negative?

      digits, point = shortest(value)
      count = digits.length
      if point.between?(count, 21)
        digits + ("0" * (point - count))
      elsif point.between?(1, 21)
        "#{digits[0, point]}.#{digits[point..]}"
      elsif point.between?(-5, 0)
        "0.#{"0" * -point}#{digits}"
      else
        significand = count == 1 ? digits : "#{digits[0]}.#{digits[1..]}"
        "#{significand}e#{point.positive? ? "+" : "-"}#{(point - 1).abs}"
      end
    end

    # The significant digits of a positive double, and where its decimal point falls:
    # the value is 0.digits × 10^point.
    def shortest(value)
      mantissa, exponent = value.to_s.split("e")
      whole, fraction = mantissa.split(".")
      digits = "#{whole}#{fraction}"
      leading = digits[/\A0*/].length
      [digits[leading..].sub(/0+\z/, ""), whole.length + exponent.to_i - leading]
    end

    private_class_method :object, :quote, :utf8, :number, :shortest
  end
  private_constant :JCS
end
