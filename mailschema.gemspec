# frozen_string_literal: true

require_relative "lib/mailschema/version"

Gem::Specification.new do |spec|
  spec.name = "mailschema"
  spec.version = Mailschema::VERSION
  spec.authors = ["MailSchema contributors"]

  spec.summary = "Mail Action Protocol 0.3 processing"
  spec.description = "Parse, canonicalize, digest and validate Mail Action Protocol 0.3 descriptions, " \
                     "type contracts and implementation records, extract and build the MAP part of an " \
                     "email, and decide whether a verified DKIM signature qualifies a message."
  spec.homepage = "https://mailschema.org"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mailschema/ruby"
  spec.metadata["changelog_uri"] = "https://github.com/mailschema/ruby/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/mailschema/ruby/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # The artifacts are copied from MailSchema by package preparation, so the files are listed
  # explicitly rather than taken from git.
  spec.files = Dir["lib/**/*.rb", "artifacts/**/*", "sig/**/*.rbs", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "json_schemer", "~> 2.5"
  spec.add_dependency "mail", "~> 2.8"
end
