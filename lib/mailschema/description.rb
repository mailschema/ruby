# frozen_string_literal: true

# A MAP description: the JSON-LD a message carries beside its readable content.
module Mailschema
  # Whitespace, controls, bidirectional and invisible formatting characters.
  UNSAFE = /\p{White_Space}|\p{Cc}|\p{Cf}/
  private_constant :UNSAFE

  # Why the value is not a MAP 0.3 description, or no reasons. Beyond the core schema: expiry
  # follows issuance, operation identifiers are unique, and no security-sensitive identifier
  # contains whitespace, a control or a formatting character.
  def self.description_errors(value)
    errors = Schemas.errors(Schemas::CORE, value)
    return errors if errors.any?

    if Time.iso8601(value["expiresAt"]) <= Time.iso8601(value["issuedAt"])
      errors << "/expiresAt: must be later than issuedAt"
    end
    ids = value["operations"].map { |operation| operation["id"] }
    errors << "/operations: identifiers must be unique" if ids.uniq.size != ids.size
    identifiers(value).each do |pointer, identifier|
      next unless identifier && UNSAFE.match?(identifier)

      errors << "#{pointer}: must not contain whitespace, controls or formatting characters"
    end
    errors
  end

  # The description in the bytes or text, or InvalidDocument with every reason it is not one.
  def self.parse_description(input)
    value = parse(input, DESCRIPTION_MAX_BYTES)
    errors = description_errors(value)
    raise InvalidDocument.new("The value is not a MAP 0.3 description.", errors) if errors.any?

    value
  end

  # The security-sensitive identifiers of a description, by their JSON Pointers.
  def self.identifiers(value)
    capabilities = value["operations"].each_with_index.map do |operation, index|
      ["/operations/#{index}/capability/url", operation.dig("capability", "url")]
    end
    [
      ["/@id", value["@id"]],
      ["/type/id", value.dig("type", "id")],
      ["/service/id", value.dig("service", "id")],
      ["/service/tenant", value.dig("service", "tenant")],
      ["/recipient", value["recipient"]],
      ["/subject/id", value.dig("subject", "id")],
      ["/terms/id", value.dig("terms", "id")],
      ["/human/url", value.dig("human", "url")],
      *capabilities
    ]
  end
  private_class_method :identifiers
end
