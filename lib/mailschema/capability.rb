# frozen_string_literal: true

# The possession capability and the rules its URLs meet.
module Mailschema
  # The possession capability: the last segment of the execution URL path as written.
  def self.capability(description)
    written_path(description.dig("service", "execution", "url")).split("/", -1).last.to_s
  end

  # The path of an absolute URL exactly as written, with no dot segments removed and
  # nothing decoded.
  def self.written_path(url) = url.to_s[%r{\A[A-Za-z][A-Za-z0-9+.-]*://[^/?#]*([^?#]*)}, 1].to_s

  # The rules a possession description's capability URLs must meet when it is issued.
  module Capability
    UNGUESSABLE = /\A[A-Za-z0-9_-]{22,}\z/
    DOT_SEGMENT = /\A(?:\.|%2e){1,2}\z/i

    module_function

    def problems(description)
      execution = description.dig("service", "execution")
      capability = Mailschema.capability(description)
      problems = []
      problems << "The capability is too short to be unguessable." unless UNGUESSABLE.match?(capability)
      if [execution.fetch("url"), execution.fetch("resultUrlTemplate")].any? { |url| dot_segment?(url) }
        problems << "A capability URL must not contain dot segments."
      end
      unless execution.fetch("resultUrlTemplate").start_with?("#{execution.fetch("url")}/")
        problems << "The result template must extend the execution URL and its capability."
      end
      if description.dig("service", "humanUrl").include?(capability)
        problems << "The human route must not carry the capability."
      end
      problems
    end

    def dot_segment?(url) = Mailschema.written_path(url).split("/", -1).any? { |segment| DOT_SEGMENT.match?(segment) }
  end
  private_constant :Capability
end
