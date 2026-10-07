# frozen_string_literal: true

require "test_helper"

class AuthenticationTest < Minitest::Test
  Signature = Mailschema::Authentication::Signature

  RAW = <<~MAIL.gsub("\n", "\r\n")
    From: Publisher <editor@publisher.example>
    To: owner@example.net
    Subject: Review this publication
    Date: Fri, 02 Oct 2026 08:00:00 +0000
    Message-ID: <review@publisher.example>
    MIME-Version: 1.0
    Content-Type: text/plain; charset=UTF-8
    DKIM-Signature: v=1; a=rsa-sha256; d=publisher.example; s=s1;
     h=from:to:subject:date:message-id:mime-version:content-type; bh=x; b=x

    Review.
  MAIL
  SIGNED = %w[From To Subject Date Message-ID MIME-Version Content-Type].freeze

  def test_finds_the_qualifying_signature
    assert_equal signature, qualifying
    assert_equal signature(algorithm: "ed25519-sha256", key_type: "ed25519", key_bits: 256),
                 qualifying(signatures: [signature(algorithm: "ed25519-sha256", key_type: "ed25519", key_bits: 256)])
    upper = signature(domain: "PUBLISHER.example")
    assert_equal upper, qualifying(signatures: [upper])
    assert_equal signature(key_bits: 1024), qualifying(signatures: [signature(pass: false), signature(key_bits: 1024)])
  end

  def test_refuses_a_failed_or_partial_body_signature
    assert_nil qualifying(signatures: [signature(pass: false)])
    assert_nil qualifying(signatures: [signature(body_length_limited: true)])
    assert_nil qualifying(signatures: [signature(body_length_limited: nil)])
  end

  def test_refuses_a_signature_missing_a_required_header
    assert_nil qualifying(signatures: [signature(signed_headers: SIGNED - ["Content-Type"])])
  end

  def test_requires_present_conditional_headers_once_and_signed
    with_cc = RAW.sub("Subject:", "Cc: copy@example.net\r\nSubject:")
    assert_nil qualifying(with_cc)
    assert_equal signature(signed_headers: [*SIGNED, "Cc"]),
                 qualifying(with_cc, signatures: [signature(signed_headers: [*SIGNED, "Cc"])])
    expires_twice = RAW.sub("Subject:", "Expires: a\r\nExpires: b\r\nSubject:")
    assert_nil qualifying(expires_twice, signatures: [signature(signed_headers: [*SIGNED, "Expires"])])
  end

  def test_refuses_repeated_or_missing_required_headers
    assert_nil qualifying(RAW.sub("Subject:", "From: Forger <forger@publisher.example>\r\nSubject:"))
    assert_nil qualifying(RAW.sub("Subject: Review this publication\r\n", ""))
  end

  def test_requires_exactly_one_author_mailbox
    from = "From: Publisher <editor@publisher.example>"
    assert_nil qualifying(RAW.sub(from, "From: editor@publisher.example, other@publisher.example"))
    assert_nil qualifying(RAW.sub(from, "From: Group: editor@publisher.example;"))
    assert_nil qualifying(RAW.sub(from, "From: undisclosed"))
  end

  def test_refuses_weak_or_unknown_algorithms
    assert_nil qualifying(signatures: [signature(key_bits: 512)])
    assert_nil qualifying(signatures: [signature(algorithm: "rsa-sha1")])
    assert_nil qualifying(signatures: [signature(algorithm: "ed25519-sha256")])
  end

  def test_requires_strict_alignment_by_default
    assert_nil qualifying(signatures: [signature(domain: "mail.publisher.example")])
    assert_nil qualifying(signatures: [signature(domain: "notpublisher.example")])
  end

  def test_relaxes_alignment_with_organizational_domains_the_caller_supplies
    organizational = ->(domain) { domain.split(".").last(2).join(".") }
    subdomain = signature(domain: "mail.publisher.example")
    assert_equal subdomain, qualifying(signatures: [subdomain], organizational_domain: organizational)
    assert_nil qualifying(signatures: [signature(domain: "other.example")], organizational_domain: organizational)
    assert_nil qualifying(signatures: [subdomain], organizational_domain: ->(_domain) {})
  end

  def test_refuses_a_header_block_that_is_not_crlf
    assert_nil qualifying(RAW.gsub("\r\n", "\n"))
    assert_nil qualifying(RAW.sub("To: owner@example.net\r\n", "To: owner@example.net\nX-Hidden: 1\r\n"))
  end

  private

  def signature(**changes)
    Signature.new(pass: true, domain: "publisher.example", body_length_limited: false, algorithm: "rsa-sha256",
                  key_type: "rsa", key_bits: 2048, signed_headers: SIGNED).with(**changes)
  end

  def qualifying(raw = RAW, signatures: [signature], organizational_domain: nil)
    Mailschema::Authentication.qualifying(raw_message: raw, signatures: signatures,
                                          organizational_domain: organizational_domain)
  end
end
