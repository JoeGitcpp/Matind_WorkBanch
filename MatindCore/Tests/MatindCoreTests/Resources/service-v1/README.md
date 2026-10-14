# service-v1 contract samples

Conformance suite for the service-container contracts. The Rust validator
(`matrix-automation::service_contract`) is the reference; the web client and the
Swift client keep byte-identical copies of this directory and must reach the same
verdict on every file.

- `valid/<contract>--<name>.json` must be accepted by `<contract>`.
- `invalid/<contract>--<name>.json` must be rejected by `<contract>`.
- `<contract>` is one of `service-manifest-v1`, `service-operation-v1`,
  `data-handle-v1`, `capability`, `service-task-v1`, `metering-entry-v1`.
  A `capability` sample is a bare JSON string (or, when invalid, any JSON value).
- Unknown fields are rejected everywhere.

Adding a case: add the file here, then copy the directory to the other two
repositories (`MatrixFactoryFrontend/packages/service-contract/samples`,
`WorkBoardDesktop/MatindCore/Tests/MatindCoreTests/Resources/service-v1`). Each
side's test also checks its copy against `SHA256SUMS`.
