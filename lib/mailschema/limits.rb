# frozen_string_literal: true

module Mailschema
  # MAP documents within the core limits, with lengths counted in code points as JSON
  # Schema counts them.
  module Limits
    TITLE = 240
    DETAIL = 4000
    POINTER = 1000
    ERROR_DETAIL = 2000
    ERRORS = 100

    module_function

    # The text, or its first limit - 1 code points and an ellipsis.
    def cut(text, limit) = text.length > limit ? "#{text[0, limit - 1]}…" : text

    # An input error within the core problem's limits. A pointer too long to report
    # names its nearest ancestor that fits, with a detail that says so, and a detail
    # too long is cut.
    def input_error(detail, pointer)
      if pointer.length > POINTER
        pointer = Pointer.within(pointer, POINTER)
        detail = "A member within this value does not satisfy the contract."
      end
      { "detail" => cut(detail, ERROR_DETAIL), "pointer" => pointer }
    end

    # A problem's title, detail and input errors within the core limits. An empty or
    # overlong title, an empty detail or an empty error list is the caller's mistake.
    def problem_members(title, detail, errors)
      raise ArgumentError, "a problem title is 1 to #{TITLE} characters" unless title.length.between?(1, TITLE)
      raise ArgumentError, "a problem detail is not empty" if detail.empty?

      [title, cut(detail, DETAIL), errors && bounded_errors(errors)]
    end

    def bounded_errors(errors)
      raise ArgumentError, "errors, when given, name at least one input error" if errors.empty?
      raise ArgumentError, "an input error has a detail" if errors.any? { |error| error.fetch("detail").empty? }

      errors.first(ERRORS).map { |error| input_error(error.fetch("detail"), error.fetch("pointer")) }
    end

    # The problem with as many of its errors, in order, as fit within the document limit.
    def within_document(problem)
      errors = problem["errors"]
      return problem unless errors

      errors = errors.dup
      errors.pop while errors.size > 1 && JSON.generate(problem.merge("errors" => errors)).bytesize > MAX_BYTES
      problem.merge("errors" => errors)
    end
  end
  private_constant :Limits
end
