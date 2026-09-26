# frozen_string_literal: true

require "test_helper"

class ContractTest < Minitest::Test
  ZERO = "sha-256:#{"0" * 64}".freeze
  ELSEWHERE = "https://example.com/x.json"
  UNPUBLISHED = "https://mailschema.org/schemas/unpublished-0.1.schema.json"

  def test_type_reference_is_the_digest_of_the_contract
    Fixtures.types.each do |slug|
      contract = Fixtures.contract(slug)
      assert_equal Mailschema.digest(Fixtures.contract_files(slug).first), contract.digest, slug
      assert_equal Fixtures.description(slug).fetch("type"), contract.type_reference, slug
    end
  end

  def test_a_contract_is_refused_unless_it_is_the_one_pinned
    document, schema = Fixtures.contract_files("meeting-scheduling")
    error = assert_raises(Mailschema::InvalidContract) { Mailschema::Contract.new(document, schema, digest: ZERO) }
    assert_match(/not the pinned/, error.message)
    changed = deep_copy(document).merge("title" => "Changed")
    assert_raises(Mailschema::InvalidContract) do
      Mailschema::Contract.new(changed, schema, digest: Fixtures.pinned("meeting-scheduling"))
    end
  end

  # Each contract here is pinned by its own digest, so the rule itself must refuse it.
  def test_contracts_that_break_a_rule_are_refused_even_when_pinned
    document, schema = Fixtures.contract_files("meeting-scheduling")
    {
      "a dependency digest" => [->(c, _) { c["dependencies"][0]["canonicalDigest"] = ZERO }, /pinned digest of/],
      "an unpinned core" => [->(c, _) { c["dependencies"].reject! { |d| d["url"] == Mailschema::CORE_SCHEMA } },
                             /core schema must be pinned/],
      "an unknown dependency" => [->(c, _) { c["dependencies"] << { "url" => UNPUBLISHED, "canonicalDigest" => ZERO } },
                                  /unknown dependency/],
      "a dependency outside MailSchema" => [
        ->(c, _) { c["dependencies"] << { "url" => ELSEWHERE, "canonicalDigest" => ZERO } }, /invalid type contract/
      ],
      "an unpinned reference" => [->(c, _) { c["detailsSchema"]["properties"]["extra"] = { "$ref" => ELSEWHERE } },
                                  /not a pinned dependency/],
      "the request schema" => [->(_, s) { s["title"] = "Changed" }, /request schema digest differs/],
      "another profile" => [->(c, _) { c["profile"] = "https://mailschema.org/profiles/map/0.1" }, /profile/],
      "the contract format" => [->(c, _) { c.delete("operations") }, /invalid type contract/],
      "a duplicate operation" => [->(c, _) { c["operations"] << c["operations"].first }, /duplicate operation/],
      "a local reference" => [->(c, _) { c["detailsSchema"]["properties"]["extra"] = { "$ref" => "#/$defs/x" } },
                              /not a pinned dependency/],
      "a reference that does not resolve" => [
        ->(c, _) { c["detailsSchema"]["properties"]["extra"] = { "$ref" => "#{Mailschema::CORE_SCHEMA}#/$defs/none" } },
        /does not name a schema/
      ],
      "a pattern that does not compile" => [
        ->(c, _) { c["detailsSchema"]["properties"]["extra"] = { "type" => "string", "pattern" => "^[^]$" } },
        /does not compile/
      ],
      "a property pattern that does not compile" => [
        ->(c, _) { c["operations"][0]["results"][0]["outputSchema"]["patternProperties"] = { "(" => {} } },
        /not valid JSON Schema|does not compile/
      ],
      "an anchor reference" => [
        ->(c, _) { c["detailsSchema"]["properties"]["extra"] = { "$ref" => "#{Mailschema::CORE_SCHEMA}#anchor" } },
        /names an anchor/
      ],
      "a reference to a number" => [
        lambda do |c, _|
          c["detailsSchema"]["properties"]["extra"] =
            { "$ref" => "#{Mailschema::CORE_SCHEMA}#/$defs/description/properties/service/properties/name/maxLength" }
        end,
        /does not name a schema/
      ],
      "a reference to an array" => [
        lambda do |c, _|
          c["detailsSchema"]["properties"]["extra"] = { "$ref" => "#{Mailschema::CORE_SCHEMA}#/$defs/description/required" }
        end,
        /does not name a schema/
      ],
      "a dynamic reference" => [
        ->(c, _) { c["detailsSchema"]["properties"]["extra"] = { "$dynamicRef" => "#meta" } },
        /\$dynamicRef is not pinned by any digest/
      ],
      "a percent-encoded pointer" => [
        lambda do |c, _|
          c["detailsSchema"]["properties"]["extra"] = { "$ref" => "#{Mailschema::CORE_SCHEMA}#/$defs%2FnonBlank" }
        end,
        /not a plain JSON Pointer/
      ],
      "a nested $id" => [
        lambda do |c, _|
          c["detailsSchema"]["properties"]["extra"] = { "$id" => Mailschema::CORE_SCHEMA, "type" => "string" }
        end,
        /nested \$id/
      ],
      "a nested $schema" => [
        lambda do |c, _|
          c["detailsSchema"]["properties"]["extra"] =
            { "$schema" => "http://json-schema.org/draft-07/schema#", "type" => "string" }
        end,
        /nested \$schema/
      ],
      "a request schema in another dialect" => [
        ->(_, s) { s["$schema"] = "http://json-schema.org/draft-07/schema#" },
        /declare JSON Schema 2020-12/
      ],
      "an autocomplete of the contract's own" => [
        ->(c, _) { c["detailsSchema"]["properties"]["properties"] = { "type" => "string", "autocomplete" => "email" } },
        /autocomplete belongs/
      ],
      "an $id at the details root" => [
        ->(c, _) { c["detailsSchema"]["$id"] = "https://example.com/d.json" },
        /nested \$id/
      ],
      "a type list" => [
        ->(c, _) { c["detailsSchema"]["properties"]["extra"] = { "type" => %w[string null] } },
        /one type/
      ],
      "a reference that is not a string" => [
        ->(c, _) { c["detailsSchema"]["properties"]["extra"] = { "$ref" => 5 } },
        /not a string|invalid type contract/
      ],
      "a malformed keyword" => [
        ->(c, _) { c["operations"][0]["results"][0]["outputSchema"]["multipleOf"] = 0 },
        /not valid JSON Schema/
      ],
      "a reference to a map of properties" => [
        lambda do |c, _|
          c["detailsSchema"]["properties"]["extra"] = { "$ref" => "#{Mailschema::CORE_SCHEMA}#/$defs/description/properties" }
        end,
        /does not resolve|does not name a schema/
      ]
    }.each do |name, (mutate, message)|
      contract = deep_copy(document)
      request_schema = deep_copy(schema)
      mutate.call(contract, request_schema)
      error = assert_raises(Mailschema::InvalidContract, name) do
        Mailschema::Contract.new(contract, request_schema, digest: Mailschema.digest(contract))
      end
      assert_match message, error.message, name
    end
  end

  # A reference may name a schema inside an array, as RFC 6901 allows.
  def test_a_reference_through_an_array_loads
    document, schema = Fixtures.contract_files("meeting-scheduling")
    document["detailsSchema"]["properties"]["extra"] = { "$ref" => "#{Mailschema::CORE_SCHEMA}#/$defs/description/allOf/0" }
    assert Mailschema::Contract.new(document, schema, digest: Mailschema.digest(document))
  end

  def test_contracts_are_frozen_copies
    document, schema = Fixtures.contract_files("content-review")
    contract = Mailschema::Contract.new(document, schema, digest: Fixtures.pinned("content-review"))
    document["title"] = "Changed"
    refute_equal "Changed", contract.document["title"]
    assert contract.document.frozen?
    assert contract.document.fetch("operations").first.frozen?
  end

  def test_decisions_and_repeatable_operations
    contract = Fixtures.contract("content-review")
    assert contract.decision?("approve")
    refute contract.decision?("request-changes")
    assert_raises(ArgumentError) { contract.decision?("publish") }
  end

  def test_description_rules
    contract = Fixtures.contract("content-review")
    base = Fixtures.description("content-review")
    {
      "an operation offered twice" => ->(d) { d["operations"] << d["operations"].first },
      "reversed dates" => ->(d) { d["expiresAt"] = d["describedAt"] },
      "another contract" => ->(d) { d["type"]["contractDigest"] = ZERO },
      "possession for a credential operation" => lambda do |d|
        d["service"]["authority"] = "possession"
        d["service"].delete("resource")
        d["recipient"] = "alex@example.org"
      end,
      "details the contract refuses" => ->(d) { d["details"] = { "unknown" => 1 } },
      "an operation id with a line break" => ->(d) { d["operations"][0]["id"] = "approve\nevil" }
    }.each do |name, mutate|
      description = deep_copy(base)
      mutate.call(description)
      refute_empty contract.description_errors(description), name
    end
  end

  # Without a contract, a description can be checked against the core alone.
  def test_descriptions_of_unknown_types_meet_the_core
    description = Fixtures.description("content-review")
    description["type"] = description["type"].merge("id" => "https://types.example/unknown", "contractDigest" => ZERO)
    assert_empty Mailschema.description_errors(description)
    refute_empty Fixtures.contract("content-review").description_errors(description)
    refute_empty Mailschema.description_errors(description.merge("expiresAt" => "2026-10-02 08:00:00Z"))
  end

  def test_request_problems_come_before_state_and_input
    contract = Fixtures.contract("content-review")
    description = Fixtures.description("content-review")
    request = Fixtures.json("map-0.2/content-review/approve.request.json")
    expires_at = Time.iso8601(description.fetch("expiresAt"))
    before = expires_at - 1
    code = lambda do |changes = {}, now: before, offered: description|
      contract.request_problem(offered, request.merge(changes), now:)&.code
    end
    assert_nil code.call
    assert_equal "unsupported-type", code.call({ "type" => request["type"].merge("version" => "9.9") })
    assert_equal "unsupported-type", code.call({ "type" => request["type"].merge("contractDigest" => ZERO) })
    assert_equal "unsupported-operation", code.call({ "operation" => "publish" })
    withheld = deep_copy(description).tap { |d| d["operations"].reject! { |offer| offer["id"] == "approve" } }
    assert_equal "unsupported-operation", code.call(offered: withheld)
    assert_equal "expired-interaction", code.call(now: expires_at)
    assert_equal "unsupported-type", code.call({ "type" => request["type"].merge("version" => "9.9") }, now: expires_at)
  end

  def test_an_operation_is_offered_only_under_an_authority_it_permits
    contract = Fixtures.contract("account-activity")
    description = Fixtures.description("account-activity")
    request = Fixtures.json("map-0.2/account-activity/confirm.request.json")
    now = Time.iso8601(description.fetch("describedAt"))
    assert_nil contract.request_problem(description, request, now:)
    description["service"]["authority"] = "possession"
    problem = contract.request_problem(description, request, now:)
    assert_equal ["unsupported-operation", "Unsupported operation"], [problem.code, problem.title]
    built = Mailschema.problem(problem.code, title: problem.title, detail: problem.detail,
                                             request_id: request["requestId"],
                                             interaction_id: request["interactionId"],
                                             result_url: Mailschema.result_url(description, request["requestId"]))
    assert_empty Mailschema.problem_errors(built)
  end

  def test_form_rules
    contract = Fixtures.contract("information-request")
    description = Fixtures.description("information-request")
    description["details"]["fields"]["required"] << "ghost"
    assert_includes contract.description_errors(description).join, "ghost"
  end

  def test_capability_issuance
    contract = Fixtures.contract("email-confirmation")
    base = Fixtures.description("email-confirmation")
    capability = base.dig("service", "execution", "url").split("/").last
    assert_equal capability, Mailschema.capability(base)
    replace = lambda do |from, to|
      lambda do |d|
        execution = d["service"]["execution"]
        execution["url"] = execution["url"].sub(from, to)
        execution["resultUrlTemplate"] = execution["resultUrlTemplate"].sub(from, to)
      end
    end
    {
      "a short capability" => replace.call(capability, "short"),
      "a trailing slash" => ->(d) { d["service"]["execution"]["url"] += "/" },
      "a dot segment" => replace.call("/map/c/", "/map/./c/"),
      "an encoded dot segment" => replace.call("/map/c/", "/map/%2E%2e/c/"),
      "a dot segment in the result template" => lambda do |d|
        d["service"]["execution"]["resultUrlTemplate"] = d["service"]["execution"]["resultUrlTemplate"]
                                                         .sub("/results/", "/results/../results/")
      end,
      "a result template without it" => lambda do |d|
        d["service"]["execution"]["resultUrlTemplate"] = "https://accounts.example.com/map/results/{requestId}"
      end,
      "a result template outside the execution URL" => lambda do |d|
        d["service"]["execution"]["resultUrlTemplate"] = "https://accounts.example.com/map/r/c/#{capability}/{requestId}"
      end,
      "a request identifier in the fragment" => lambda do |d|
        d["service"]["execution"]["resultUrlTemplate"] = "#{d["service"]["execution"]["url"]}/results\#{requestId}"
      end,
      "a human route with it" => ->(d) { d["service"]["humanUrl"] = "https://accounts.example.com/confirm/#{capability}" }
    }.each do |name, mutate|
      description = deep_copy(base)
      mutate.call(description)
      refute_empty contract.description_errors(description), name
    end
  end

  # The capability is the path as written: a query, a fragment or an encoded slash
  # never moves it.
  def test_the_capability_is_the_last_segment_as_written
    base = Fixtures.description("email-confirmation")
    capability = Mailschema.capability(base)
    at = ->(url) { Mailschema.capability(deep_copy(base).tap { |d| d["service"]["execution"]["url"] = url }) }
    assert_equal capability, at.call("https://accounts.example.com/map/c/#{capability}?next=/x#/y")
    assert_equal "a%2Fb", at.call("https://accounts.example.com/map/c/a%2Fb")
    assert_equal "", at.call("https://accounts.example.com/map/c/#{capability}/")
    assert_equal "", at.call("https://accounts.example.com")
  end

  def test_input_errors_point_into_the_input
    contract = Fixtures.contract("content-review")
    description = Fixtures.description("content-review")
    request = Fixtures.json("map-0.2/content-review/approve.request.json")
    pointers = lambda do |input, operation = "approve"|
      found = contract.input_errors(description, request.merge("operation" => operation, "input" => input))
      found.map { |error| error["pointer"] }
    end
    assert_equal ["/unexpected"], pointers.call({ "unexpected" => true })
    assert_equal ["/feedback"], pointers.call({}, "request-changes")
    assert_equal ["/feedback"], pointers.call({ "feedback" => "   " }, "request-changes")
    assert_equal ["/a~1b~0c"], pointers.call({ "a/b~c" => true })
    assert_equal [""], pointers.call({ "x" * 1500 => true })
    astral = "\u{1F600}" * 600
    assert_equal ["/#{astral}"], pointers.call({ astral => true })
    long = contract.input_errors(description, request.merge("input" => { "x" * 1500 => true }))
    invalid = Mailschema.problem("invalid-request", title: "Invalid", detail: "Invalid input.", errors: long,
                                                    request_id: request["requestId"],
                                                    interaction_id: request["interactionId"],
                                                    result_url: "https://reviews.example/map/results/x")
    assert_empty Mailschema.problem_errors(invalid)
    assert_equal [""], pointers.call({}, "publish")
  end

  def test_field_bindings
    contract = Fixtures.contract("information-request")
    description = Fixtures.description("information-request")
    request = Fixtures.json("map-0.2/information-request/submit-response.request.json")
    values = request.dig("input", "values")
    with = ->(input) { contract.input_errors(description, request.merge("input" => input)).map { |e| e["pointer"] } }
    assert_includes with.call({ "values" => values.merge("ceoHomeAddress" => "x") }), "/values/ceoHomeAddress"
    assert_includes with.call({ "values" => { "website" => "https://acme.example" } }), "/values/supportEmail"
    assert_includes with.call({ "values" => values.merge("supportEmail" => "not an address") }), "/values/supportEmail"
    assert_equal ["/values"], with.call({})
  end

  # A text field's format is the core lexical form of the same name, never a
  # validator's format checker.
  def test_field_formats_are_core_lexical_forms
    contract = Fixtures.contract("information-request")
    description = Fixtures.description("information-request")
    request = Fixtures.json("map-0.2/information-request/submit-response.request.json")
    values = request.dig("input", "values")
    with = lambda do |changes|
      input = { "values" => values.merge(changes) }
      contract.input_errors(description, request.merge("input" => input)).map { |e| e["pointer"] }
    end
    assert_empty with.call("website" => "urn:isbn:0451450523", "supportEmail" => "support+map@acme.example")
    assert_equal ["/values/website"], with.call("website" => "acme.example")
    assert_equal ["/values/website"], with.call("website" => "https://acme.example/a b")
    assert_equal ["/values/supportEmail"], with.call("supportEmail" => "support@acme..example")
    assert_equal ["/values/supportEmail"], with.call("supportEmail" => "Support <support@acme.example>")
  end

  # Ruby's `$` matches before a line break; MAP patterns read as ECMA-262 does.
  def test_requests_use_ecmascript_patterns
    request = Fixtures.json("map-0.2/content-review/approve.request.json")
    assert_empty Mailschema.request_errors(request)
    refute_empty Mailschema.request_errors(request.merge("operation" => "approve\nevil"))
    refute_empty Mailschema.request_errors(request.merge("requestId" => "#{request["requestId"]}\n"))
  end

  def test_result_rules
    contract = Fixtures.contract("content-review")
    declined = Fixtures.json("map-0.2/content-review/approve.declined.json")
    assert_empty contract.result_errors(declined)
    refute_empty contract.result_errors(declined.merge("reason" => "withdrawn"))
    refute_empty contract.result_errors(declined.merge("output" => { "extra" => true }))
    refute_empty contract.result_errors(declined.except("reason").merge("state" => "pending"))
    refute_empty contract.result_errors(declined.merge("operation" => "publish"))
  end
end
