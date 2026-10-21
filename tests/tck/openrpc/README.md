# OpenRPC qualification inputs

`open-rpc-meta-schema.json` is the unmodified official release asset from
[open-rpc/meta-schema 1.14.9](https://github.com/open-rpc/meta-schema/releases/download/1.14.9/open-rpc-meta-schema.json).
It permits OpenRPC document version 1.3.2. SHA-256:
`e5f534fb0dd9dd3598d26414e278a8c96e923ee7b54bef7009c499f4c71d0f82`.
The upstream project is Apache-2.0 licensed.

The release references `https://meta.json-schema.tools`. The unmodified
`json-schema-meta.json` was retrieved from that official companion endpoint on
2026-10-21 and is frozen here, with SHA-256:
`c60549433ca5726bb3ff8959bbcdb3013b6b17fd8c3f99ae0c9604088c714738`.
It describes JSON Schema draft-07 keywords and boolean schemas.
`json-schema-meta-alias.json` resolves its slashless reference to its canonical
identifier, without modifying either upstream file or fetching remote references.

`mise run test:openrpc` uses pinned Ajv CLI 5.0.0 and ajv-formats 2.1.1 as an
independent validator. MoonBit runs the qualification script. Npm installs only
test tools under `.dev/out`; conversion and reference resolution perform no
network access. The script validates actual built-CLI and isolated-library
outputs, rejects deliberately invalid documents/references, and compares
representative exported value schemas with the runtime RPC validator.
