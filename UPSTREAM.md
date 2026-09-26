# Release provenance

Version `0.2.0` derives from [`mailschema/mailschema@b9c918f`](https://github.com/mailschema/mailschema/commit/b9c918f9de43c4948bda21e9b80c5373da102ec2): the gem source, its tests and fixtures, and the bundled files are prepared from that commit by `npm run packages:prepare`.

The bundled files are exact projections of that source commit and do not independently define MAP:

- contribution (`schemas/contribution.schema.json`): `a8a241b4837971a6251bcc135c704283536f4fb825fbbaedaf1598c6e688d564`
- map-0.2 (`schemas/map-0.2.schema.json`): `732d60fcb758d945dc15c57d885c9d1c0c76423a7439096d9755e8ec9830836a`
- map-0.2-context (`contexts/map-0.2.jsonld`): `dfed0189524d7d16d31ed3d8af97e9a0c458200c4c034b413f9d14fa35b60257`
- type-contract-0.2 (`schemas/type-contract-0.2.schema.json`): `e030007cc034662c9d9d448a8a035aff3106cfb96fb60e6aa9f92b99b25df0b9`
- forms-0.1 (`schemas/forms-0.1.schema.json`): `3a976b93a057380e3630ca05e77e221a43a98559fb7fda8066299ec4bf2a8f9e`

The canonical schemas live in the main MailSchema repository. This repository owns the Ruby gem surface and its release history.
