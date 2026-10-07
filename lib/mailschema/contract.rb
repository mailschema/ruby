# frozen_string_literal: true

# A type contract: the digest-bound definition of an interaction's details, operations,
# effects and permitted bindings.
module Mailschema
  # The capability binding's kinds: the exact effects each declares and its longest lifetime.
  CAPABILITY_KINDS = {
    "refusal" => { effects: %w[refusal state].freeze, max_lifetime_seconds: 604_800 }.freeze,
    "protective-report" => { effects: %w[protection state].freeze, max_lifetime_seconds: 259_200 }.freeze,
    "address-confirmation" => { effects: %w[assertion state].freeze, max_lifetime_seconds: 86_400 }.freeze
  }.freeze

  # The schemas a contract supplies, held to what every implementation enforces alike.
  module ContractSchemas
    # The JSON Schema 2020-12 keywords a contract's schemas may use. Every implementation
    # enforces all of them alike; scope-resolved references and content annotations are absent.
    KEYWORDS = Set.new(
      %w[
        $schema $ref $defs $comment
        allOf anyOf oneOf not if then else dependentSchemas
        prefixItems items contains properties patternProperties
        additionalProperties propertyNames unevaluatedItems unevaluatedProperties
        type enum const multipleOf maximum exclusiveMaximum minimum
        exclusiveMinimum maxLength minLength pattern maxItems minItems
        uniqueItems maxContains minContains maxProperties minProperties required
        dependentRequired format
        title description default deprecated readOnly writeOnly examples
      ]
    ).freeze
    DIALECT = "https://json-schema.org/draft/2020-12/schema"

    class << self
      # Why a schema a contract supplies cannot be enforced alike everywhere, if it cannot.
      def problems(schema, pointer)
        within = Subschemas.all(schema, pointer)
        schemas = within.to_set { |at, _node| at.delete_prefix(pointer) }
        found = within.flat_map do |at, node|
          node.is_a?(Hash) ? node_problems(at, node, at == pointer, schemas) : []
        end
        return found if found.any?
        return ["#{pointer}: $ref leads back without moving into the value"] if Subschemas.endless?(schema)

        [compile_problem(schema, within, pointer)].compact
      end

      private

      def node_problems(at, node, root, schemas)
        problems = node.keys.reject { |keyword| KEYWORDS.include?(keyword) }
                       .map { |keyword| "#{keyword} is not a MAP schema keyword" }
        problems << "$schema names JSON Schema 2020-12, at the schema's root only" if stray_schema?(node, root)
        problems << "$ref is a JSON Pointer to a schema within this schema" if unresolved?(node, schemas)
        problems << "format is one of #{FORMATS.join(", ")}" if node.key?("format") && !FORMATS.include?(node["format"])
        problems << "multipleOf is an integer" if node["multipleOf"].is_a?(Float) && node["multipleOf"] % 1 != 0
        (problems + pattern_problems(node)).map { |problem| "#{at}: #{problem}" }
      end

      def stray_schema?(node, root) = node.key?("$schema") && !(root && node["$schema"] == DIALECT)

      # A $ref other than # and the exact RFC 6901 pointer Subschemas gives a schema (the root or a
      # subschema, object or boolean) in the same root. Any other value or spelling is refused,
      # and every $ref is checked, in a definition nothing uses too.
      def unresolved?(node, schemas)
        return false unless node.key?("$ref")

        ref = node["$ref"]
        !(ref.is_a?(String) && ref.start_with?("#") && schemas.include?(ref[1..]))
      end

      def pattern_problems(node)
        patterns = [
          *(node["pattern"] if node["pattern"].is_a?(String)),
          *(node["patternProperties"].keys if node["patternProperties"].is_a?(Hash))
        ]
        patterns.filter_map do |pattern|
          problem = Patterns.unportable(pattern)
          "pattern #{JCS.quote(pattern)} uses #{problem}" if problem
        end
      end

      # Why the schema would not compile, or nil: it is not valid JSON Schema 2020-12, or a
      # reference cannot be resolved now, so validation never fails on one later.
      def compile_problem(schema, nodes, pointer)
        invalid = JSONSchemer.validate_schema(schema).first
        return "#{pointer}: #{invalid.fetch("error")}" if invalid

        compiled = Schemas.compile(schema)
        nodes.filter_map { |_at, node| node["$ref"] if node.is_a?(Hash) }.each { |ref| compiled.ref(ref) }
        nil
      rescue StandardError => e
        "#{pointer}: #{e.message}"
      end
    end
  end
  private_constant :ContractSchemas

  # Why the value is not a MAP 0.3 type contract, or no reasons.
  def self.contract_errors(value)
    errors = Schemas.errors(Schemas::CONTRACT, value)
    return errors if errors.any?

    # The canonical form has JSON.stringify's bytes in another order.
    errors << "/: exceeds #{CONTRACT_MAX_BYTES} bytes" if canonicalize(value).bytesize > CONTRACT_MAX_BYTES
    ids = value["operations"].map { |operation| operation["id"] }
    errors << "/operations: identifiers must be unique" if ids.uniq.size != ids.size
    errors.concat(ContractSchemas.problems(value["detailsSchema"], "/detailsSchema"))
    value["operations"].each_with_index do |operation, index|
      at = "/operations/#{index}"
      errors.concat(ContractSchemas.problems(operation["inputSchema"], "#{at}/inputSchema")) if operation["inputSchema"]
      errors.concat(capability_errors(operation, at)) if operation["capability"]
    end
    errors
  end

  def self.capability_errors(operation, at)
    name = operation.dig("capability", "kind")
    kind = CAPABILITY_KINDS.fetch(name)
    expected = kind[:effects].map { |effect| "#{EFFECTS}#{effect}" }.sort
    errors = []
    if operation["effects"].sort != expected
      errors << "#{at}/effects: a #{name} capability declares exactly #{expected.join(" and ")}"
    end
    if operation.dig("capability", "maxLifetimeSeconds") > kind[:max_lifetime_seconds]
      errors << "#{at}/capability/maxLifetimeSeconds: at most #{kind[:max_lifetime_seconds]}"
    end
    errors
  end
  private_class_method :capability_errors

  # A valid contract with its digest and compiled schemas.
  class Contract
    # The contract's frozen document.
    attr_reader :document
    # `sha-256:` and the SHA-256 of the contract's RFC 8785 form.
    attr_reader :digest

    # The contract in the bytes or text, read as MAP JSON within the contract limit.
    def self.parse(input) = new(Mailschema.parse(input, CONTRACT_MAX_BYTES))

    # The contract, or InvalidDocument with every reason the value is not one.
    def initialize(value)
      errors = Mailschema.contract_errors(value)
      raise InvalidDocument.new("The value is not a MAP 0.3 type contract.", errors) if errors.any?

      @document = frozen(value)
      @digest = Mailschema.digest(@document)
      @details = Schemas.compile(@document["detailsSchema"])
      @inputs = @document["operations"].filter_map do |operation|
        [operation["id"], Schemas.compile(operation["inputSchema"])] if operation["inputSchema"]
      end.to_h
    end

    def id = document["id"]

    def version = document["version"]

    def operation(id) = document["operations"].find { |operation| operation["id"] == id }

    # Why the details do not satisfy the contract's details schema, or no reasons.
    def details_errors(details) = Schemas.errors(@details, details, "/details")

    # Why the input is not acceptable for the operation, or no reasons. An operation whose
    # inputSchema is null accepts no input: pass nil.
    def input_errors(operation_id, input = nil)
      return ["/operation: #{operation_id} is not an operation of this contract"] unless operation(operation_id)

      schema = @inputs[operation_id]
      return input.nil? ? [] : ["/input: this operation accepts no input"] unless schema

      Schemas.errors(schema, input, "/input")
    end

    # Why a description does not use this contract as it allows, or no reasons: it is a
    # description; it names this contract by identifier, version and digest; it offers only
    # declared operations; a capability appears only where the contract permits one, at the
    # service's origin and within the kind's lifetime; and its details satisfy the details
    # schema.
    def description_errors(description)
      errors = Mailschema.description_errors(description)
      return errors if errors.any?

      errors.concat(type_errors(description))
      lifetime = Time.iso8601(description["expiresAt"]) - Time.iso8601(description["issuedAt"])
      origin = authority(description.dig("service", "id"))
      description["operations"].each_with_index do |offered, index|
        errors.concat(offer_errors(offered, "/operations/#{index}", lifetime, origin))
      end
      errors.concat(details_errors(description["details"]))
    end

    private

    def type_errors(description)
      type = description["type"]
      errors = []
      if type["id"] != id || type["version"] != version
        errors << "/type: names #{type["id"]} #{type["version"]}, not this contract"
      end
      errors << "/type/contractDigest: does not match" if type["contractDigest"] != digest
      errors << "/profile: differs from the contract profile" if description["profile"] != document["profile"]
      errors
    end

    def offer_errors(offered, at, lifetime, origin)
      declared = operation(offered["id"])
      return ["#{at}/id: #{offered["id"]} is not an operation of this contract"] unless declared
      return [] unless offered["capability"]

      errors = []
      if !declared["capability"]
        errors << "#{at}/capability: the contract permits no capability for #{offered["id"]}"
      elsif lifetime > declared.dig("capability", "maxLifetimeSeconds")
        errors << "/expiresAt: a #{offered["id"]} capability lasts at most " \
                  "#{declared.dig("capability", "maxLifetimeSeconds")} seconds"
      end
      if authority(offered.dig("capability", "url")) != origin
        errors << "#{at}/capability/url: must have the service's origin"
      end
      errors
    end

    # An HTTPS URL's host and port as an origin compares them: lowercase, without :443.
    def authority(url) = url[%r{\Ahttps://([^/?#]*)}i, 1]&.downcase&.delete_suffix(":443")

    # A frozen copy of a JSON value, so the document keeps its digest.
    def frozen(value)
      case value
      when Hash then value.to_h { |name, member| [name, frozen(member)] }.freeze
      when Array then value.map { |item| frozen(item) }.freeze
      else value.dup.freeze
      end
    end
  end
end
