# mailschema for Ruby

[Mail Action Protocol](https://mailschema.org) (MAP) 0.3 processing in Ruby. The gem reads MAP JSON strictly from its original bytes, computes RFC 8785 digests, and checks descriptions, type contracts and implementation records with the same rules and messages as the reference implementation. It also finds the one MAP part of a received email, builds that part for a message you send, and decides whether a verified DKIM signature qualifies a message for MAP actions.

It does not verify DKIM, query DNS, fetch anything an email names, grant authority or send email. Those belong to your verifier, your trusted service binding and your host policy.

```sh
gem install mailschema -v 0.3.0
```

Ruby 3.3 or later. The gem depends on `json_schemer` and `mail`.

## Example

Parse a description, load the exact contract you resolved from your catalogue, and check the description against it:

```ruby
require "mailschema"

description = Mailschema.parse_description(json)
contract = Mailschema::Contract.parse(File.binread("publication-approval-0.1.json"))
contract.digest                          # => "sha-256:de91a49d..."
contract.description_errors(description) # => []
```

A document that fails raises `Mailschema::InvalidDocument`, whose `errors` lists every reason as a JSON Pointer and a message, such as `"/expiresAt: must be later than issuedAt"`.

From a received email, read the one MAP part:

```ruby
result = Mailschema::Message.extract(Mail.new(raw_message))
result.status      # => :valid, :invalid or :none
result.description # the parsed description when :valid
```

## API

All under `Mailschema`:

- `PROFILE`, `CONTEXT`, `DESCRIPTION_MEDIA_TYPE`, `DESCRIPTION_MAX_BYTES`, `CONTRACT_MAX_BYTES`, `MAX_DEPTH`, `EFFECTS`, `FORMATS` and `CAPABILITY_KINDS`.
- `parse(input, max_bytes)`: MAP JSON from text or bytes. It refuses invalid UTF-8, a byte order mark, duplicate member names (also after unescaping), lone surrogates, U+0000 and noncharacters, nesting deeper than 32, and numbers that are not finite tokens of at most 64 characters within the I-JSON range. It returns plain Hash, Array, String, Integer, Float, true, false and nil values; a number with no fractional part is an Integer.
- `canonicalize(value)` and `digest(value)`: the RFC 8785 form, and `sha-256:` with its hex SHA-256.
- `description_errors(value)` and `parse_description(input)`.
- `contract_errors(value)`, `Contract.new(value)` and `Contract.parse(input)`. A contract has `document` (frozen), `digest`, `id`, `version`, `operation(id)`, `details_errors(details)`, `input_errors(operation_id, input = nil)` and `description_errors(description)`.
- `implementation_errors(value)` and `parse_implementation(input)`.
- `Message.extract(mail)`: a `Message::Result` with `status` `:none`, `:invalid` (with a `reason`) or `:valid` (with the `description`). Pass a `Mail::Message` read from the received bytes; it never raises for untrusted input.
- `Message.part(description)`: the `Mail::Part` that carries a description, to place in a `multipart/related` entity after the readable content.
- `Authentication::Signature` and `Authentication.qualifying(raw_message:, signatures:, organizational_domain: nil)`: the first signature your DKIM verifier reported that qualifies the raw message, or nil. Alignment is strict unless you pass a callable that returns a domain's organizational domain.

Every `*_errors` method returns an array of strings, empty when the value is valid. Schemas are validated with `json_schemer` (JSON Schema 2020-12, ECMA-262 regular expressions) against the profile artifacts the gem bundles.

## Links

- Specification: https://mailschema.org
- Source and issues: https://github.com/mailschema/ruby
