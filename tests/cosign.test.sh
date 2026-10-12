#!/usr/bin/env bash
# cosign: the SBOM attestation is typed after the format syft wrote, and a
# missing signing config is refused before cosign is called.
source "$(dirname "$0")/lib.sh"

shim syft 'exit 0'
shim cosign 'exit 0'

# cosign acts on what release published, so the consumer includes both.
cat > "$CONSUMER/Taskfile.yaml" <<YAML
version: "3"
silent: true
vars:
  PROJECT_NAME: app
  APP_VERSION: 1.2.3
includes:
  release: { taskfile: '$LIB_ROOT/release', dir: . }
  cosign: { taskfile: '$LIB_ROOT/cosign', dir: . }
YAML
mkdir -p "$CONSUMER/deploy/sigstore"
touch "$CONSUMER/deploy/sigstore/cosign.key" "$CONSUMER/deploy/sigstore/signing-config.json"

run_task cosign:sbom
expect_status ok "sbom: attests with the default format"
expect_call "-o spdx-json=" "sbom: syft writes spdx-json by default"
expect_call "--type spdxjson" "sbom: an spdx-json SBOM is attested as spdxjson"

reset_calls
run_task cosign:sbom SBOM_FORMAT=cyclonedx-json
expect_status ok "sbom: attests a CycloneDX SBOM"
expect_call "--type cyclonedx" "sbom: a cyclonedx-json SBOM is attested as cyclonedx"
refute_call "--type spdxjson" "sbom: a cyclonedx-json SBOM is not labelled SPDX"

reset_calls
run_task cosign:sbom SBOM_FORMAT=spdx-json@2.2
expect_status ok "sbom: a versioned format is accepted"
expect_call "--type spdxjson" "sbom: a versioned spdx-json is attested as spdxjson"

reset_calls
run_task cosign:sbom SBOM_FORMAT=syft-table
expect_status fail "sbom: a format cosign has no predicate type for is refused"
refute_call "cosign attest" "sbom: nothing is attested under the wrong type"

# A value is data wherever it reaches a shell: none of these runs, and each
# reaches cosign or syft whole. ${IFS} keeps the ref one word for verify's split.
pwned="$WORK/pwned"
evil="\$(touch\${IFS}$pwned)"
key="deploy/sigstore/k$evil.key"
mkdir -p "$(dirname "$CONSUMER/$key")"
touch "$CONSUMER/$key"

# Set in the consumer's own vars: a CLI var does not reach the release
# module's derived refs.
cp "$CONSUMER/Taskfile.yaml" "$WORK/Taskfile.plain"
sed -i.bak "s|^  PROJECT_NAME: app\$|  PROJECT_NAME: 'app$evil'|" "$CONSUMER/Taskfile.yaml"
reset_calls
run_task cosign:sign "COSIGN_KEY=$key"
cp "$WORK/Taskfile.plain" "$CONSUMER/Taskfile.yaml"
expect_status ok "values: sign runs with a \$( ) in the name and key"
if [ -e "$pwned" ]; then fail "values: a \$( ) in the name or key ran during sign"; else pass "values: a \$( ) in the name or key does not run during sign"; fi
expect_call "cosign sign --yes --signing-config deploy/sigstore/signing-config.json --key $key localhost:5000/app$evil:1.2.3" "values: the image is signed with the key and ref as data"
expect_call "cosign sign --yes --signing-config deploy/sigstore/signing-config.json --key $key localhost:5000/charts/app$evil:1.2.3" "values: the chart is signed with the key and ref as data"
expect_call "syft localhost:5000/app$evil:1.2.3 -q -o spdx-json=" "values: syft reads the ref as data"
expect_call "--type spdxjson localhost:5000/app$evil:1.2.3" "values: the SBOM is attested to the ref as data"
expect_output "app$evil · cosign · signed localhost:5000/app$evil:1.2.3" "values: the log line prints the name and ref as data"

touch "$CONSUMER/deploy/sigstore/cosign.pub"
sed -i.bak "s|^  PROJECT_NAME: app\$|&\\
  IMAGE_NAMESPACE: 'ns$evil'|" "$CONSUMER/Taskfile.yaml"
reset_calls
run_task cosign:verify
cp "$WORK/Taskfile.plain" "$CONSUMER/Taskfile.yaml"
expect_status ok "values: verify runs with a \$( ) in the namespace"
if [ -e "$pwned" ]; then fail "values: a \$( ) in the namespace ran during verify"; else pass "values: a \$( ) in the namespace does not run during verify"; fi
expect_call "cosign verify --insecure-ignore-tlog=true --key deploy/sigstore/cosign.pub localhost:5000/ns$evil/app:1.2.3" "values: the image ref reaches verify as data"
expect_call "cosign verify --insecure-ignore-tlog=true --key deploy/sigstore/cosign.pub localhost:5000/ns$evil/charts/app:1.2.3" "values: the chart ref reaches verify as data"

reset_calls
run_task cosign:keygen "COSIGN_DIR=keys$evil"
expect_status ok "values: keygen runs with a \$( ) in the key directory"
if [ -e "$pwned" ]; then fail "values: a \$( ) in the key directory ran during keygen"; else pass "values: a \$( ) in the key directory does not run during keygen"; fi
if [ -d "$CONSUMER/keys$evil" ]; then pass "values: the key directory is created under its literal name"; else fail "values: no directory named keys$evil"; fi
expect_call "cosign generate-key-pair" "values: keygen generates the key pair"
expect_call "--no-default-oidc --out keys$evil/signing-config.json" "values: the signing config path reaches cosign as data"

rm -f "$CONSUMER/deploy/sigstore/signing-config.json"
reset_calls
run_task cosign:image
expect_status fail "image: a missing signing config is refused"
expect_output "signing-config.json not found" "image: names the missing signing config"
refute_call "cosign sign" "image: cosign is not called without its signing config"

finish
