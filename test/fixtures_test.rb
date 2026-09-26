# frozen_string_literal: true

require "test_helper"

# Every published MAP 0.2 fixture, checked with its own type contract.
class FixturesTest < Minitest::Test
  def test_every_type_is_published
    assert_equal 10, Fixtures.types.size
  end

  def test_descriptions
    Fixtures.types.each do |slug|
      description = Fixtures.description(slug)
      assert_empty Mailschema.map_errors(description), slug
      assert_empty Fixtures.contract(slug).description_errors(description), slug
    end
  end

  def test_requests_bind_their_description_and_satisfy_their_contract
    each_fixture(".request.json") do |slug, name, request|
      description = Fixtures.description(slug)
      assert_empty Mailschema.request_errors(request), name
      assert_equal Mailschema.digest(description), request.fetch("descriptionDigest"), name
      assert_equal Fixtures.contract(slug).type_reference, request.fetch("type"), name
      assert_empty Fixtures.contract(slug).input_errors(description, request), name
    end
  end

  def test_results
    types = []
    each_fixture(".json") do |slug, name, document|
      next unless document["kind"] == "MapResult"

      types << slug
      assert_empty Mailschema.map_errors(document), name
      assert_empty Fixtures.contract(slug).result_errors(document), name
    end
    assert_equal Fixtures.types, types.uniq
  end

  def test_problems
    each_fixture(".problem.json") do |_, name, problem|
      assert_empty Mailschema.problem_errors(problem), name
      assert_equal Mailschema::PROBLEM_STATUS.fetch(problem.fetch("code")), problem.fetch("status"), name
    end
  end

  # The bundled artifacts are the bytes the profile record binds.
  def test_bundled_artifacts_match_the_profile_record
    profile = Fixtures.json("profile.json")
    assert_equal Mailschema::PROFILE, profile.fetch("id")
    { "schema" => Mailschema::CORE_SCHEMA, "context" => Mailschema::CONTEXT,
      "contractFormat" => Mailschema::CONTRACT_FORMAT }.each do |name, url|
      assert_equal profile.dig("artifacts", name, "sha256"), Digest::SHA256.hexdigest(Mailschema.artifact(url)), name
    end
  end

  def test_artifacts_are_fresh_copies
    first = Mailschema.document(Mailschema::CORE_SCHEMA)
    first["title"] = "mutated"
    refute_equal "mutated", Mailschema.document(Mailschema::CORE_SCHEMA)["title"]
    assert Mailschema.artifact(Mailschema::CONTEXT).frozen?
    assert_equal "MailSchema contribution format", Mailschema.document(Mailschema::CONTRIBUTION_SCHEMA)["title"]
  end

  private

  def each_fixture(suffix)
    Fixtures.types.each do |slug|
      Dir[File.join(Fixtures::ROOT, "map-0.2", slug, "*#{suffix}")].each do |path|
        next if File.basename(path) == "description.json"

        yield slug, "#{slug}/#{File.basename(path)}", JSON.parse(File.binread(path))
      end
    end
  end
end
