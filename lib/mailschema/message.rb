# frozen_string_literal: true

# The Structured Email binding: how a message carries a description.
module Mailschema
  # The Content-Type of the part that carries a description: JSON-LD labelled with the
  # profile through the media type's profile parameter.
  DESCRIPTION_MEDIA_TYPE = %(application/ld+json; profile="#{PROFILE}").freeze

  # Whether a designated part carries a description of this profile: its media type is
  # application/ld+json, compared case-insensitively, and its profile parameter lists
  # the profile among its space-separated URIs. A client processes the one such part
  # outside any attached message and ignores every other structured part.
  def self.description_part?(media_type, profile_parameter)
    media_type.to_s.casecmp?("application/ld+json") &&
      profile_parameter.to_s.split(/[ \t]+/).include?(PROFILE)
  end
end
