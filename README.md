# mailschema for Ruby

Mail Action Protocol 0.2 tooling for Ruby. The gem parses, canonicalizes, digests and validates MAP documents, verifies the type contracts an implementation vendors, and builds results and problems.

It does not establish endpoint trust, verify email authentication, grant authority or send email. Possession mode needs DKIM and DMARC checks on the raw message, which this gem leaves to the client.

```sh
gem install mailschema
```

Ruby 3.3 or later.

## A service

Vendor the exact contract and request schema your service implements, and pin the contract by the digest you reviewed. The gem refuses any other contract.

```ruby
require "mailschema"

CONTRACT = Mailschema::Contract.new(
  JSON.parse(File.read("config/mailschema/content-review-0.3.json")),
  JSON.parse(File.read("config/mailschema/content-review-0.3.schema.json")),
  digest: "sha-256:…"
)
```

Before sending a description, check it against every rule of the core and the contract, and store its digest or keep it rebuildable from the interaction:

```ruby
CONTRACT.description_errors(description) # => []
Mailschema.digest(description)           # => "sha-256:…"
```

When a request arrives, check it in this order. No step applies an effect for a problem, and a refusal before the description is resolved and its digest matched leaves the request identifier unclaimed:

```ruby
# Answer 415 unless Mailschema.json_request?(content_type). Under possession authority,
# answer an unknown capability with a plain 404 and a lapsed one with a plain 410
# before reading the body; under credential authority, authenticate the principal.
request = Mailschema.parse(body)   # raises Mailschema::InvalidDocument
Mailschema.request_errors(request) # any errors: invalid-request

# Resolve the description you issued for request["interactionId"]. Refuse an unknown
# interaction, or a request whose descriptionDigest is not Mailschema.digest(description).

# Request identifiers are claimed within your tenant: the account, or the capability.
# If request["requestId"] is already claimed there, refuse another principal, and a
# principal whose permission has been revoked, with an uncorrelated refused problem
# (Mailschema.problem without request_id): the refusal says nothing about the request.
# Answer any change to the request, compared by Mailschema.digest, with
# idempotency-conflict. Otherwise settle the recorded result with Mailschema.settle and
# return it, or expired-interaction once Mailschema.retain_until has passed. Nothing is
# applied again.

problem = CONTRACT.request_problem(description, request, now: Time.now)
# problem.code is unsupported-type, unsupported-operation or expired-interaction,
# with the title and detail Mailschema.problem takes. Then your own state:
# already-decided, or stale-target.

CONTRACT.input_errors(description, request)
# => [{ "detail" => "...", "pointer" => "/feedback" }], a claimed invalid-request
```

Then apply the approval lifecycle or the effect, and record the result:

```ruby
Mailschema.result(
  request,
  state: "accepted",
  target: description["target"],
  result_url: Mailschema.result_url(description, request["requestId"]),
  recorded_at: Time.now,
  output: { "feedbackRecorded" => true, "feedbackId" => "fb-1" }
)
```

## API

