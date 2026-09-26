# frozen_string_literal: true

require "minitest/autorun"
require "mailschema"

# Package preparation copies these fixtures from the MailSchema repository, so the
# gem is tested against the exact documents the specification publishes.
module Fixtures
  ROOT = File.expand_path("fixtures", __dir__)

  module_function

  def read(path) = File.binread(File.join(ROOT, path))
  def json(path) = JSON.parse(read(path))

  def types
    Dir.children(File.join(ROOT, "map-0.2")).select { |name| File.directory?(File.join(ROOT, "map-0.2", name)) }.sort
  end

  # The contract and request schema of a type, as an implementation vendors them.
  def contract_files(slug)
    document = JSON.parse(File.binread(Dir[File.join(ROOT, "contracts", "#{slug}-*.json")].max))
    [document, json("schemas/#{document.dig("requestSchema", "url").split("/").last}")]
  end

  # Each type's contract, pinned by the digest its published description names.
  def contract(slug)
    @contracts ||= {}
    @contracts[slug] ||= Mailschema::Contract.new(*contract_files(slug), digest: pinned(slug))
  end

  def pinned(slug) = description(slug).dig("type", "contractDigest")

  def description(slug) = json("map-0.2/#{slug}/description.json")
end

def deep_copy(value) = JSON.parse(JSON.generate(value))
