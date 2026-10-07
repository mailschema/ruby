# frozen_string_literal: true

module Mailschema
  # The regular expressions a contract's schemas may use: the subset that ECMA-262 (with the u
  # flag) and other engines read alike, so every implementation enforces the same contract.
  class Patterns
    SYNTAX_CHARACTERS = "^$\\.*+?()[]{}|/"
    CONTROL_ESCAPES = { "t" => 0x09, "n" => 0x0a, "f" => 0x0c, "r" => 0x0d }.freeze
    QUANTIFIERS = "*+?{"
    BOUNDS = /\A\{([0-9]{1,4})(?:(,)([0-9]{1,4})?)?\}/
    # A class member that is an unescaped hyphen.
    HYPHEN = :hyphen

    # Why a pattern is outside the portable subset, or nil. The subset is printable ASCII
    # text, with any other code point written as \uXXXX. It has literal characters and escaped
    # syntax characters; \t, \n, \f, \r and \d, the ASCII digits; non-empty classes of literal
    # or escaped members and ranges, with a literal hyphen only first or last; (?: groups;
    # alternation; ^ and $; and one *, +, ?, {n}, {n,} or {n,m} after an atom. Other class
    # escapes and the dot match different characters in different engines, and brackets, && or
    # a stray brace inside a class, or a quantifier on a quantifier, are read differently or
    # refused by one of them. ^ and $ anchor the whole value, as in ECMA-262; an engine whose
    # anchors also match at line breaks must read them so.
    def self.unportable(pattern) = new(pattern).problem

    def initialize(pattern)
      @pattern = pattern
      @at = 0
    end

    def problem
      return "a character outside printable ASCII" unless /\A[\x20-\x7e]*\z/.match?(@pattern)

      disjunction(0)
    end

    private

    def disjunction(depth)
      quantifiable = false
      while @at < @pattern.length
        char = @pattern[@at]
        return depth.zero? ? "an unmatched )" : nil if char == ")"

        problem, quantifiable = QUANTIFIERS.include?(char) ? quantified(char, quantifiable) : term(char, depth)
        return problem if problem
      end
    end

    # The problem with the term at `char`, or nil and whether a quantifier may follow it.
    def term(char, depth)
      case char
      when "|", "^", "$"
        @at += 1
        [nil, false]
      when "(" then [group(depth), true]
      when "[" then [character_class, true]
      when "\\"
        code = escape(false)
        [(code if code.is_a?(String)), true]
      when "." then ["an unescaped dot"]
      when "]", "}" then ["an unescaped #{char}"]
      else
        @at += 1
        [nil, true]
      end
    end

    def group(depth)
      return "a group other than (?:" unless @pattern[@at, 3] == "(?:"

      @at += 3
      problem = disjunction(depth + 1)
      return problem if problem
      return "an unclosed group" unless @pattern[@at] == ")"

      @at += 1
      nil
    end

    def quantified(char, quantifiable)
      return [char == "{" ? "an unescaped {" : "a quantifier with nothing to repeat"] unless quantifiable

      if char == "{"
        bounds = BOUNDS.match(@pattern[@at..])
        return ["a malformed {n,m} quantifier"] unless bounds
        return ["a {n,m} quantifier with m below n"] if bounds[3] && bounds[3].to_i < bounds[1].to_i

        @at += bounds[0].length
      else
        @at += 1
      end
      following = @pattern[@at]
      [("a quantifier on a quantifier" if following && QUANTIFIERS.include?(following)), false]
    end

    # One escaped code point, -1 for the digit class outside a class, or a problem.
    def escape(in_class)
      following = @pattern[@at + 1]
      return "a trailing backslash" if following.nil?
      return unicode_escape if following == "u"

      @at += 2
      return -1 if following == "d" && !in_class
      return CONTROL_ESCAPES[following] if CONTROL_ESCAPES.key?(following)
      return following.ord if SYNTAX_CHARACTERS.include?(following) || (in_class && following == "-")

      "the escape \\#{following}"
    end

    def unicode_escape
      digits = @pattern[@at + 2, 4].to_s
      return "a malformed \\u escape" unless /\A\h{4}\z/.match?(digits)

      code = digits.hex
      return "a surrogate \\u escape" if code.between?(0xd800, 0xdfff)

      @at += 6
      code
    end

    def character_class
      @at += @pattern[@at + 1] == "^" ? 2 : 1
      # Each member's code point, or HYPHEN.
      members = []
      until @pattern[@at] == "]"
        problem = class_member(members)
        return problem if problem
      end
      @at += 1
      return "an empty character class" if members.empty?

      range_problem(members)
    end

    def class_member(members)
      char = @pattern[@at]
      return "an unclosed character class" if char.nil?
      return "a bracket inside a class" if char == "["
      return "&& inside a class" if char == "&" && @pattern[@at + 1] == "&"

      if char == "\\"
        code = escape(true)
        return code if code.is_a?(String)

        members << code
      else
        members << (char == "-" ? HYPHEN : char.ord)
        @at += 1
      end
      nil
    end

    def range_problem(members)
      last = members.size - 1
      index = 0
      while index <= last
        low = members[index]
        if low == HYPHEN
          return "an ambiguous hyphen in a class" unless [0, last].include?(index)
        elsif members[index + 1] == HYPHEN && index + 2 <= last
          high = members[index + 2]
          return "an ambiguous hyphen in a class" if high == HYPHEN
          return "a class range out of order" if high < low

          index += 2
          return "an ambiguous hyphen in a class" if members[index + 1] == HYPHEN && index + 1 != last
        end
        index += 1
      end
    end
  end
  private_constant :Patterns
end
