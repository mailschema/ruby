# frozen_string_literal: true

# MAP 0.3's identifiers, limits and schema validation.
module Mailschema
  PROFILE = "https://mailschema.org/profiles/map/0.3"
  CONTEXT = "https://mailschema.org/contexts/map-0.3.jsonld"
  # The Content-Type of the MIME part that carries a description.
  DESCRIPTION_MEDIA_TYPE = %(application/ld+json; profile="#{PROFILE}").freeze
  DESCRIPTION_MAX_BYTES = 65_536
  CONTRACT_MAX_BYTES = 262_144
  # The namespace of the initial effect vocabulary.
  EFFECTS = "https://mailschema.org/effects/"
  # The formats MAP schemas may assert. Every implementation checks exactly these.
  FORMATS = %w[date date-time email uri].freeze

  # JSON Schema 2020-12 as MAP reads it: the listed formats asserted and no other, ECMA-262
  # regular expressions, so ^ and $ anchor the whole value, and references resolved only
  # within the schema, never over the network.
  module Schemas
    ARTIFACTS = File.expand_path("../../artifacts", __dir__)
    FORMAT_CHECKS = Formats.checks.freeze

    module_function

    def compile(schema)
      JSONSchemer.schema(
        schema,
        formats: FORMAT_CHECKS,
        regexp_resolver: "ecma",
        ref_resolver: proc { |uri| raise JSONSchemer::UnknownRef, uri.to_s }
      )
    end

    # A schema the gem bundles, by its file name in artifacts/.
    def bundled(name) = compile(JSON.parse(File.read(File.join(ARTIFACTS, name))))

    # Each validation error as its JSON Pointer and message, the pointer placed inside an
    # enclosing document by `prefix`; an error at the document's root is at /.
    def errors(schema, value, prefix = "")
      schema.validate(value).map do |error|
        pointer = "#{prefix}#{error.fetch("data_pointer")}"
        "#{pointer.empty? ? "/" : pointer}: #{error.fetch("error")}"
      end
    end

    CORE = bundled("core.schema.json")
    CONTRACT = bundled("contract.schema.json")
    IMPLEMENTATION = bundled("implementation.schema.json")
  end
  private_constant :Schemas
end
