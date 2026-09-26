# frozen_string_literal: true

module Mailschema
  # The form fields block of forms 0.1: the rules JSON Schema cannot state, and the
  # schema the values of a block satisfy.
  module Forms
    # The core definitions that give a text field's `format` its lexical form.
    FORMATS = { "email" => "address", "uri" => "identifier", "date" => "date", "date-time" => "dateTime" }.freeze

    module_function

    # Every required field exists, choices are distinct, and defaults are among the
    # choices.
    def problems(fields)
      properties = fields.fetch("properties", {})
      undefined = fields.fetch("required", []).reject { |name| properties.key?(name) }
      problems = undefined.map { |name| "required field #{name} is not defined" }
      properties.each do |name, field|
        choices = (field["oneOf"] || field.dig("items", "anyOf") || []).map { |choice| choice["const"] }
        problems << "field #{name} repeats a choice" unless choices.uniq.size == choices.size
        defaults = field.key?("default") ? Array(field["default"]) : []
        if choices.any? && defaults.any? { |value| !choices.include?(value) }
          problems << "field #{name} defaults to a value it does not offer"
        end
      end
      problems
    end

    # The schema the values of a fields block satisfy: only its fields, each with a
    # text field's `format` read as the core lexical form of that name.
    def values_schema(fields)
      properties = fields.fetch("properties", {}).transform_values do |field|
        next field unless field.key?("format")

        field.except("format").merge("$ref" => "#{CORE_SCHEMA}#/$defs/#{FORMATS.fetch(field["format"])}")
      end
      fields.merge("properties" => properties, "additionalProperties" => false)
    end
  end
  private_constant :Forms
end
