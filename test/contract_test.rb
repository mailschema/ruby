# frozen_string_literal: true

require "test_helper"

class ContractTest < Minitest::Test
  EFFECTS = Mailschema::EFFECTS

  def test_identifies_each_published_contract_by_the_digest_its_example_carries
    assert_equal %w[account-security-response campaign-send-approval email-address-confirmation publication-approval],
                 Fixtures.contracts.keys.sort
    Fixtures.contracts.each do |slug, contract|
      assert_equal Fixtures.example(slug).dig("type", "contractDigest"), contract.digest, slug
      assert_equal Mailschema.digest(Fixtures.contract_document(slug)), contract.digest, slug
      assert_equal [], Mailschema.contract_errors(Fixtures.contract_document(slug)), slug
    end
  end

  def test_keeps_a_frozen_copy
    document = Fixtures.contract_document("publication-approval")
    contract = Mailschema::Contract.new(document)
    document["name"] = "Changed"
    assert_equal "Publication Approval", contract.document["name"]
    assert_predicate contract.document, :frozen?
    assert_predicate contract.document.dig("operations", 0, "effects"), :frozen?
    assert_equal "https://mailschema.org/types/publication-approval", contract.id
    assert_equal "0.1", contract.version
    assert_equal "approve", contract.operation("approve")["id"]
    assert_nil contract.operation("publish")
  end

  def test_checks_operation_input_against_the_operation
    contract = Fixtures.contracts.fetch("publication-approval")
    assert_equal [], contract.input_errors("approve")
    assert_equal [], contract.input_errors("approve", nil)
    assert_equal ["/input: this operation accepts no input"], contract.input_errors("approve", {})
    assert_equal ["/operation: publish is not an operation of this contract"], contract.input_errors("publish")
    refute_empty contract.input_errors("request-changes", {})
    assert(contract.input_errors("request-changes", {}).all? { |error| error.start_with?("/input: ") })
    assert_equal [], contract.input_errors("request-changes", { "comment" => "Use the approved title." })
  end

  def test_reports_details_errors_inside_the_description
    contract = Fixtures.contracts.fetch("campaign-send-approval")
    details = Fixtures.example("campaign-send-approval")["details"]
    assert_equal [], contract.details_errors(details)
    details["audience"]["count"] = 0
    errors = contract.details_errors(details)
    assert_equal 1, errors.size
    assert_match %r{\A/details/audience/count: }, errors.first
  end

  REFUSALS = {
    "repeats an operation" => [->(c) { c["operations"] << c["operations"][0] }, /unique/],
    "gives a capability another effect" => [
      ->(c) { c["operations"][1]["effects"] << "#{EFFECTS}communication" }, /declares exactly/
    ],
    "gives a capability a longer lifetime" => [
      ->(c) { c["operations"][1]["capability"]["maxLifetimeSeconds"] = 604_801 }, /604800/
    ],
    "references a remote schema" => [
      ->(c) { c["detailsSchema"] = { "$ref" => "https://untrusted.example/schema.json" } },
      /JSON Pointer to a schema within this schema/
    ],
    "uses a keyword outside MAP" => [
      ->(c) { c["detailsSchema"] = { "type" => "object", "$dynamicRef" => "#meta" } },
      /\$dynamicRef is not a MAP schema keyword/
    ],
    "asserts a format outside MAP" => [
      ->(c) { c["detailsSchema"] = { "type" => "string", "format" => "hostname" } }, /format is one of/
    ],
    "uses a pattern engines read differently" => [
      ->(c) { c["detailsSchema"] = { "type" => "string", "pattern" => "^\\s+$" } }, /the escape \\s/
    ],
    "moves the dialect inside a schema" => [
      lambda do |c|
        c["detailsSchema"] = { "properties" => { "a" => { "$schema" => "https://json-schema.org/draft/2020-12/schema" } } }
      end,
      /at the schema's root only/
    ],
    "uses a fractional multipleOf" => [
      ->(c) { c["detailsSchema"] = { "type" => "number", "multipleOf" => 0.5 } }, /multipleOf is an integer/
    ],
    "references a definition it does not have" => [
      ->(c) { c["detailsSchema"] = { "$defs" => { "unused" => { "$ref" => "#/$defs/missing" } }, "type" => "object" } },
      %r{\A/detailsSchema/\$defs/unused: \$ref is a JSON Pointer to a schema within this schema\z}
    ],
    "is not valid JSON Schema" => [
      ->(c) { c["detailsSchema"] = { "type" => "string", "minLength" => -1 } }, %r{\A/detailsSchema: }
    ],
    "gives an input schema an unportable pattern" => [
      lambda do |c|
        c["operations"][2]["inputSchema"] = { "type" => "object", "patternProperties" => { "^a.b$" => {} } }
      end,
      %r{/operations/2/inputSchema: pattern "\^a\.b\$" uses an unescaped dot}
    ]
  }.freeze

  REFUSALS.each do |name, (mutate, reason)|
    define_method("test_refuses_a_contract_that_#{name.tr(" ", "_")}") do
      contract = Fixtures.contract_document("campaign-send-approval")
      mutate.call(contract)
      assert_match reason, Mailschema.contract_errors(contract).join("\n")
      error = assert_raises(Mailschema::InvalidDocument) { Mailschema::Contract.new(contract) }
      assert_equal "The value is not a MAP 0.3 type contract.", error.message
      assert_equal Mailschema.contract_errors(contract), error.errors
    end
  end

  def test_resolves_references_as_json_pointers_within_the_schema
    {
      "#" => true,
      "#/$defs/a~1b" => true,
      "#/allOf/0" => true,
      "#/" => false,
      "#/allOf/1" => false,
      "#/$defs/a/b" => false,
      # A pointer to a value that is not a schema names no schema.
      "#/type" => false
    }.each do |ref, valid|
      contract = Fixtures.contract_document("campaign-send-approval")
      contract["detailsSchema"].merge!("$defs" => { "a/b" => { "type" => "string" } }, "allOf" => [true])
      contract["detailsSchema"]["properties"]["summary"] = { "$ref" => ref }
      expected = ["/detailsSchema/properties/summary: $ref is a JSON Pointer to a schema within this schema"]
      assert_equal valid ? [] : expected, Mailschema.contract_errors(contract), ref
    end
  end

  def test_refuses_a_reference_that_never_moves_into_the_value
    {
      { "type" => "object", "properties" => { "a" => { "$ref" => "#/properties/a" } } } => false,
      { "$ref" => "#" } => false,
      { "type" => "object", "allOf" => [{ "$ref" => "#" }] } => false,
      { "type" => "object",
        "$defs" => { "a" => { "$ref" => "#/$defs/b" }, "b" => { "anyOf" => [{ "$ref" => "#/$defs/a" }] } },
        "properties" => { "x" => { "$ref" => "#/$defs/a" } } } => false,
      { "type" => "object", "$defs" => { "a" => { "$ref" => "#/$defs/b" }, "b" => { "$ref" => "#/$defs/a" } } } => true,
      { "type" => "object", "properties" => { "a" => { "$ref" => "#" } } } => true
    }.each do |schema, valid|
      contract = Fixtures.contract_document("campaign-send-approval").merge("detailsSchema" => schema)
      expected = valid ? [] : ["/detailsSchema: $ref leads back without moving into the value"]
      assert_equal expected, Mailschema.contract_errors(contract), schema.inspect
      Mailschema::Contract.new(contract).details_errors({ "a" => { "a" => {} } }) if valid
    end
  end

  # MAP's rules are the only checks beyond JSON Schema itself: no validator's own strictness.
  def test_accepts_any_valid_json_schema_within_the_map_rules
    [
      { "properties" => { "a" => { "minLength" => 1 } } },
      { "type" => %w[string number] },
      { "if" => { "type" => "string" } },
      { "type" => "array", "prefixItems" => [{ "type" => "string" }] },
      { "type" => "object", "properties" => { "ab" => {} }, "patternProperties" => { "^a" => {} } },
      { "type" => "array", "minContains" => 2 },
      { "type" => "object", "allOf" => [{ "type" => "number" }] }
    ].each do |schema|
      contract = Fixtures.contract_document("campaign-send-approval").merge("detailsSchema" => schema)
      assert_equal [], Mailschema.contract_errors(contract), schema.inspect
    end
  end

  def test_reports_root_errors_at_the_document_it_checks
    contract = Fixtures.contracts.fetch("publication-approval")
    assert_match %r{\A/details: }, contract.details_errors("details").first
    assert_match %r{\A/input: }, contract.input_errors("request-changes", "comment").first
    assert_match %r{\A/: }, Mailschema.contract_errors([]).first
  end

  def test_refuses_a_contract_beyond_its_size_limit
    contract = Fixtures.contract_document("campaign-send-approval")
    contract["detailsSchema"]["description"] = "x" * Mailschema::CONTRACT_MAX_BYTES
    assert_includes Mailschema.contract_errors(contract), "/: exceeds 262144 bytes"
  end

  # Verdicts and reasons of the reference implementation's unportablePattern.
  PATTERNS = {
    "^[a-z][a-z0-9-]{0,63}$" => nil,
    "^\\d{4}-\\d{2}$" => nil,
    "^(?:ab|cd)+[\\-x-z]?\\u00e9$" => nil,
    "[-a]" => nil,
    "[a-]" => nil,
    "a{2,}" => nil,
    "^.+$" => "an unescaped dot",
    "[a-z-0]" => "an ambiguous hyphen in a class",
    "[z-a]" => "a class range out of order",
    "[]" => "an empty character class",
    "[a" => "an unclosed character class",
    "[[a]]" => "a bracket inside a class",
    "[a&&b]" => "&& inside a class",
    "[\\d]" => "the escape \\d",
    "(a)" => "a group other than (?:",
    "(?:a" => "an unclosed group",
    "a)" => "an unmatched )",
    "a{2,1}" => "a {n,m} quantifier with m below n",
    "a{x}" => "a malformed {n,m} quantifier",
    "a**" => "a quantifier on a quantifier",
    "*a" => "a quantifier with nothing to repeat",
    "{" => "an unescaped {",
    "a}" => "an unescaped }",
    "\\w" => "the escape \\w",
    "\\ud800" => "a surrogate \\u escape",
    "\\u00g0" => "a malformed \\u escape",
    "a\\" => "a trailing backslash",
    "é" => "a character outside printable ASCII"
  }.freeze

  def test_holds_patterns_to_the_portable_subset
    PATTERNS.each do |pattern, problem|
      contract = Fixtures.contract_document("campaign-send-approval")
      contract["detailsSchema"]["properties"]["summary"]["pattern"] = pattern
      expected = problem && ["/detailsSchema/properties/summary: pattern #{JSON.generate(pattern)} uses #{problem}"]
      assert_equal expected || [], Mailschema.contract_errors(contract), pattern
    end
  end
