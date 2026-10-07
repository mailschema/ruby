# frozen_string_literal: true

module Mailschema
  # The formats MAP schemas may assert, defined as the reference implementation asserts them
  # (ajv-formats' full definitions), so a value has a format here exactly when it has it there.
  # Its uri and email expressions are ASCII-only and case-insensitive; Ruby folds case beyond
  # ASCII, so other text is refused before they run.
  module Formats
    DATE = /\A(\d\d\d\d)-(\d\d)-(\d\d)\z/
    DAYS = [nil, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze
    # The time of a date-time, whose zone ajv-formats requires.
    TIME = /\A(\d\d):(\d\d):(\d\d(?:\.\d+)?)(z|([+-])(\d\d)(?::?(\d\d))?)\z/i
    # A date-time splits at t or at ECMAScript's \s.
    SEPARATOR = /[tT\t\n\v\f\r\u{2028}\u{2029}\u{FEFF}\p{Zs}]/
    EMAIL = Regexp.new(<<~'PATTERN'.delete("\n"), Regexp::IGNORECASE)
      \A[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+
      [a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z
    PATTERN
    URI = Regexp.new(<<~'PATTERN'.delete("\n"), Regexp::IGNORECASE)
      \A(?:[a-z][a-z0-9+\-.]*:)(?:\/?\/(?:(?:[a-z0-9\-._~!$&'()*+,;=:]|%[0-9a-f]{2})*@)?(?:\[(?:(?:(?:(?:[0-9a-f]{1,4}:){6}
      |::(?:[0-9a-f]{1,4}:){5}|(?:[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){4}|(?:(?:[0-9a-f]{1,4}:){0,1}[0-9a-f]{1,4})?::(?:[0-9a
      -f]{1,4}:){3}|(?:(?:[0-9a-f]{1,4}:){0,2}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){2}|(?:(?:[0-9a-f]{1,4}:){0,3}[0-9a-f]{1,4}
      )?::[0-9a-f]{1,4}:|(?:(?:[0-9a-f]{1,4}:){0,4}[0-9a-f]{1,4})?::)(?:[0-9a-f]{1,4}:[0-9a-f]{1,4}|(?:(?:25[0-5]|2[0-4]\d|[
      01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?))|(?:(?:[0-9a-f]{1,4}:){0,5}[0-9a-f]{1,4})?::[0-9a-f]{1,4}|(?:(?:[0-9a
      -f]{1,4}:){0,6}[0-9a-f]{1,4})?::)|[Vv][0-9a-f]+\.[a-z0-9\-._~!$&'()*+,;=:]+)\]|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3
      }(?:25[0-5]|2[0-4]\d|[01]?\d\d?)|(?:[a-z0-9\-._~!$&'()*+,;=]|%[0-9a-f]{2})*)(?::\d*)?(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@
      ]|%[0-9a-f]{2})*)*|\/(?:(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*
      )*)?|(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)(?:\?(?:[a-z0-9\-
      ._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?(?:#(?:[a-z0-9\-._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?\z
    PATTERN

    class << self
      def date?(value)
        match = DATE.match(value) or return false
        year, month, day = match.captures.map(&:to_i)
        month.between?(1, 12) && day.between?(1, month == 2 && leap?(year) ? 29 : DAYS[month])
      end

      def date_time?(value)
        parts = value.split(SEPARATOR, -1)
        parts.size == 2 && date?(parts[0]) && time?(parts[1])
      end

      def email?(value) = value.ascii_only? && EMAIL.match?(value)

      def uri?(value) = value.ascii_only? && value.match?(%r{[/:]}) && URI.match?(value)

      # The checks json_schemer runs: these four, on strings only, and no other format.
      def checks
        own = { "date" => method(:date?), "date-time" => method(:date_time?), "email" => method(:email?),
                "uri" => method(:uri?) }
        JSONSchemer::Draft202012::FORMATS.transform_values { false }.merge(
          own.transform_values { |check| ->(value, _format) { !value.is_a?(String) || check.call(value) } }
        )
      end

      private

      def leap?(year) = (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)

      # A time with a zone, allowing a leap second only at 23:59 UTC.
      def time?(value)
        match = TIME.match(value) or return false
        hour, minute, zone_hour, zone_minute = match.values_at(1, 2, 6, 7).map(&:to_i)
        second = match[3].to_f
        return false if zone_hour > 23 || zone_minute > 59
        return true if hour <= 23 && minute <= 59 && second < 60

        sign = match[5] == "-" ? -1 : 1
        utc_minute = minute - (zone_minute * sign)
        utc_hour = hour - (zone_hour * sign) - (utc_minute.negative? ? 1 : 0)
        [23, -1].include?(utc_hour) && [59, -1].include?(utc_minute) && second < 61
      end
    end
  end
  private_constant :Formats
end
