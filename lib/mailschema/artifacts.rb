# frozen_string_literal: true

# The bundled core artifacts and the validators built from them.
module Mailschema
  PROFILE = "https://mailschema.org/profiles/map/0.2"
  CORE_SCHEMA = "https://mailschema.org/schemas/map-0.2.schema.json"
  FORMS_SCHEMA = "https://mailschema.org/schemas/forms-0.1.schema.json"
  CONTRACT_FORMAT = "https://mailschema.org/schemas/type-contract-0.2.schema.json"
  CONTEXT = "https://mailschema.org/contexts/map-0.2.jsonld"
  # The Registry contribution schema every MailSchema package binds, carried as bytes.
  CONTRIBUTION_SCHEMA = "https://mailschema.org/schemas/contribution.schema.json"

  ROOT = File.expand_path("../..", __dir__)
  # Canonical artifacts, byte for byte, by the URL MailSchema publishes them at.
  ARTIFACTS = {
    CORE_SCHEMA => "schemas/map-0.2.schema.json",
    FORMS_SCHEMA => "schemas/forms-0.1.schema.json",
    CONTRACT_FORMAT => "schemas/type-contract-0.2.schema.json",
    CONTEXT => "contexts/map-0.2.jsonld",
    CONTRIBUTION_SCHEMA => "schemas/contribution.schema.json"
  }.freeze

  # The exact bytes of a bundled artifact.
  def self.artifact(url) = File.binread(File.join(ROOT, ARTIFACTS.fetch(url))).freeze

  # A fresh parsed copy of a bundled artifact.
  def self.document(url) = JSON.parse(artifact(url))

  # The schemas a contract may depend on without supplying them itself.
  BUNDLED = [CORE_SCHEMA, FORMS_SCHEMA].to_h { |url| [url, JSON.parse(artifact(url)).freeze] }.freeze

  # JSON Schema 2020-12 as MAP reads it. Lexical forms are the core schema's patterns,
  # so `format` stays an annotation: format checkers differ between validators. MAP
  # patterns use a subset ECMA-262 and Ruby read alike, and references resolve only
  # against schemas already in hand, never over the network.
  module Validation
    module_function

    def schema(value, references = BUNDLED)
      JSONSchemer.schema(
        value,
        regexp_resolver: "ecma",
        format: false,
        ref_resolver: proc { |uri| references[uri.to_s.delete_suffix("#")] }
      )
    end

    # The first way a schema is not valid JSON Schema 2020-12, or nil.
    def invalid_schema(value) = JSONSchemer.validate_schema(value).first&.fetch("error")

    # Errors as `pointer message` lines, as the other MailSchema packages report them.
    # `prefix` places the pointers inside an enclosing document.
    def errors(schema, value, prefix = "")
      schema.validate(value).first(100).map do |error|
        pointer = "#{prefix}#{error.fetch("data_pointer")}"
        "#{pointer.empty? ? "/" : pointer} #{error.fetch("error")}"
      end
    end
  end

  CORE = Validation.schema(BUNDLED.fetch(CORE_SCHEMA))
  DEFINITIONS = %w[description request result problem].to_h { |name| [name, CORE.ref("#/$defs/#{name}")] }.freeze
  DATE_TIME = CORE.ref("#/$defs/dateTime")
  REQUEST_ID = CORE.ref("#/$defs/uuidUrn")
  CONTRACTS = Validation.schema(document(CONTRACT_FORMAT))

  private_constant :ROOT, :BUNDLED, :Validation, :CORE, :DEFINITIONS, :DATE_TIME, :REQUEST_ID, :CONTRACTS

  # Whether a value is a request identifier: the core UUID URN form. Only one names a
  # result resource. Anything else, bytes that are not text included, is not one.
  def self.request_id?(value)
    return false if value.is_a?(String) && !value.valid_encoding?

    REQUEST_ID.valid?(value)
  end

  # Checks any MAP 0.2 description, request, result or problem against the core schema.
  def self.map_errors(document) = Validation.errors(CORE, document)

  # Checks a description against the core description definition only. A description
  # of a type the caller has no contract for can be checked this far.
  def self.description_errors(description) = Validation.errors(DEFINITIONS.fetch("description"), description)

  # Checks a request against the core request definition. A request that fails here
  # is not claimed: its identifier stays free.
  def self.request_errors(request) = Validation.errors(DEFINITIONS.fetch("request"), request)

  # Checks a result against the core result definition only.
  def self.result_errors(result) = Validation.errors(DEFINITIONS.fetch("result"), result)

  # Checks a problem against the core problem definition, including the agreement of
  # its type, status and code.
  def self.problem_errors(problem) = Validation.errors(DEFINITIONS.fetch("problem"), problem)
end