end

class ImplementationTest < Minitest::Test
  def record
    contract = Fixtures.contracts.fetch("campaign-send-approval")
    {
      "service" => "https://example.org",
      "maintainer" => { "name" => "Example", "url" => "https://example.org" },
      "type" => { "id" => contract.id, "version" => contract.version, "contractDigest" => contract.digest },
      "operations" => ["approve"],
      "binding" => "https://example.org/map-binding",
      "status" => "Draft",
      "documentation" => "https://example.org/docs/map",
      "evidence" => [{ "kind" => "declaration", "url" => "https://example.org/docs/map", "summary" => "Supported." }]
    }
  end

  def test_accepts_a_service_origin
    assert_equal [], Mailschema.implementation_errors(record)
    assert_equal [], Mailschema.implementation_errors(record.merge("service" => "https://example.org/"))
    assert_equal record, Mailschema.parse_implementation(JSON.generate(record))
  end

  def test_refuses_an_operation_path_in_place_of_a_service_origin
    %w[https://example.org/map https://EXAMPLE.org https://example.org:443].each do |service|
      assert_equal ["/service: must be an HTTPS origin, not an operation path"],
                   Mailschema.implementation_errors(record.merge("service" => service)), service
    end
    error = assert_raises(Mailschema::InvalidDocument) do
      Mailschema.parse_implementation(JSON.generate(record.merge("service" => "https://example.org/map")))
    end
    assert_equal "The value is not an implementation record.", error.message
  end
end
