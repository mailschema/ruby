# frozen_string_literal: true

require "bigdecimal"
require "digest"
require "json"
require "json_schemer"
require "time"

require_relative "mailschema/version"
require_relative "mailschema/limits"
require_relative "mailschema/jcs"
require_relative "mailschema/document"
require_relative "mailschema/artifacts"
require_relative "mailschema/pointer"
require_relative "mailschema/schema_walk"
require_relative "mailschema/references"
require_relative "mailschema/forms"
require_relative "mailschema/capability"
require_relative "mailschema/contract"
require_relative "mailschema/documents"
require_relative "mailschema/http"
require_relative "mailschema/message"

# Mail Action Protocol 0.2 tooling. The module parses,
# canonicalizes, digests and validates MAP documents, checks the type contracts an
# implementation vendors, and builds results and problems. It does not establish
# endpoint trust, verify email authentication, grant authority or send email.
module Mailschema
  # RFC 8785 canonical JSON of a value.
  def self.canonicalize(value) = JCS.canonicalize(value)

  # `sha-256:` and the SHA-256 of the RFC 8785 canonical form: the digest MAP uses
  # for descriptions, contracts and pinned schemas.
  def self.digest(value) = "sha-256:#{Digest::SHA256.hexdigest(JCS.canonicalize(value))}"

  # Whether a deadline, a core date-time plus `after` seconds, has been reached.
  # Anything but a core date-time counts as reached, so a mistake fails closed.
  def self.reached?(now, deadline, after: 0)
    !(DATE_TIME.valid?(deadline) && now < Time.iso8601(deadline) + after)
  end
end
