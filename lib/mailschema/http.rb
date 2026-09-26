# frozen_string_literal: true

# The HTTP binding: which requests the execution URL admits, and where results live.
module Mailschema
  # Whether a Content-Type admits a request rather than a 415: the media type
  # application/json, compared case-insensitively, with no parameter other than a
  # UTF-8 charset. Only HTTP's optional whitespace, spaces and tabs, may surround
  # each part, and empty parameter slots are ignored, as RFC 9110 permits. Bytes that
  # are not text admit nothing.
  def self.json_request?(content_type)
    text = content_type.to_s
    return false unless text.valid_encoding?

    type, *parameters = text.split(";", -1).map { |part| part.gsub(/\A[ \t]+|[ \t]+\z/, "").downcase }
    type == "application/json" &&
      parameters.all? { |parameter| parameter.empty? || parameter.match?(/\Acharset=(?:utf-8|"utf-8")\z/) }
  end

  # The result resource of a request: the description's template, with the request
  # identifier encoded as ECMAScript's encodeURIComponent encodes it.
  def self.result_url(description, request_id)
    encoded = request_id.to_s.b.gsub(/[^A-Za-z0-9\-_.!~*'()]/n) { |byte| format("%%%02X", byte.ord) }
    description.dig("service", "execution", "resultUrlTemplate").sub("{requestId}") { encoded }
  end
end
