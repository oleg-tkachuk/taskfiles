# sealed-secrets — a secret you can commit

Turn a value into a SealedSecret manifest, and fetch the key that lets you do it
without a cluster.

```yaml
includes:
  sealed-secrets: { taskfile: '{{.TASKLIB}}sealed-secrets{{.TASKLIB_REF}}', dir: . }
```

## Tasks

| Task | What it does |
|---|---|
| `seal` | Seal one key/value into a SealedSecret manifest |
| `seal:file` | Seal every key in an env file into one SealedSecret manifest |
| `pubkey` | Print the controller's public certificate |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `SEALED_SECRETS_NS` | `sealed-secrets` | controller namespace |
| `SEALED_SECRETS_CONTROLLER` | `sealed-secrets-controller` | controller name |
| `K8S_CONTEXT` | current | pin a cluster |

Per call: `namespace`, `name`, `output` for both sealing tasks; `key` and
`value` for `seal`; `file` for `seal:file`.

## Example

```console
$ task sealed-secrets:seal namespace=billing name=api-keys \
    key=STRIPE_KEY value=sk_test_123 \
    output=deploy/secrets/billing-api-keys.yaml
✔ sealed-secrets · billing/api-keys → deploy/secrets/billing-api-keys.yaml

$ task sealed-secrets:seal:file namespace=billing name=api-env \
    file=.env.production output=deploy/secrets/billing-env.yaml

$ task sealed-secrets:pubkey > deploy/secrets/controller.pem
```

## Where the plaintext goes

Nowhere off this machine. Both tasks build the Secret locally with
`--dry-run=client` and pipe it straight into `kubeseal`, which encrypts to a key
only the controller holds. The manifest that lands in `output` is safe to
commit; the cluster decrypts it on apply.

One caveat worth knowing: `seal` takes the value as a variable, so it sits in
this process's argument list for as long as `kubectl` runs — readable by
anything that can see the process table on this machine, and likely in your
shell history. That is a fair trade for a one-off dev credential and a poor one
for anything that matters. `seal:file` reads from disk instead; prefer it when
the value is real.

`pubkey` prints a public key. Committing it lets a colleague seal a value for
this cluster without having access to it — it can encrypt and cannot decrypt.

---

Part of [taskfiles](../README.md).
