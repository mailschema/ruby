# frozen_string_literal: true

# An implementation record: a Registry declaration or report of a service's support for exact
# contract versions.
module Mailschema
  # Why the value is not an implementation record, or no reasons.
  def self.implementation_errors(value)
    errors = Schemas.errors(Schemas::IMPLEMENTATION, value)
    return errors if errors.any?

    origin = Origin.of(value["service"])
    unless origin && [origin, "#{origin}/"].include?(value["service"])
      errors << "/service: must be an HTTPS origin, not an operation path"
    end
    errors << "/operations: identifiers must be unique" if value["operations"].uniq.size != value["operations"].size
    errors
  end

  # The record in the bytes or text, or InvalidDocument with every reason it is not one.
  def self.parse_implementation(input)
    value = parse(input, CONTRACT_MAX_BYTES)
    errors = implementation_errors(value)
    raise InvalidDocument.new("The value is not an implementation record.", errors) if errors.any?

    value
  end
end
