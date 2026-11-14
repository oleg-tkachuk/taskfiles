# sealed-secrets — a secret you can commit

Turn a value into a SealedSecret manifest, and fetch the key that lets you do it
without a cluster.

```yaml
includes:
  sealed-secrets: { taskfile: '{{printf .TASKLIB "sealed-secrets"}}', dir: . }
```

## Tasks

| Task | What it does |
|---|---|
| `seal` | Seal one key/value into a SealedSecret manifest |
| `seal:file` | Seal every key in an env file into one SealedSecret manifest |
| `seal:literals` | Seal several key/value pairs into one manifest — `SECRET_LITERALS="k1=v1 k2=v2"` |
| `seal:files` | Seal whole files, each as the value of one key — `SECRET_FILES="tls.key=certs/tls.key"` |
| `seal:merge` | Rotate one key inside an existing manifest, leaving the others |
| `pubkey` | Print the controller's public certificate |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `SEALED_SECRETS_NS` | `sealed-secrets` | controller namespace |
| `KUBESEAL_FLAGS` | — | verbatim extra kubeseal flags |
| `SEALED_SECRETS_CONTROLLER` | `sealed-secrets-controller` | controller name |
| `K8S_CONTEXT` | current | pin a cluster — both kubectl and kubeseal use it, so the value is sealed to that cluster's controller key |

Per call: `SECRET_NAMESPACE`, `SECRET_NAME`, `SECRET_OUTPUT` for every sealing
task; `SECRET_KEY` and `SECRET_VALUE` for `seal` and `seal:merge`;
`SECRET_FILE` for `seal:file`; `SECRET_LITERALS` for `seal:literals`;
`SECRET_FILES` for `seal:files`.

| Var | Default | Meaning |
|---|---|---|
| `SECRET_TYPE` | Opaque | the Secret's type, for every sealing task but `seal:merge`: `kubernetes.io/basic-auth`, `kubernetes.io/tls` |

## Examples

```yaml
includes:
  sealed-secrets:
    taskfile: '{{printf .TASKLIB "sealed-secrets"}}'
    dir: .
    vars: { SEALED_SECRETS_NS: kube-system }
```

```console
$ task sealed-secrets:seal SECRET_NAMESPACE=orders SECRET_NAME=api-keys \
    SECRET_KEY=STRIPE_KEY SECRET_VALUE=sk_test_123 \
    SECRET_OUTPUT=deploy/secrets/orders-api-keys.yaml
✔ ok    · sealed-secrets · orders/api-keys → deploy/secrets/orders-api-keys.yaml

$ task sealed-secrets:seal:file SECRET_NAMESPACE=orders SECRET_NAME=api-env \
    SECRET_FILE=.env.production SECRET_OUTPUT=deploy/secrets/orders-env.yaml

$ task sealed-secrets:seal:literals SECRET_NAMESPACE=orders SECRET_NAME=db-role \
    SECRET_LITERALS="username=orders password=s3cret" SECRET_TYPE=kubernetes.io/basic-auth \
    SECRET_OUTPUT=deploy/secrets/orders-db-role.yaml

$ task sealed-secrets:seal:files SECRET_NAMESPACE=orders SECRET_NAME=signing \
    SECRET_FILES="signing.pem=.secrets/signing.pem" \
    SECRET_OUTPUT=deploy/secrets/orders-signing.yaml

$ task sealed-secrets:pubkey > deploy/secrets/controller.pem
```

## Where the plaintext goes

Nowhere off this machine, and nowhere on its disk that it was not already.
Every sealing task builds the Secret locally with `--dry-run=client` and pipes
it straight into `kubeseal`, which encrypts to a key only the controller
holds. The only file this module writes is the sealed one. The manifest that
lands in `SECRET_OUTPUT` is safe to commit; the cluster decrypts it on apply.

One caveat worth knowing: `seal` takes the value as a variable, so it sits in
this process's argument list for as long as `kubectl` runs — readable by
anything that can see the process table on this machine, and likely in your
shell history. That is a fair trade for a one-off dev credential and a poor one
for anything that matters. `seal:file` and `seal:files` read from disk
instead — kubectl opens the file itself, so only its path is an argument;
prefer them when the value is real.

It does not sit in Task's own output, though: the plaintext is held in a
`secret: true` var, so `task --verbose` and `task --summary` print `*****`
where the command carries it.

The value is passed as a single shell-quoted argument, so a quote or a
semicolon in it is data. Before v2.1.2 it was interpolated between hand-written
quotes, and a value containing `'` closed them: the remainder of the value ran
as commands, and the `--dry-run=client` that keeps the plaintext off the cluster
was cut off with them.

`pubkey` prints a public key. Committing it lets a colleague seal a value for
this cluster without having access to it — it can encrypt and cannot decrypt.

---

## Four shapes, and which to reach for

| The secret is | Use |
| --- | --- |
| one key | `seal` |
| several keys, values with no whitespace | `seal:literals` |
| several keys, each value on one line | `seal:file` with an env file |
| a value of several lines — a PEM key, a certificate chain | `seal:files`, one file per key |

`seal:literals` splits `literals` on whitespace — that is what makes the list a
list. Each pair then becomes its own argv element, so a value carrying a quote,
a semicolon or a `$( )` reaches kubectl as data rather than as shell. A value
that genuinely contains a space has no place in that list; write it to a file
and use `seal:file`.

`seal:file` and `seal:files` are two different things. `SECRET_FILE` is one
env file whose lines are `KEY=value`, each line a key. `SECRET_FILES` is
`key=path` words, and each file is one key's whole value, line breaks
included, which an env file cannot hold. The words are split on whitespace, so
a path holds none; a word with no `key=` is keyed by its file name.

## A type other than Opaque

`SECRET_TYPE` is passed to `kubectl create secret generic --type`, for a
Secret something reads by its type — `kubernetes.io/basic-auth` for a
database role, `kubernetes.io/tls`. Without it the Secret is Opaque, as
before.

`seal:merge` takes none. The type is part of the manifest's structure, which
a merge leaves alone: `kubeseal --merge-into` keeps the type the manifest was
sealed with and ignores the incoming Secret's (checked against kubeseal
0.41.2). To change a manifest's type, seal it again whole.

A sealing task writes beside `output` and moves the result over it only once
kubectl and kubeseal have both succeeded, so a failed run leaves an existing
manifest as it was.

Part of [taskfiles](../README.md).
