# frozen_string_literal: true

# MAP JSON: I-JSON parsed from its original text, and the RFC 8785 digests that identify
# contracts and descriptions.
module Mailschema
  # A document that is not MAP JSON, or not the document it claims to be.
  class InvalidDocument < StandardError
    attr_reader :errors

    def initialize(message, errors = [message])
      super(message)
      @errors = errors
    end
  end

  MAX_DEPTH = 32

  # Parse MAP JSON from its original text or bytes: UTF-8 I-JSON (RFC 7493) of at most
  # `max_bytes`, with no byte order mark, duplicate member names, lone surrogates,
  # noncharacters or U+0000, no container deeper than 32 counting the root as 1, and every
  # number a finite token of at most 64 characters within +/-(2^53-1) that does not underflow
  # to zero. These rules apply to the original tokens, before a general parser could erase
  # them. A number with no fractional part is an Integer: I-JSON numbers are doubles, so 1 and
  # 1.0 are one number.
  def self.parse(input, max_bytes)
    text = utf8(input)
    raise InvalidDocument, "A byte order mark is not allowed." if text.start_with?("\u{FEFF}")
    raise InvalidDocument, "The JSON exceeds #{max_bytes} bytes." if text.bytesize > max_bytes

    Reader.new(text).document
  end

  # The RFC 8785 canonical form of a JSON value.
  def self.canonicalize(value) = JCS.canonicalize(value)

  # `sha-256:` and the SHA-256 of the value's RFC 8785 form, as MAP identifies contracts.
  def self.digest(value) = "sha-256:#{Digest::SHA256.hexdigest(canonicalize(value))}"

  NOT_UTF8 = "The JSON is not valid UTF-8."
  private_constant :NOT_UTF8

  # The text, from bytes or a string in any encoding, refusing anything but well-formed UTF-8.
  def self.utf8(input)
    raise TypeError, "MAP JSON is text or bytes." unless input.is_a?(String)

    text = input.encoding == Encoding::BINARY ? input.dup.force_encoding(Encoding::UTF_8) : input.encode(Encoding::UTF_8)
    return text if text.valid_encoding?

    raise InvalidDocument, NOT_UTF8
  rescue EncodingError
    raise InvalidDocument, NOT_UTF8
  end
  private_class_method :utf8

  # json.ts's reader: the grammar of RFC 8259 over the text, failing at the first token that
  # breaks a MAP rule.
  class Reader
    MAX_NUMBER_TOKEN = 64
    EXACT = (2**53) - 1
    # Half the smallest subnormal: a nonzero token at or below it rounds to zero.
    TINY = Rational(1, 2**1075)
    NUMBER = /-?(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?/
    STRING = /"((?>[^"\\]+|\\.)*)"/m
    WELL_FORMED = %r{\A(?>[^\\\x00-\x1f]+|\\["\\/bfnrt]|\\u\h{4})*\z}
    UNESCAPE = { '"' => '"', "\\" => "\\", "/" => "/", "b" => "\b", "f" => "\f", "n" => "\n", "r" => "\r",
                 "t" => "\t" }.freeze
    LITERALS = { "true" => true, "false" => false, "null" => nil }.freeze

    def initialize(text)
      @scanner = StringScanner.new(text)
    end

    def document
      result = value(0)
      space
      refuse("trailing content") unless @scanner.eos?
      result
    end

    private

    # The offset counts UTF-16 code units, as json.ts reports it.
    def refuse(reason, beyond = 0)
      offset = (@scanner.string.byteslice(0, @scanner.pos).encode(Encoding::UTF_16LE).bytesize / 2) + beyond
      raise InvalidDocument, "Invalid MAP JSON at offset #{offset}: #{reason}."
    end

    def space = @scanner.skip(/[ \t\n\r]*/)

    # `depth` counts the containers enclosing the value.
    def value(depth)
      space
      case @scanner.peek(1)
      when "{", "["
        refuse("nesting deeper than #{MAX_DEPTH}") if depth >= MAX_DEPTH
        @scanner.getch == "{" ? object(depth + 1) : array(depth + 1)
      when '"' then string
      else
        literal = @scanner.scan(/true|false|null/)
        literal ? LITERALS.fetch(literal) : number
      end
    end

    def object(depth)
      result = {}
      space
      return result if @scanner.skip(/\}/)

      loop do
        space
        refuse("expected a member name") unless @scanner.peek(1) == '"'
        name = string
        refuse("duplicate member #{JCS.quote(name)}") if result.key?(name)
        space
        refuse('expected ":"') unless @scanner.skip(/:/)
        result[name] = value(depth)
        space
        next if @scanner.skip(/,/)
        return result if @scanner.skip(/\}/)

        refuse('expected "," or "}"')
      end
    end

    def array(depth)
      result = []
      space
      return result if @scanner.skip(/\]/)

      loop do
        result << value(depth)
        space
        next if @scanner.skip(/,/)
        return result if @scanner.skip(/\]/)

        refuse('expected "," or "]"')
      end
    end

    def string
      unless @scanner.scan(STRING)
        # json.ts steps over an escape's two characters, past the end when the text ends in one.
        escape = @scanner.rest[1..][/\\*\z/].length.odd?
        @scanner.terminate
        refuse("unterminated string", escape ? 1 : 0)
      end
      refuse("malformed string") unless WELL_FORMED.match?(@scanner[1])
      text = unescape(@scanner[1]) or refuse("lone surrogate")
      refuse("U+0000 or a noncharacter") if text.each_codepoint.any? { |point| forbidden?(point) }
      text
    end

    # JSON escapes name UTF-16 code units, so a string with escapes is rebuilt in UTF-16,
    # where a lone surrogate is invalid.
    def unescape(body)
      return body unless body.include?("\\")

      units = body.scan(/\\u(\h{4})|\\(.)|([^\\]+)/m).flat_map do |code, escape, text|
        if code then [code.hex]
        elsif escape then [UNESCAPE.fetch(escape).ord]
        else text.encode(Encoding::UTF_16LE).unpack("v*")
        end
      end
      text = units.pack("v*").force_encoding(Encoding::UTF_16LE)
      text.encode(Encoding::UTF_8) if text.valid_encoding?
    end

    def forbidden?(point) = point.zero? || point.between?(0xfdd0, 0xfdef) || point & 0xfffe == 0xfffe

    def number
      token = @scanner.scan(NUMBER) or refuse("unexpected token")
      refuse("a number token longer than #{MAX_NUMBER_TOKEN} characters") if token.length > MAX_NUMBER_TOKEN
      digits = "#{@scanner[1]}#{@scanner[2]}".sub(/\A0+/, "")
      return 0 if digits.empty?

      # Float rounds correctly but warns when a token overflows or underflows, so the decimal
      # exponent settles both first. The value lies in [10^(magnitude-1), 10^magnitude).
      scale = @scanner[3].to_i - @scanner[2].to_s.length
      magnitude = digits.length + scale
      refuse("a number outside the I-JSON range") if magnitude > 17
      if magnitude < -323 || (magnitude == -323 && Rational(digits.to_i, 10**-scale) <= TINY)
        refuse("a number that underflows to zero")
      end
      number = Float(token)
      refuse("a number outside the I-JSON range") if number.abs > EXACT
      number.to_i == number ? number.to_i : number
    end
  end
  private_constant :Reader
end
