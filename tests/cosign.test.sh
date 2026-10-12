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

rm -f "$CONSUMER/deploy/sigstore/signing-config.json"
reset_calls
run_task cosign:image
expect_status fail "image: a missing signing config is refused"
expect_output "signing-config.json not found" "image: names the missing signing config"
refute_call "cosign sign" "image: cosign is not called without its signing config"

finish
