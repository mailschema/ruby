# frozen_string_literal: true

require "minitest/autorun"
require "mailschema"

# Package preparation copies these fixtures from the MailSchema repository, so the gem is
# tested against the exact documents and vectors the specification publishes.
module Fixtures
  ROOT = File.expand_path("fixtures", __dir__)
  ARTIFACTS = File.expand_path("../artifacts", __dir__)

  module_function

  def read(path) = File.binread(File.join(ROOT, path))

  def json(path) = JSON.parse(read(path))

  def example(slug) = json("examples/#{slug}.json")

  def contract_path(slug) = Dir[File.join(ROOT, "contracts", "#{slug}-*.json")].first

  # A fresh copy of a published contract's document, to change.
  def contract_document(slug) = JSON.parse(File.binread(contract_path(slug)))

  # Each published contract by the slug of its example.
  def contracts
    @contracts ||= Dir[File.join(ROOT, "contracts", "*.json")].to_h do |path|
      [File.basename(path).sub(/-[0-9.]+\.json\z/, ""), Mailschema::Contract.parse(File.binread(path))]
    end
  end
end

def deep_copy(value) = Marshal.load(Marshal.dump(value))
