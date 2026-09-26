# frozen_string_literal: true

require "test_helper"

class DocumentsTest < Minitest::Test
  APPROVAL = "https://reviews.example/approvals/1"

  def setup
    @contract = Fixtures.contract("content-review")
    @description = Fixtures.description("content-review")
    @request = Fixtures.json("map-0.2/content-review/approve.request.json")
    @url = Mailschema.result_url(@description, @request.fetch("requestId"))
    @at = Time.utc(2026, 9, 25, 9)
    @correlated = { request_id: @request["requestId"], interaction_id: @request["interactionId"], result_url: @url }
  end

  def result(state, **)
    Mailschema.result(@request, state:, target: @description.fetch("target"), result_url: @url, recorded_at: @at, **)
  end

  def test_results_validate_against_the_core_and_the_contract
    [
      result("completed", output: { "decision" => "approved" }, actor: "agent-1"),
      result("approval-required", approval_url: APPROVAL),
      result("failed", reason: "declined")
    ].each do |built|
      assert_empty Mailschema.map_errors(built), built["state"]
      assert_empty @contract.result_errors(built), built["state"]
    end
    assert_equal "2026-09-25T09:00:00.000Z", result("failed", reason: "declined").fetch("recordedAt")
  end

  def test_results_enforce_approval_links_and_reasons
    assert_raises(ArgumentError) { result("approval-required") }
    assert_raises(ArgumentError) { result("completed", approval_url: APPROVAL) }
    assert_raises(ArgumentError) { result("failed") }
    assert_raises(ArgumentError) { result("completed", reason: "declined") }
  end

  def test_transitions_keep_correlation_and_the_actor
    proposed = result("approval-required", approval_url: APPROVAL, actor: "agent-1")
    superseded = Mailschema.transition(proposed, state: "failed", reason: "superseded", recorded_at: @at + 60)
    kept = %w[state approvalUrl reason recordedAt]
    assert_equal proposed.except(*kept), superseded.except(*kept)
    assert_equal "superseded", superseded.fetch("reason")
    assert_empty @contract.result_errors(superseded)
    assert_raises(ArgumentError) { Mailschema.transition(superseded, state: "completed", recorded_at: @at) }
    assert_raises(ArgumentError) { Mailschema.transition(proposed, state: "pending", recorded_at: @at) }
  end

  def test_an_undecided_approval_expires_at_the_deadline
    proposed = result("approval-required", approval_url: APPROVAL)
    expires_at = Time.iso8601(@description.fetch("expiresAt"))
    assert_nil Mailschema.settle(proposed, @description, expires_at - 1)
    settled = Mailschema.settle(proposed, @description, expires_at + 3600)
    assert_equal ["failed", "expired", expires_at.utc.iso8601(3)], settled.values_at("state", "reason", "recordedAt")
    assert_nil Mailschema.settle(settled, @description, expires_at + 7200)
    assert_equal "failed", Mailschema.settle(proposed, @description, expires_at)&.fetch("state")
  end

  def test_deadlines_are_reached_at_the_instant
    deadline = "2026-10-02T08:00:00.500+10:00"
    at = Time.utc(2026, 10, 1, 22, 0, 0.5r)
    refute Mailschema.reached?(at - 0.001, deadline)
    assert Mailschema.reached?(at, deadline)
    refute Mailschema.reached?(at, deadline, after: 1)
    assert Mailschema.reached?(at + 1, deadline, after: 1)
  end

  # A deadline that is not a core date-time has passed, even where Ruby or JavaScript
  # would parse it, so a mistake fails closed.
  def test_a_deadline_that_is_not_a_core_date_time_has_passed
    now = Time.utc(2026, 9, 25)
    ["", "tomorrow", nil, 1, "Fri, 25 Sep 2099 08:00:00 GMT", "2099-09-25t08:00:00z", "2099-09-25T08:00:00",
     " 2099-09-25T08:00:00Z"].each { |deadline| assert Mailschema.reached?(now, deadline), deadline.inspect }
    refute Mailschema.reached?(now, "2099-09-25T08:00:00Z")
  end

  def test_retention_runs_from_the_latest_state
    expires_at = Time.iso8601(@description.fetch("expiresAt"))
    retention = @description.dig("service", "execution", "resultRetentionSeconds")
    assert_equal expires_at, Mailschema.retain_until(@description, expires_at - retention - 1)
    assert_equal expires_at + 10 + retention, Mailschema.retain_until(@description, expires_at + 10)
  end

  def test_problems_correlate_type_status_and_code
    Mailschema::PROBLEM_STATUS.except("authentication-required").each do |code, status|
      options = code == "stale-target" ? @correlated.merge(target: @description.fetch("target")) : @correlated
      problem = Mailschema.problem(code, title: "Title", detail: "Detail.", **options)
      assert_equal status, problem.fetch("status")
      assert_empty Mailschema.problem_errors(problem), code
      # Only these can be answered without correlation; every other code is about a
      # claimed request.
      uncorrelated = -> { Mailschema.problem(code, title: "Title", detail: "Detail.") }
      if %w[invalid-request refused].include?(code)
        assert_empty Mailschema.problem_errors(uncorrelated.call), code
      else
        assert_raises(ArgumentError, code, &uncorrelated)
      end
    end
    errors = [{ "detail" => "Required.", "pointer" => "/feedback" }]
    invalid = Mailschema.problem("invalid-request", title: "Invalid", detail: "Detail.", errors:, **@correlated)
    assert_empty Mailschema.problem_errors(invalid)
    not_found = Mailschema.problem("result-not-found", title: "Not found", detail: "Detail.",
                                                       **@correlated.except(:interaction_id))
    assert_empty Mailschema.problem_errors(not_found)
  end

  # A detail beyond the core limit is cut at a code point, so the problem stays valid.
  def test_problem_details_stay_within_the_core_limit
    problem = Mailschema.problem("invalid-request", title: "Invalid", detail: "\u{1F600}" * 5000)
    assert_equal 4000, problem.fetch("detail").length
    assert_empty Mailschema.problem_errors(problem)
    assert_raises(ArgumentError) { Mailschema.problem("refused", title: "T" * 241, detail: "D.") }
    assert_raises(ArgumentError) { Mailschema.problem("refused", title: "", detail: "D.") }
    assert_raises(ArgumentError) { Mailschema.problem("refused", title: "T", detail: "") }
    assert_raises(ArgumentError) do
      Mailschema.problem("invalid-request", title: "T", detail: "D.", errors: [], **@correlated)
    end
  end

  # However many and however long its input errors, a problem stays a valid MAP document.
  def test_problems_stay_within_the_document_limit
    long = "\u{1F600}" * 1500
    errors = Array.new(150) { |index| { "detail" => "#{long}#{index}", "pointer" => "/#{"~0" * 700}#{index}" } }
    problem = Mailschema.problem("invalid-request", title: "Invalid", detail: "Detail.", errors:, **@correlated)
    assert_operator JSON.generate(problem).bytesize, :<=, Mailschema::MAX_BYTES
    assert_operator problem.fetch("errors").size, :>=, 1
    assert_empty Mailschema.problem_errors(problem)
    assert_equal problem, Mailschema.parse(JSON.generate(problem))
  end

  def test_problem_rules
    uncorrelated = @correlated.except(:interaction_id)
    assert_raises(ArgumentError) { Mailschema.problem("refused", title: "T", detail: "D.", **uncorrelated) }
    assert_raises(ArgumentError) { Mailschema.problem("stale-target", title: "T", detail: "D.", **@correlated) }
    errors = [{ "detail" => "D", "pointer" => "" }]
    assert_raises(ArgumentError) { Mailschema.problem("refused", title: "T", detail: "D.", errors:) }
    assert_raises(KeyError) { Mailschema.problem("teapot", title: "T", detail: "D.") }
  end

  # A builder never returns a document the core refuses.
  def test_builders_refuse_what_the_core_refuses
    ["garbage", @request.fetch("requestId").upcase].each do |request_id|
      assert_raises(ArgumentError, request_id) do
        Mailschema.problem("result-not-found", title: "T", detail: "D.", request_id:, result_url: @url)
      end
    end
    assert_raises(ArgumentError) { Mailschema.problem("stale-target", title: "T", detail: "D.") }
    assert_raises(ArgumentError) do
      Mailschema.result(@request, state: "completed", target: @description.fetch("target"),
                                  result_url: "http://reviews.example/r", recorded_at: @at)
    end
  end

  def test_request_identifiers_are_core_uuid_urns
    assert Mailschema.request_id?(@request.fetch("requestId"))
    ["garbage", @request.fetch("requestId").upcase, "#{@request.fetch("requestId")}\n", nil, 1, "\xFF", "\xFF".b]
      .each { |value| refute Mailschema.request_id?(value), value.inspect }
    refute Mailschema.json_request?("application/json; charset=\xFF")
  end

  # The status table restates the core schema, which is the authority.
  def test_problem_status_matches_the_core_schema
    core = Mailschema.document(Mailschema::CORE_SCHEMA)
    from_schema = core.dig("$defs", "problem", "allOf").filter_map do |rule|
      type = rule.dig("if", "properties", "type", "const")
      [type.delete_prefix(Mailschema::PROBLEM_TYPES), rule.dig("then", "properties", "status", "const")] if type
    end.to_h
    assert_equal from_schema, Mailschema::PROBLEM_STATUS
  end

  # The core never correlates authentication-required, and neither does the builder.
  def test_authentication_required_is_never_correlated
    uncorrelated = Mailschema.problem("authentication-required", title: "Authentication required", detail: "Sign in.")
    assert_empty Mailschema.problem_errors(uncorrelated)
    assert_raises(ArgumentError) do
      Mailschema.problem("authentication-required", title: "T", detail: "D.", **@correlated)
    end
    forged = uncorrelated.merge("instance" => @url, "profile" => Mailschema::PROFILE,
                                "requestId" => @request["requestId"], "interactionId" => @request["interactionId"],
                                "code" => "authentication-required")
    refute_empty Mailschema.problem_errors(forged)
  end

  def test_result_urls_encode_like_ecmascript
    expected = "https://reviews.example/map/results/urn%3Auuid%3Aabc"
    assert_equal expected, Mailschema.result_url(@description, "urn:uuid:abc")
    assert_equal 202, Mailschema.result_status(result("approval-required", approval_url: APPROVAL))
    assert_equal 200, Mailschema.result_status(result("failed", reason: "declined"))
  end

  def test_shared_media_type_vectors
    Fixtures.json("map-0.2/media-type-vectors.json").each do |vector|
      content_type = vector.fetch("contentType")
      assert_equal vector.fetch("accepted"), Mailschema.json_request?(content_type), content_type.inspect
    end
    refute Mailschema.json_request?(nil)
  end

  def test_description_parts_are_labelled_with_the_profile
    assert_equal %(application/ld+json; profile="#{Mailschema::PROFILE}"), Mailschema::DESCRIPTION_MEDIA_TYPE
    assert Mailschema.description_part?("application/ld+json", Mailschema::PROFILE)
    assert Mailschema.description_part?("Application/LD+JSON", "https://example.com/p #{Mailschema::PROFILE}")
    refute Mailschema.description_part?("application/ld+json", nil)
    refute Mailschema.description_part?("application/ld+json", "https://mailschema.org/profiles/map/0.3")
    refute Mailschema.description_part?("application/json", Mailschema::PROFILE)
  end
end