| Call                                                                                                 | Does                                                                                                                                                                                                                                                                                                                                                                                                 |
| ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Mailschema.parse(json)`                                                                             | Parses a MAP document as I-JSON within the core limits, integral numbers as Integers, or raises `Mailschema::InvalidDocument`                                                                                                                                                                                                                                                                        |
| `Mailschema.canonicalize(value)`, `Mailschema.digest(value)`                                         | RFC 8785 canonical JSON, and `sha-256:` over it                                                                                                                                                                                                                                                                                                                                                      |
| `Mailschema.map_errors(document)`                                                                    | Checks a description, request, result or problem against the core schema                                                                                                                                                                                                                                                                                                                             |
| `Mailschema.description_errors`, `Mailschema.request_errors`                                         | Check a description or a request against its core definition only                                                                                                                                                                                                                                                                                                                                    |
| `Mailschema.result_errors`, `Mailschema.problem_errors`                                              | Check a result or a problem against its core definition only                                                                                                                                                                                                                                                                                                                                         |
| `Mailschema::Contract.new(contract, request_schema, digest:, dependencies: {})`                      | Checks the contract's format and profile, refuses any contract but the one pinned by `digest`, checks its pinned dependencies and request schema digest, validates every schema against JSON Schema 2020-12 and compiles every validator once, or raises `Mailschema::InvalidContract`; `dependencies:` supplies, by URL, any pinned schema the gem does not bundle                                  |
| `contract.description_errors(description)`                                                           | Checks a description against every rule of the core and the contract                                                                                                                                                                                                                                                                                                                                 |
| `contract.request_problem(description, request, now:)`                                               | The exact type, an offered operation the authority permits, and expiry, as a `Contract::Problem` or nil                                                                                                                                                                                                                                                                                              |
| `contract.input_errors(description, request)`                                                        | Checks an operation's input and field bindings, with JSON Pointers into `input`                                                                                                                                                                                                                                                                                                                      |
| `contract.result_errors(result)`                                                                     | Checks a result against the core, the declared output schema and the declared reason                                                                                                                                                                                                                                                                                                                 |
| `contract.type_reference`, `contract.operation(id)`, `contract.decision?(id)`                        | The type reference descriptions and requests name, one of its operations, and whether completing it decides the interaction                                                                                                                                                                                                                                                                          |
| `contract.id`, `contract.version`, `contract.digest`, `contract.document`, `contract.request_schema` | The contract's identity, and frozen copies of the documents it verified                                                                                                                                                                                                                                                                                                                              |
| `Mailschema.result`, `Mailschema.transition`, `Mailschema.problem`                                   | Build results, state transitions and problems with their correlation members, or raise `ArgumentError` rather than return a document the core refuses. A problem stays within the core limits: a title of at most 240 characters, a detail cut at 4000, and as many of the first 100 input errors, each bounded, as fit in 64 KiB as `JSON.generate` writes them, so send documents written that way |
| `Mailschema.result_url`, `Mailschema.result_status`, `Mailschema.request_id?`                        | The result resource of a request, a result's HTTP status, and whether a value is a request identifier, the only thing a result URL names                                                                                                                                                                                                                                                             |
| `Mailschema.json_request?(content_type)`                                                             | Whether a `Content-Type` admits a request rather than a 415                                                                                                                                                                                                                                                                                                                                          |
| `Mailschema::DESCRIPTION_MEDIA_TYPE`, `Mailschema.description_part?(media_type, profile_parameter)`  | The `Content-Type` of the part that carries a description, and whether a designated part is labelled with this profile; a client processes the one such part outside any attached message and ignores every other structured part                                                                                                                                                                    |
| `Mailschema.retain_until`, `Mailschema.settle`, `Mailschema.reached?`                                | Result retention, the expiry of an undecided approval, and whether a deadline has passed                                                                                                                                                                                                                                                                                                             |
| `Mailschema.capability(description)`, `Mailschema.written_path(url)`                                 | The possession capability: the last segment of the execution URL's path as written                                                                                                                                                                                                                                                                                                                   |
| `Mailschema.artifact(url)`, `Mailschema.document(url)`                                               | The bundled core artifacts, as exact bytes or as a fresh parsed copy                                                                                                                                                                                                                                                                                                                                 |

Type rules a contract cannot express, such as a meeting slot being one of the slots offered, belong to each type's implementation.

## Bundled artifacts

The gem carries the MAP 0.2 core schema, its JSON-LD context, the type contract format and the form fields block, and the Registry contribution schema that every MailSchema package binds. Each is byte-identical to the file [mailschema.org](https://mailschema.org) publishes. The gem does not validate contributions; the JavaScript and Python packages do. Type contracts are not bundled: an implementation vendors the contracts it supports, and `Mailschema::Contract` verifies them by digest.

JSON Schema validation uses `json_schemer` with ECMA-262 regular expressions. Lexical forms such as date-times and addresses are core schema patterns, so `format` is never asserted. References resolve only against pinned schemas, never over the network.

## Links

- [Specification](https://mailschema.org/specification/profile)
- [Source](https://github.com/mailschema/ruby)

MIT License.
