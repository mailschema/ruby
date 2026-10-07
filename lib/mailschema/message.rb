# frozen_string_literal: true

module Mailschema
  # The MAP part of an email (Core, "Email representation"): the one designated description of
  # this profile, in a multipart/related entity whose root is the readable content it
  # describes. A description inside an attachment or an attached message is never read.
  module Message
    # What a message carries: status :none; :invalid, with the reason the part cannot be used;
    # or :valid, with the description.
    Result = Data.define(:status, :reason, :description)

    NONE = Result.new(status: :none, reason: nil, description: nil)
    READABLE = %w[text/plain text/html].freeze
    TRANSFER_ENCODINGS = %w[base64 quoted-printable].freeze
    SINGLE_FIELDS = %w[content-type content-purpose content-transfer-encoding].freeze

    class << self
      # The MAP description of a received Mail::Message, read from its original bytes (for
      # example with Mail.new(raw)). It never raises for untrusted input. Reasons:
      # :multiple_parts, :ambiguous_headers, :transfer_encoding, :media_type,
      # :not_partial_representation, :invalid_description and :unreadable.
      def extract(mail)
        designated = entities(mail).select { |part, _parent| designated?(part) }
        return NONE if designated.empty?
        return invalid(:multiple_parts) if designated.size > 1

        part, parent = designated.first
        reason = problem(part, parent)
        return invalid(reason) if reason

        Result.new(status: :valid, reason: nil, description: Mailschema.parse_description(part.body.decoded.b))
      rescue InvalidDocument
        invalid(:invalid_description)
      rescue StandardError
        invalid(:unreadable)
      end

      # The MIME part that carries a description: compact JSON in quoted-printable, since one
      # line of JSON is usually longer than SMTP's 998 octets and 8bit cannot carry it. It
      # raises InvalidDocument unless that JSON is a valid description.
      def part(description)
        json = JSON.generate(description)
        Mailschema.parse_description(json)
        Mail::Part.new.tap do |part|
          part.content_type = "#{DESCRIPTION_MEDIA_TYPE}; charset=UTF-8"
          part.content_transfer_encoding = "quoted-printable"
          part.header["Content-Purpose"] = "Machine-readable"
          # Mail takes a body assigned under a transfer encoding as already encoded.
          part.body = Mail::Encodings::QuotedPrintable.encode(json)
        end
      end

      private

      def invalid(reason) = Result.new(status: :invalid, reason: reason, description: nil)

      # Every part with its parent, at any depth. An attachment or an attached message is a
      # leaf, so nothing inside one is read.
      def entities(entity)
        entity.parts.flat_map do |part|
          attached?(part) || part.mime_type == "message/rfc822" ? [] : [[part, entity], *entities(part)]
        end
      end

      def attached?(part) = part.content_disposition.to_s.downcase.start_with?("attachment")

      # Every Content-Purpose the part declares, however many times it repeats it.
      def machine_readable?(part)
        part.header.fields.any? do |field|
          field.name.casecmp?("Content-Purpose") && field.value.to_s.casecmp?("Machine-readable")
        end
      end

      # A designated part labelled with this profile, judged from its original header lines,
      # before a parser picks one of repeated fields or parameters.
      def designated?(part)
        return false unless machine_readable?(part)

        types = content_types(part)
        types.any? { |value| value.downcase.include?("application/ld+json") } &&
          types.any? { |value| value.include?(PROFILE) }
      end

      def content_types(entity)
        Array(Header.fields(entity.raw_source.to_s, lax: true)).filter_map do |name, value|
          value if name == "content-type"
        end
      end

      def problem(part, parent)
        return :ambiguous_headers unless unambiguous?(part)
        return :transfer_encoding unless TRANSFER_ENCODINGS.include?(part.content_transfer_encoding.to_s.downcase)
        return :media_type unless description_part?(part)

        :not_partial_representation unless partial_representation?(parent)
      end

      # Each field that decides how the part is read appears once, with each parameter once.
      def unambiguous?(part)
        fields = Header.fields(part.raw_source.to_s, lax: true) or return false
        counts = fields.map(&:first).tally
        SINGLE_FIELDS.all? { |name| counts[name] == 1 } && Header.unique_parameters?(fields.assoc("content-type").last)
      end

      def description_part?(part)
        part.mime_type == "application/ld+json" && part.content_type_parameters&.[]("profile") == PROFILE
      end

      # A multipart/related entity with one unambiguous Content-Type, whose root (its start
      # parameter's part, or else its first) is readable.
      def partial_representation?(entity)
        return false unless entity.mime_type == "multipart/related"

        types = content_types(entity)
        return false unless types.one? && Header.unique_parameters?(types.first)

        start = entity.content_type_parameters&.[]("start")
        roots = start.to_s.empty? ? entity.parts.first(1) : entity.parts.select { |part| content_id(part) == start }
        roots.one? && readable?(roots.first)
      end

      def content_id(part) = part.header["Content-ID"]&.value.to_s.strip

      def readable?(part)
        return false if attached?(part)
        return part.parts.any? { |alternative| readable?(alternative) } if part.mime_type == "multipart/alternative"

        READABLE.include?(part.mime_type) && !part.body.decoded.b.strip.empty?
      end
    end
  end
end
