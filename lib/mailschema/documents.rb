# frozen_string_literal: true

# Building MAP results and problems, and the lifecycle rules every service applies.
module Mailschema
  # The HTTP status of every MAP problem code, as the core schema fixes it.
  PROBLEM_STATUS = {
    "invalid-request" => 400,
    "authentication-required" => 401,
    "refused" => 403,
    "result-not-found" => 404,
    "stale-target" => 409,
    "idempotency-conflict" => 409,
    "request-in-progress" => 409,
    "already-decided" => 409,
    "expired-interaction" => 410,
    "unsupported-type" => 422,
    "unsupported-operation" => 422
  }.freeze
  PROBLEM_TYPES = "https://mailschema.org/problems/"
  NON_TERMINAL_STATES = %w[pending approval-required].freeze

  # A result for a request, with every correlation member. `approval_url` is given
  # exactly for approval-required and `reason` exactly for failed. Like every builder
  # here, it raises ArgumentError rather than return a document the core refuses.
  def self.result(request, state:, target:, result_url:, recorded_at:, output: {}, reason: nil, approval_url: nil,
                  actor: nil)
    if (state == "approval-required") == approval_url.nil?
      raise ArgumentError, "approval_url is given exactly when the state is approval-required"
    end
    raise ArgumentError, "reason is given exactly when the state is failed" if (state == "failed") == reason.nil?

    built({
      "kind" => "MapResult",
      "profile" => PROFILE,
      "requestId" => request.fetch("requestId"),
      "interactionId" => request.fetch("interactionId"),
      "descriptionDigest" => request.fetch("descriptionDigest"),
      "type" => request.fetch("type"),
      "operation" => request.fetch("operation"),
      "state" => state,
      "target" => target,
      "recordedAt" => timestamp(recorded_at),
      "resultUrl" => result_url,
      "actor" => actor,
      "approvalUrl" => approval_url,
      "reason" => reason,
      "output" => output
    }.compact, :result_errors)
  end

  # The next state of a pending or approval-required result. Every correlation member
  # and the actor stay; the state, reason, output and recording time change.
  def self.transition(result, state:, recorded_at:, reason: nil, output: {})
    unless NON_TERMINAL_STATES.include?(result.fetch("state"))
      raise ArgumentError, "a #{result["state"]} result is terminal"
    end
    raise ArgumentError, "a transition ends pending work" if NON_TERMINAL_STATES.include?(state)
    raise ArgumentError, "reason is given exactly when the state is failed" if (state == "failed") == reason.nil?

    built(result.except("approvalUrl", "reason")
                .merge("state" => state, "reason" => reason, "output" => output, "recordedAt" => timestamp(recorded_at))
                .compact, :result_errors)
  end

  # A problem. With `request_id` it is correlated and carries `instance`, `profile`,
  # `requestId`, `interactionId` and `code`; without, it is plain RFC 9457. It stays
  # within the core limits: a long detail is cut, each input error is bounded, and
  # only as many of the first 100 errors as fit within 64 KiB are kept.
  def self.problem(code, title:, detail:, request_id: nil, interaction_id: nil, result_url: nil, target: nil,
                   errors: nil)
    status = PROBLEM_STATUS.fetch(code)
    title, detail, errors = Limits.problem_members(title, detail, errors)
    body = { "type" => "#{PROBLEM_TYPES}#{code}", "title" => title, "status" => status, "detail" => detail }
    raise ArgumentError, "an interaction is named only with its request" if interaction_id && !request_id
    if request_id && code == "authentication-required"
      raise ArgumentError, "authentication-required is never correlated"
    end
    if errors && !(request_id && code == "invalid-request")
      raise ArgumentError, "errors belong to a correlated invalid-request"
    end

    body.merge!(correlation(code, request_id, interaction_id, result_url, target)) if request_id
    built(Limits.within_document(body.merge("target" => target, "errors" => errors).compact), :problem_errors)
  end

  def self.correlation(code, request_id, interaction_id, result_url, target)
    raise ArgumentError, "a correlated problem names its result URL" unless result_url
    if interaction_id.nil? && code != "result-not-found"
      raise ArgumentError, "a correlated problem names its interaction"
    end
    raise ArgumentError, "a stale-target problem carries the current target" if code == "stale-target" && target.nil?

    { "instance" => result_url, "profile" => PROFILE, "requestId" => request_id,
      "interactionId" => interaction_id, "code" => code }
  end
  private_class_method :correlation

  # The HTTP status of a result: 202 while work is pending, otherwise 200.
  def self.result_status(result) = NON_TERMINAL_STATES.include?(result.fetch("state")) ? 202 : 200

  # Results stay retrievable until the later of the interaction's expiry and the
  # retention interval measured from the latest recorded state.
  def self.retain_until(description, recorded_at)
    retention = description.dig("service", "execution", "resultRetentionSeconds")
    [Time.iso8601(description.fetch("expiresAt")), recorded_at + retention].max
  end

  # An undecided approval ends as failed, with reason expired, at the interaction's
  # expiry, whether or not anyone looks. The settled result, or nil when nothing changes.
  def self.settle(result, description, now)
    return unless result.fetch("state") == "approval-required" && reached?(now, description.fetch("expiresAt"))

    transition(result, state: "failed", reason: "expired", recorded_at: Time.iso8601(description.fetch("expiresAt")))
  end

  def self.timestamp(time) = time.to_time.utc.iso8601(3)
  private_class_method :timestamp

  # The document, once the core definition `check` names accepts it.
  def self.built(document, check)
    refused = public_send(check, document)
    raise ArgumentError, "the core refuses this document: #{refused.first(3).join("; ")}" if refused.any?

    document
  end
  private_class_method :built
end
