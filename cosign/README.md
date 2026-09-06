# cosign — signing and SBOMs

Signs what `release` published and attests what is inside it. Include it
alongside `release` and chain it after — the release publishes, this signs.

```yaml
includes:
  sign: { taskfile: '{{.TASKLIB}}/cosign{{.TASKLIB_REF}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `sign:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `all` | Sign the image and the chart, then attest the image's SBOM |
| `chart` | Sign the published chart at the release version |
| `image` | Sign the published image at the release version |
| `keygen` | One-time — generate the cosign key pair and a no-transparency-log signing config |
| `sbom` | Generate an SBOM for the published image and attest it with cosign |
| `verify` | Verify the signatures on the published image and chart |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `COSIGN_DIR` | `deploy/sigstore` | where the key pair lives |
| `COSIGN_KEY` | `<dir>/cosign.key` | |
| `COSIGN_PUB` | `<dir>/cosign.pub` | |
| `COSIGN_SIGNING_CONFIG` | `<dir>/signing-config.json` | |
| `COSIGN_SIGN` | `1` | `0` makes every task here a no-op |
| `COSIGN_SIGN_FLAGS` | — | extra flags for sign and attest |
| `COSIGN_VERIFY_FLAGS` | `--insecure-ignore-tlog=true` | |
| `SBOM_FORMAT` | `spdx-json` | syft output format |
| `SBOM_INSECURE` | `0` | `1` when the registry's certificate is one syft rejects |

Plus `PROJECT_NAME`, `REGISTRY`, `IMAGE_NAMESPACE` and `CHART_NAME`, read the
same way `release` reads them.

## Examples

```yaml
includes:
  release: { taskfile: '{{.TASKLIB}}/release{{.TASKLIB_REF}}', dir: . }
  sign:    { taskfile: '{{.TASKLIB}}/cosign{{.TASKLIB_REF}}', dir: . }

tasks:
  deploy:
    cmds:
      - task: release:deploy
      - task: sign:all          # image + chart + SBOM attestation
```

```console
$ task sign:keygen              # once, then commit cosign.pub only
✔ billing · cosign · wrote deploy/sigstore/cosign.{key,pub} + signing-config.json
⚠ billing · cosign · commit cosign.pub, keep cosign.key out of the repo

$ task deploy
✔ billing · cosign · signed registry.internal/acme/billing:1.4.0
✔ billing · cosign · signed registry.internal/acme/charts/billing:1.4.0
✔ billing · cosign · SBOM attested to registry.internal/acme/billing:1.4.0

$ task sign:verify
✔ billing · cosign · verified registry.internal/acme/billing:1.4.0
```

Publishing unsigned on purpose, for one run:

```console
$ task deploy COSIGN_SIGN=0
```

## Missing tools are an error, not a skip

An artifact that is quietly unsigned is the whole failure mode this module exists
to prevent. A missing key or a missing syft fails with the command that fixes it;
turning signing off is something you say out loud, with `COSIGN_SIGN=0`.

## No transparency log by default

`keygen` writes a signing config with no Rekor, Fulcio, TSA or OIDC, because a
private registry cannot verify against the public log anyway. Publishing to a
public registry instead? Drop `COSIGN_KEY`, pass keyless flags through
`COSIGN_SIGN_FLAGS`, and take `--insecure-ignore-tlog` back out of
`COSIGN_VERIFY_FLAGS`.

## keygen refuses to overwrite

A regenerated key silently invalidates every signature already published under
the old one. Rotation is deliberate: move the old key aside yourself.

---

Part of [taskfiles](../README.md).
