# frozen_string_literal: true

require "test_helper"

class ArtifactsTest < Minitest::Test
  # The bundled artifacts are the bytes the profile record binds.
  def test_bundled_artifacts_match_the_profile_record
    profile = JSON.parse(File.binread(File.join(Fixtures::ARTIFACTS, "profile.json")))
    assert_equal Mailschema::PROFILE, profile.fetch("id")
    assert_equal Mailschema::CONTEXT, profile.fetch("context")
    { "context" => "context.jsonld", "schema" => "core.schema.json", "contractFormat" => "contract.schema.json" }
      .each do |name, file|
        assert_equal profile.dig("artifacts", name, "sha256"),
                     Digest::SHA256.file(File.join(Fixtures::ARTIFACTS, file)).hexdigest, name
      end
  end

  def test_constants
    assert_equal %(application/ld+json; profile="https://mailschema.org/profiles/map/0.3"),
                 Mailschema::DESCRIPTION_MEDIA_TYPE
    assert_equal [65_536, 262_144, 32], [Mailschema::DESCRIPTION_MAX_BYTES, Mailschema::CONTRACT_MAX_BYTES,
                                         Mailschema::MAX_DEPTH]
    assert_equal %w[address-confirmation protective-report refusal], Mailschema::CAPABILITY_KINDS.keys.sort
    assert_equal 604_800, Mailschema::CAPABILITY_KINDS.dig("refusal", :max_lifetime_seconds)
  end

  # Verdicts of the reference implementation's formats, where other validators differ.
  FORMATS = {
    "uri" => { "urn:example:tenant:7" => true, "https://a.example/~x?q=1#f" => true, "a:" => false,
               "https:" => false, "https://a.example?x=<y>" => false, "https://exämple.example" => false },
    "email" => { "owner@example.net" => true, "a@b" => false, '"quoted"@example.net' => false,
                 "a@[198.51.100.7]" => false, "\u{212A}elvin@example.net" => false },
    "date" => { "2024-02-29" => true, "2026-02-29" => false, "2026-04-31" => false },
    "date-time" => { "2026-10-02T08:00:00Z" => true, "2026-10-02 08:00:00+0530" => true,
                     "2026-10-02T08:00:00+05" => true, "2026-10-02T08:00:00" => false,
                     "2026-12-31T23:59:60Z" => true, "2026-10-02T23:59:60Z" => true, "2026-10-02T12:59:60Z" => false }
  }.freeze

  def test_asserts_formats_as_the_reference_implementation_does
    FORMATS.each do |format, values|
      schema = { "type" => "object", "properties" => { "value" => { "type" => "string", "format" => format } } }
      contract = Fixtures.contract_document("publication-approval").merge("detailsSchema" => schema)
      contract = Mailschema::Contract.new(contract)
      values.each do |value, valid|
        assert_equal valid, contract.details_errors({ "value" => value }).empty?, "#{format} #{value}"
      end
    end
  end

  def test_asserts_no_other_format
    schema = { "type" => "object", "properties" => { "value" => { "type" => "string", "format" => "hostname" } } }
    compiled = Mailschema.const_get(:Schemas).compile(schema)
    assert compiled.valid?({ "value" => "not a hostname" })
  end
end
