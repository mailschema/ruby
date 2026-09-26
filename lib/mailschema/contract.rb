# frozen_string_literal: true

# Type contracts an implementation vendors, verified by digest and compiled once.
module Mailschema
  # A type contract that fails its own checks or its pinned digest.
  class InvalidContract < Error; end

  # Reasons the core assigns to the approval lifecycle.
  APPROVAL_REASONS = %w[declined stale-target expired superseded].freeze

  # A type contract an implementation vendors, verified against the digest it was
  # pinned by and compiled once. It checks the descriptions, requests, inputs and
  # results of that exact type. The Registry has already applied the contract rules,
  # such as portable patterns, to the contract that digest names; loading refuses
  # anything that would otherwise fail at request time.
  class Contract
    # A MAP problem a request earns before the service's own state is consulted.
    Problem = Data.define(:code, :title, :detail)

    FIELD_VALIDATORS = 128
    private_constant :FIELD_VALIDATORS

    attr_reader :document, :digest, :request_schema

    # `digest` is the contract digest the implementation pinned; `dependencies`
    # supplies, by URL, any pinned schema the gem does not bundle.
    def initialize(contract, request_schema, digest:, dependencies: {})
      errors = Validation.errors(CONTRACTS, contract)
      raise InvalidContract, "invalid type contract: #{errors.join("; ")}" if errors.any?
      raise InvalidContract, "the contract is for another MAP profile" unless contract["profile"] == PROFILE

      @document = frozen_copy(contract)
      @digest = Mailschema.digest(@document)
      raise InvalidContract, "the contract digest is #{@digest}, not the pinned #{digest}" unless @digest == digest

      @request_schema = frozen_copy(request_schema)
      @references = pin(@document.fetch("dependencies", []), dependencies)
      verify_structure
      compile
    end

    def id = document.fetch("id")
    def version = document.fetch("version")

    # The type reference a description and a request of this contract name exactly.
    def type_reference = { "id" => id, "version" => version, "contractDigest" => digest }

    def operation(id) = document.fetch("operations").find { |operation| operation.fetch("id") == id }

    # Whether completing the operation decides the interaction.
    def decision?(id)
      found = operation(id) or raise ArgumentError, "#{id} is not an operation of this type"
      !found.fetch("repeatable", false)
    end

    # Every rule a description must satisfy beyond the core schema, for the service
    # that issues it and the client that receives it.
    def description_errors(description)
      errors = Mailschema.description_errors(description)
      return errors if errors.any?
      return ["The description names another type contract."] unless description.fetch("type") == type_reference

      problems = details_problems(description)
      problems.concat(operation_problems(description))
      unless Time.iso8601(description.fetch("describedAt")) < Time.iso8601(description.fetch("expiresAt"))
        problems << "The interaction expires before it was described."
      end
      problems.concat(Capability.problems(description)) if description.dig("service", "authority") == "possession"
      problems
    end

    # The checks a service makes on a request once it has resolved the description it
    # issued, compared the description digest and established the caller: the exact
    # type, an offered operation the authority permits, and expiry. Nil when they
    # pass. The service then applies its own state (a decided interaction, a stale
    # target) and `input_errors`, in that order, before any effect.
    def request_problem(description, request, now:)
      unless request["type"] == type_reference && description["type"] == type_reference
        return Problem.new("unsupported-type", "Unsupported interaction type",
                           "The service does not implement this exact interaction type contract.")
      end
      unless offered?(description, request["operation"])
        return Problem.new("unsupported-operation", "Unsupported operation",
                           "The operation was not offered in this interaction.")
      end
      return unless Mailschema.reached?(now, description.fetch("expiresAt"))

      Problem.new("expired-interaction", "Interaction expired",
                  "The interaction expired before the request was processed.")
    end

    # Input problems for one request, each with a detail and a JSON Pointer into its
    # input: the operation's input schema, then its field bindings against the
    # description's details. Type rules a contract cannot express are the caller's.
    def input_errors(description, request)
      found = operation(request["operation"])
      schema = @inputs[request["operation"]]
      return [problem("The operation is not part of this type.", "")] unless found && schema

      errors = pointer_errors(schema, request["input"])
      return errors.first(100) if errors.any?

      found.fetch("fieldBindings", [])
           .flat_map { |binding| binding_errors(binding, description["details"], request["input"]) }
           .first(100)
    end

    # The core result definition, then the output schema and reason this contract
    # declares for the result's operation and state.
    def result_errors(result)
      errors = Mailschema.result_errors(result)
      return errors if errors.any?
      return ["The result names another type contract."] unless result.fetch("type") == type_reference

      found = operation(result.fetch("operation"))
      return ["#{result["operation"]} is not an operation of this type."] unless found

      declared = found.fetch("results").find { |entry| entry.fetch("state") == result.fetch("state") }
      return ["#{found["id"]} does not declare the state #{result["state"]}."] unless declared

      problems = Validation.errors(@outputs.fetch([found["id"], declared["state"]]), result.fetch("output"), "/output")
      if result["state"] == "failed" && !declared.fetch("reasons", []).include?(result["reason"])
        problems << "#{found["id"]} does not declare the reason #{result["reason"]}."
      end
      problems
    end

    private

    def frozen_copy(value) = deep_freeze(JSON.parse(JSON.generate(value)))

    def deep_freeze(value)
      case value
      when Hash then value.each_value { |member| deep_freeze(member) }
      when Array then value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end

    def pin(dependencies, supplied)
      references = dependencies.to_h do |dependency|
        url = dependency.fetch("url")
        schema = BUNDLED[url] || supplied[url]
        raise InvalidContract, "unknown dependency #{url}" unless schema
        unless Mailschema.digest(schema) == dependency.fetch("canonicalDigest")
          raise InvalidContract, "the pinned digest of #{url} differs"
        end

        [url, schema.frozen? ? schema : frozen_copy(schema)]
      end
      raise InvalidContract, "the core schema must be pinned" unless references.key?(CORE_SCHEMA)

      references.freeze
    end

    def verify_structure
      verify_schemas
      verify_request_schema
      verify_operations
      References.verify(inline_schemas, request_schema, @references, unbundled)
    end

    # The schemas the contract carries itself: its details and every output.
    def inline_schemas
      outputs = document.fetch("operations").flat_map do |operation|
        operation.fetch("results").map { |result| result["outputSchema"] }
      end
      [document["detailsSchema"], *outputs].compact
    end

    # Every schema is valid JSON Schema 2020-12, so no malformed keyword fails when a
    # request arrives.
    def verify_schemas
      [*inline_schemas, request_schema, *unbundled].each do |schema|
        problem = Validation.invalid_schema(schema)
        raise InvalidContract, "a schema is not valid JSON Schema 2020-12: #{problem}" if problem
      end
    end

    def verify_request_schema
      reference = document.fetch("requestSchema")
      unless request_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
        raise InvalidContract, "the request schema must declare JSON Schema 2020-12"
      end
      unless request_schema["$id"] == reference["url"]
        raise InvalidContract, "the request schema $id differs from the contract"
      end
      unless Mailschema.digest(request_schema) == reference["canonicalDigest"]
        raise InvalidContract, "the request schema digest differs from the contract"
      end

      constants = SchemaWalk.values(request_schema, "const").grep(String)
      [id, version, *operation_ids].each do |expected|
        raise InvalidContract, "the request schema does not bind #{expected}" unless constants.include?(expected)
      end
    end

    def verify_operations
      raise InvalidContract, "duplicate operation identifiers" unless operation_ids.uniq == operation_ids

      document.fetch("operations").each do |operation|
        states = operation.fetch("results").map { |result| result.fetch("state") }
        raise InvalidContract, "duplicate #{operation["id"]} result states" unless states.uniq == states
      end
    end

    def operation_ids = document.fetch("operations").map { |operation| operation.fetch("id") }

    # Every validator now, so a pattern that does not compile refuses the contract
    # rather than a request.
    def compile
      references = @references.merge(request_schema.fetch("$id") => request_schema)
      @schema = ->(value) { Validation.schema(value, references) }
      compile_deferred
      @details = @schema.call(document["detailsSchema"]) if document.key?("detailsSchema")
      @inputs = branches.to_h { |operation, input| [operation, @schema.call(input)] }
      @outputs = document.fetch("operations").flat_map do |operation|
        operation.fetch("results").map do |result|
          [[operation["id"], result["state"]], @schema.call(result.fetch("outputSchema"))]
        end
      end.to_h
      resolve_references
      @fields = {}
    rescue RegexpError, JSONSchemer::InvalidEcmaRegexp => e
      raise InvalidContract, "a pattern does not compile: #{e.message}"
    rescue JSONSchemer::InvalidRefPointer, JSONSchemer::InvalidRefResolution, JSONSchemer::UnknownRef => e
      raise InvalidContract, "a reference does not resolve: #{e.message}"
    end

    # The pinned schemas the gem does not bundle.
    def unbundled = @references.reject { |url, _| BUNDLED.key?(url) }.values

    # What the validator would otherwise compile at first use: pinned schemas the gem
    # does not bundle, and the names of patternProperties.
    def compile_deferred
      unbundled.each { |schema| @schema.call(schema) }
      [document, request_schema, *unbundled]
        .flat_map { |schema| SchemaWalk.values(schema, "patternProperties").grep(Hash).flat_map(&:keys) }
        .each { |pattern| @schema.call({ "pattern" => pattern }) }
    end

    # Every reference resolved now, into every schema it reaches, as a request would
    # otherwise resolve it first.
    def resolve_references = [@details, *@inputs.values, *@outputs.values].compact.each(&:bundle)

    # Each operation's branch of the request schema, with its input schema.
    def branches
      last = request_schema.fetch("allOf", []).last || {}
      (last["oneOf"] || [last]).to_h do |branch|
        properties = branch["properties"] || {}
        [properties.dig("operation", "const"), properties.fetch("input", {})]
      end
    end

    def offered?(description, id)
      authority = description.dig("service", "authority")
      description.fetch("operations").any? { |offered| offered["id"] == id } &&
        operation(id)&.fetch("authority")&.include?(authority)
    end

    def operation_problems(description)
      ids = description.fetch("operations").map { |offered| offered.fetch("id") }
      authority = description.dig("service", "authority")
      problems = ids.uniq.size == ids.size ? [] : ["An operation is offered twice."]
      ids.each do |offered|
        unless operation(offered)&.fetch("authority")&.include?(authority)
          problems << "#{offered} is not a #{authority} operation of this type."
        end
      end
      problems
    end

    def details_problems(description)
      details = description.key?("details") ? description["details"] : Pointer::MISSING
      missing = details.equal?(Pointer::MISSING)
      valid = @details ? !missing && @details.valid?(details) : missing
      return ["The details do not satisfy the type contract."] unless valid

      blocks = document.fetch("operations").flat_map do |operation|
        operation.fetch("fieldBindings", []).map { |binding| binding["fields"] }
      end
      blocks.uniq.flat_map do |pointer|
        fields = Pointer.member(details, pointer)
        fields.equal?(Pointer::MISSING) ? [] : Forms.problems(fields).map { |found| "#{pointer}: #{found}" }
      end
    end

    # A form-shaped input holds only the fields the details define, and satisfies them.
    def binding_errors(binding, details, input)
      fields = Pointer.member(details, binding.fetch("fields"))
      values = Pointer.member(input, binding.fetch("input"))
      if fields.equal?(Pointer::MISSING)
        return [] if values.equal?(Pointer::MISSING)

        [problem("This interaction defines no fields for these values.", binding["input"])]
      elsif values.equal?(Pointer::MISSING)
        return [] if fields.fetch("required", []).empty?

        [problem("Values for the required fields are missing.", binding["input"])]
      else
        pointer_errors(fields_schema(fields), values, binding["input"])
      end
    end

    # The compiled schema of a fields block's values. Least recently used blocks leave
    # first, so a long-running service stays bounded.
    def fields_schema(fields)
      key = Mailschema.digest(fields)
      schema = @fields.delete(key) || @schema.call(Forms.values_schema(fields))
      @fields[key] = schema
      @fields.shift while @fields.size > FIELD_VALIDATORS
      schema
    end

    # Validation errors as a detail and a JSON Pointer, naming a missing member itself.
    def pointer_errors(schema, value, prefix = "")
      schema.validate(value).flat_map do |error|
        at = error.fetch("data_pointer")
        if error["type"] == "required"
          error.dig("details", "missing_keys").map do |name|
            problem(error["error"], "#{prefix}#{at}/#{Pointer.escape(name)}")
          end
        else
          [problem(error["error"], "#{prefix}#{at}")]
        end
      end.uniq
    end

    def problem(detail, pointer) = Limits.input_error(detail, pointer)
  end
end
