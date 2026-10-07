# frozen_string_literal: true

require "test_helper"

class DescriptionTest < Minitest::Test
  # Each vector edits a published example by JSON Pointer. It is valid when the description
  # and its details under the example's contract both are.
  def test_shape_vectors
    Fixtures.json("shape-vectors.json").each do |vector|
      value = Fixtures.example(vector.fetch("example"))
      vector.fetch("edits").each { |edit| apply(value, edit) }
      contract = Fixtures.contracts.fetch(vector.fetch("example"))
      valid = Mailschema.description_errors(value).empty? && contract.details_errors(value["details"]).empty?
      assert_equal vector.fetch("valid"), valid, vector.fetch("id")
    end
  end

  def test_accepts_every_published_example_under_its_contract
    Fixtures.contracts.each do |slug, contract|
      description = Mailschema.parse_description(Fixtures.read("examples/#{slug}.json"))
      assert_equal [], contract.description_errors(description), slug
    end
  end

  def test_refuses_identifiers_with_formatting_characters_and_expiry_before_issuance
    description = Fixtures.example("publication-approval")
    assert_equal ["/recipient: must not contain whitespace, controls or formatting characters"],
                 Mailschema.description_errors(description.merge("recipient" => "owner\u{202E}@example.net"))
    assert_equal ["/expiresAt: must be later than issuedAt"],
                 Mailschema.description_errors(description.merge("expiresAt" => description["issuedAt"]))
  end

  def test_refuses_repeated_operations
    description = Fixtures.example("publication-approval")
    description["operations"] << { "id" => "approve" }
    assert_equal ["/operations: identifiers must be unique"], Mailschema.description_errors(description)
  end

  def test_reports_schema_errors_by_pointer
    description = Fixtures.example("publication-approval").merge("method" => "POST")
    errors = Mailschema.description_errors(description)
    refute_empty errors
    assert(errors.all? { |error| error.start_with?("/") })
  end

  def test_checks_a_description_against_the_contract_it_names
    contract = Fixtures.contracts.fetch("email-address-confirmation")
    description = Fixtures.example("email-address-confirmation")

    elsewhere = deep_copy(description)
    elsewhere["operations"][0]["capability"]["url"] = description.dig("operations", 0, "capability", "url")
                                                                 .sub("service.example", "other.example")
    assert_equal ["/operations/0/capability/url: must have the service's origin"],
                 contract.description_errors(elsewhere)

    long = description.merge("expiresAt" => "2026-10-04T08:00:01Z")
    assert_equal ["/expiresAt: a confirm capability lasts at most 86400 seconds"], contract.description_errors(long)

    other = deep_copy(description)
    other["type"]["contractDigest"] = Fixtures.contracts.fetch("publication-approval").digest
    other["operations"] << { "id" => "approve" }
    assert_equal ["/type/contractDigest: does not match",
                  "/operations/1/id: approve is not an operation of this contract"],
                 contract.description_errors(other)
  end

  def test_refuses_a_capability_the_contract_does_not_permit
    contract = Fixtures.contracts.fetch("publication-approval")
    description = Fixtures.example("publication-approval")
    description["operations"][0]["capability"] = { "url" => "https://service.example/c/approve" }
    assert_equal ["/operations/0/capability: the contract permits no capability for approve"],
                 contract.description_errors(description)
  end

  def test_parse_description_reports_every_reason
    text = JSON.generate(Fixtures.example("publication-approval").merge("expiresAt" => "2026-10-01T08:00:00Z"))
    error = assert_raises(Mailschema::InvalidDocument) { Mailschema.parse_description(text) }
    assert_equal "The value is not a MAP 0.3 description.", error.message
    assert_equal ["/expiresAt: must be later than issuedAt"], error.errors
  end

  private

  # A JSON Pointer edit: replace sets a member, including one the example lacks; remove
  # removes it.
  def apply(value, edit)
    *path, key = edit.fetch("path").split("/", -1).drop(1).map { |token| token.gsub("~1", "/").gsub("~0", "~") }
    target = path.reduce(value) { |node, token| node.is_a?(Array) ? node[Integer(token)] : node[token] }
    key = Integer(key) if target.is_a?(Array)
    if edit.fetch("op") == "replace"
      target[key] = edit.fetch("value")
    elsif target.is_a?(Array)
      target.delete_at(key)
    else
      target.delete(key)
    end
  end
end
