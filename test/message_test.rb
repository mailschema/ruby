# frozen_string_literal: true

require "test_helper"

class MessageTest < Minitest::Test
  PROFILE = Mailschema::PROFILE

  def setup
    @description = Fixtures.example("publication-approval")
  end

  def test_extracts_the_one_designated_description
    result = extract(received("multipart/related", readable, machine_part))
    assert_equal :valid, result.status
    assert_nil result.reason
    assert_equal @description, result.description
  end

  def test_finds_the_related_entity_beside_attachments_and_other_structured_parts
    other_profile = machine_part(content_type: %(application/ld+json; profile="https://example.com/profiles/other"))
    unlabelled = machine_part(JSON.generate({ "@context" => "https://schema.org/", "@type" => "EmailMessage" }),
                              content_type: "application/ld+json; charset=UTF-8")
    mail = received("multipart/mixed", related(machine_part, other_profile, unlabelled), attachment("brief.txt"))
    assert_equal :valid, extract(mail).status
  end

  def test_round_trips_a_built_part
    part = Mailschema::Message.part(@description)
    assert_equal "quoted-printable", part.content_transfer_encoding
    assert_equal "Machine-readable", part.header["Content-Purpose"].value
    assert_equal PROFILE, part.content_type_parameters["profile"]
    result = extract(received("multipart/mixed", related(part), attachment("brief.txt")))
    assert_equal :valid, result.status
    assert_equal @description, result.description
  end

  def test_builds_only_a_valid_description
    error = assert_raises(Mailschema::InvalidDocument) do
      Mailschema::Message.part(@description.merge("expiresAt" => @description["issuedAt"]))
    end
    assert_equal ["/expiresAt: must be later than issuedAt"], error.errors
  end

  def test_finds_nothing_without_a_designated_part_of_this_profile
    assert_equal :none, extract(received("multipart/related", readable)).status
    assert_equal :none, extract(received("multipart/related", readable, machine_part(purpose: nil))).status
    other = machine_part(content_type: %(application/ld+json; profile="https://example.com/profiles/other"))
    assert_equal :none, extract(received("multipart/related", readable, other)).status
    plain = Mail.new(Mail.new { body "Review." }.encoded)
    assert_equal Mailschema::Message::Result.new(status: :none, reason: nil, description: nil), extract(plain)
  end

  def test_never_reads_a_part_inside_an_attachment
    attached_part = machine_part
    attached_part.content_disposition = "attachment; filename=map.json"
    assert_equal :none, extract(received("multipart/related", readable, attached_part)).status

    attached_entity = related(machine_part)
    attached_entity.content_disposition = "attachment"
    assert_equal :none, extract(received("multipart/mixed", readable, attached_entity)).status
  end

  def test_never_reads_a_part_inside_an_attached_message
    forwarded = Mail::Part.new
    forwarded.content_type = "message/rfc822"
    forwarded.body = received("multipart/related", readable, machine_part).encoded
    assert_equal :none, extract(received("multipart/mixed", readable, forwarded)).status
  end

  def test_refuses_two_designated_parts
    assert_invalid :multiple_parts, received("multipart/related", readable, machine_part, machine_part)
  end

  def test_refuses_a_repeated_content_type_parameter
    raw = received("multipart/related", readable, machine_part).encoded
    assert_invalid :ambiguous_headers, Mail.new(raw.sub(%(profile="#{PROFILE}"),
                                                        %(profile="#{PROFILE}"; profile="https://example.com/other")))
    assert_invalid :ambiguous_headers, Mail.new(raw.sub(%(profile="#{PROFILE}"),
                                                        %(profile="#{PROFILE}"; profile*=us-ascii''other)))
  end

  def test_refuses_repeated_fields
    raw = received("multipart/related", readable, machine_part).encoded
    assert_invalid :ambiguous_headers,
                   Mail.new(raw.sub("Content-Transfer-Encoding: base64",
                                    "Content-Transfer-Encoding: base64\r\nContent-Transfer-Encoding: 8bit"))
    assert_invalid :ambiguous_headers,
                   Mail.new(raw.sub("Content-Purpose: Machine-readable",
                                    "Content-Purpose: Machine-readable\r\nContent-Purpose: Other"))
  end

  def test_refuses_another_transfer_encoding
    raw = received("multipart/related", readable, machine_part).encoded
    assert_invalid :transfer_encoding, Mail.new(raw.sub("Content-Transfer-Encoding: base64",
                                                        "Content-Transfer-Encoding: 8bit"))
  end

  def test_refuses_a_part_labelled_with_a_profile_that_merely_contains_this_one
    longer = machine_part(content_type: %(application/ld+json; profile="#{PROFILE}0"))
    assert_invalid :media_type, received("multipart/related", readable, longer)
  end

  def test_refuses_a_part_outside_multipart_related
    assert_invalid :not_partial_representation, received("multipart/mixed", readable, machine_part)
  end

  def test_refuses_a_related_root_that_is_an_attachment
    assert_invalid :not_partial_representation, received("multipart/related", attachment("note.txt"), machine_part)
  end

  def test_refuses_a_related_root_that_is_not_readable
    raw = received("multipart/related", readable, machine_part).encoded
    # Mail sorts text/plain first, so the readable root is moved after the part in the bytes.
    boundary = raw[/boundary="([^"]+)"/, 1]
    head, text, machine, tail = raw.split(/(?=--#{Regexp.escape(boundary)})/)
    assert_invalid :not_partial_representation, Mail.new([head, machine, text, tail].join)
  end

  def test_honours_a_start_parameter_naming_the_root
    root = readable
    root.content_id = "<review@service.example>"
    mail = received(%(multipart/related; start="<review@service.example>"), machine_part, root)
    assert_equal :valid, extract(mail).status
  end

  def test_reads_a_root_of_alternatives
    alternatives = Mail::Part.new
    alternatives.content_type = "multipart/alternative"
    alternatives.add_part(readable)
    assert_equal :valid, extract(received("multipart/related", alternatives, machine_part)).status
  end

  def test_refuses_an_invalid_description_without_raising
    assert_invalid :invalid_description,
                   received("multipart/related", readable, machine_part('{"@type":"MailAction","@type":"MailAction"}'))
    assert_invalid :invalid_description,
                   received("multipart/related", readable, machine_part(JSON.generate(@description.merge("x" => 1))))
  end

  private

  def extract(mail) = Mailschema::Message.extract(mail)

  def assert_invalid(reason, mail)
    assert_equal Mailschema::Message::Result.new(status: :invalid, reason: reason, description: nil), extract(mail)
  end

  def machine_part(json = JSON.generate(@description), content_type: Mailschema::DESCRIPTION_MEDIA_TYPE,
                   purpose: "Machine-readable")
    Mail::Part.new.tap do |part|
      part.content_type = content_type
      part.header["Content-Purpose"] = purpose if purpose
      part.content_transfer_encoding = "base64"
      part.body = [json].pack("m0")
    end
  end

  def readable
    Mail::Part.new.tap do |part|
      part.content_type = "text/plain; charset=UTF-8"
      part.body = "Review the getting started guide."
    end
  end

  def attachment(filename)
    readable.tap { |part| part.content_disposition = "attachment; filename=#{filename}" }
  end

  def related(*parts)
    Mail::Part.new.tap do |entity|
      entity.content_type = "multipart/related"
      [readable, *parts].each { |part| entity.add_part(part) }
    end
  end

  # The message as a recipient reads it: from its encoded bytes.
  def received(content_type, *parts)
    mail = Mail.new
    mail.content_type = content_type
    parts.each { |part| mail.add_part(part) }
    Mail.new(mail.encoded)
  end
end
