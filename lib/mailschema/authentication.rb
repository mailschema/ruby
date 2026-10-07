# frozen_string_literal: true

module Mailschema
  # Core "Qualifying message authentication", applied to the facts a DKIM verifier reports. The
  # gem verifies no signature and makes no DNS query: the caller's verifier does both, and this
  # module decides whether one verified signature qualifies the message for MAP actions.
  module Authentication
    # One signature as the verifier found it: whether it verified, its d= domain, whether it
    # carries an l= body length, its a= algorithm, its key's type and size, and its h= names.
    Signature = Data.define(:pass, :domain, :body_length_limited, :algorithm, :key_type, :key_bits,
                            :signed_headers) do
      def pass? = pass == true
      def body_length_limited? = body_length_limited != false
    end

    # Present exactly once and signed.
    REQUIRED = %w[from to subject date message-id mime-version content-type].freeze
    # Present at most once, and signed when present.
    CONDITIONAL = %w[cc supersedes expires].freeze

    class << self
      # The first signature that qualifies the message, or nil. `raw_message` is the message as
      # received, with CRLF line endings. Alignment with the From author domain is strict:
      # equal domains, ignoring case. Given `organizational_domain`, a callable that returns a
      # domain's organizational domain (RFC 9989, found through DNS by the caller), alignment
      # is relaxed: the two organizational domains are equal.
      def qualifying(raw_message:, signatures:, organizational_domain: nil)
        fields = Header.fields(raw_message) or return
        counts = fields.map(&:first).tally
        covered = REQUIRED + CONDITIONAL.select { |name| counts.key?(name) }
        return unless covered.all? { |name| counts[name] == 1 }

        author = author_domain(fields.assoc("from").last) or return
        signatures.find do |signature|
          qualifies?(signature, covered) && aligned?(signature.domain.to_s, author, organizational_domain)
        end
      end

      private

      # It verified the whole body with an acceptable key, and signed every covered header.
      def qualifies?(signature, covered)
        signature.pass? && !signature.body_length_limited? && acceptable_key?(signature) &&
          (covered - signature.signed_headers.map { |name| name.strip.downcase }).empty?
      end

      # The domain of the From field's one mailbox, or nil unless it names exactly one.
      def author_domain(value)
        list = Mail::AddressList.new(value.dup.force_encoding(Encoding::UTF_8))
        return unless list.addresses.one? && list.group_names.empty?

        domain = list.addresses.first.domain.to_s
        domain unless domain.empty?
      rescue Mail::Field::ParseError
        nil
      end

      # RFC 8301 and RFC 8463: RSA of at least 1,024 bits with SHA-256, or Ed25519.
      def acceptable_key?(signature)
        case signature.algorithm
        when "rsa-sha256" then signature.key_type == "rsa" && signature.key_bits.to_i >= 1024
        when "ed25519-sha256" then signature.key_type == "ed25519"
        else false
        end
      end

      def aligned?(signer, author, organizational_domain)
        return false if signer.empty?
        return true if signer.casecmp?(author)
        return false unless organizational_domain

        organization = organizational_domain.call(author).to_s
        !organization.empty? && organization.casecmp?(organizational_domain.call(signer).to_s)
      end
    end
  end
end
