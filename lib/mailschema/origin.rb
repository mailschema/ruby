# frozen_string_literal: true

module Mailschema
  # The RFC 6454 origin of an absolute URL, serialized as the WHATWG URL parser does: its
  # scheme, its lowercased host, and its port unless that is the scheme's default.
  module Origin
    def self.of(url)
      uri = URI.parse(url)
      return if uri.scheme.nil? || uri.host.to_s.empty?

      port = uri.port == uri.default_port ? "" : ":#{uri.port}"
      "#{uri.scheme.downcase}://#{uri.host.downcase}#{port}"
    rescue URI::InvalidURIError
      nil
    end
  end
  private_constant :Origin
end
