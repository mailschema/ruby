# frozen_string_literal: true

require_relative "lib/mailschema/version"

Gem::Specification.new do |spec|
  spec.name = "mailschema"
  spec.version = Mailschema::VERSION
  spec.authors = ["MailSchema contributors"]

  spec.summary = "Mail Action Protocol 0.2 tooling"
  spec.description = "Parse, canonicalize, digest and validate Mail Action Protocol 0.2 documents, " \
                     "verify the type contracts an implementation vendors, and build results and problems."
  spec.homepage = "https://mailschema.org/tools"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mailschema/ruby"
  spec.metadata["changelog_uri"] = "https://github.com/mailschema/ruby/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/mailschema/ruby/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # The library, its canonical artifacts and its documents. The artifacts are copied
  # from MailSchema and verified byte for byte before release, so they are listed
  # explicitly rather than taken from git.
  spec.files = Dir["lib/**/*.rb", "schemas/*.json", "contexts/*.jsonld", "sig/**/*.rbs",
                   "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "bigdecimal", ">= 3.1", "< 5"
  spec.add_dependency "json", ">= 2.21", "< 4"
  spec.add_dependency "json_schemer", "~> 2.5"
end
