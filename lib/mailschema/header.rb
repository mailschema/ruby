# frozen_string_literal: true

module Mailschema
  # Header fields read from an entity's original bytes. A parsed message collapses repeated
  # fields and keeps the last of repeated parameters, so MAP's uniqueness rules are checked
  # here, where different parsers cannot read one header differently.
  module Header
    FIELD = /\A([!-9;-~]+):[ \t]*(.*)\z/m
    PARAMETER = /\A\s*([!\#$%&'*+.^_`|~0-9A-Za-z-]+)\s*=/

    class << self
      # The unfolded fields of a raw entity's header block as [lowercase name, value] pairs, or
      # nil when it is malformed. Lines end with CRLF. `lax` also accepts LF, and skips the
      # line break a MIME part's raw source keeps from its boundary line.
      def fields(raw, lax: false)
        raw = raw.b
        block, separator, = raw.partition(lax ? /\r?\n\r?\n/ : "\r\n\r\n")
        return if separator.empty?

        lines = block.split(lax ? /\r?\n/ : "\r\n", -1)
        unfold(lax ? lines.drop_while(&:empty?) : lines)
      end

      # Whether every parameter of a Content-Type value has its own name. RFC 2231 sections and
      # charset markers belong to the name they extend, so profile and profile* are one name.
      def unique_parameters?(value)
        segments = parameters(value) or return false
        names = segments.drop(1).map do |segment|
          name = PARAMETER.match(segment)&.[](1) or return false
          name.downcase.sub(/\*.*\z/, "")
        end
        names.uniq.size == names.size
      end

      private

      # The fields of header lines, each folded line joined to its field, or nil when a line is
      # neither or holds another line break.
      def unfold(lines)
        lines.each_with_object([]) do |line, fields|
          return nil if line.match?(/[\r\n]/)

          if line.start_with?(" ", "\t")
            return nil if fields.empty?

            fields.last[1] << " " << line.strip
          else
            name, value = FIELD.match(line)&.captures
            return nil unless name

            fields << [name.downcase, value]
          end
        end
      end

      # The value split at each semicolon outside a quoted string, or nil when a quoted string
      # or an escape is left open.
      def parameters(value)
        segments = [+""]
        quoted = escaped = false
        value.each_char do |char|
          next segments << +"" if char == ";" && !quoted

          if escaped then escaped = false
          elsif quoted && char == "\\" then escaped = true
          elsif char == '"' then quoted = !quoted
          end
          segments.last << char
        end
        segments unless quoted || escaped
      end
    end
  end
  private_constant :Header
end
