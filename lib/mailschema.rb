# frozen_string_literal: true

require "digest"
require "json"
require "json_schemer"
require "mail"
require "strscan"
require "time"
require "uri"

require_relative "mailschema/version"
require_relative "mailschema/jcs"
require_relative "mailschema/json"
require_relative "mailschema/formats"
require_relative "mailschema/artifacts"
require_relative "mailschema/origin"
require_relative "mailschema/patterns"
require_relative "mailschema/subschemas"
require_relative "mailschema/description"
require_relative "mailschema/contract"
require_relative "mailschema/implementation"
require_relative "mailschema/header"
require_relative "mailschema/message"
require_relative "mailschema/authentication"

# Mail Action Protocol 0.3 processing: strict MAP JSON, RFC 8785 digests, descriptions, type
# contracts and implementation records, the MAP part of an email, and the qualifying DKIM
# signature rules. It does not verify DKIM, resolve DNS, fetch anything named in an email,
# grant authority or send email.
module Mailschema
end
