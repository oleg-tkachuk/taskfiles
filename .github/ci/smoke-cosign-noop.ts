// Verify: cosign no-ops cleanly with no key and no binary.
//
// Usage: node smoke-cosign-noop.ts, in the consumer.
//
// COSIGN_SIGN=0 exercises every task's status guard without cosign or syft
// installed, which a real sign or attest run would need.

import { runMain } from "./lib/main.ts";
import { passed, taskOk } from "./lib/smoke.ts";

async function main(): Promise<void> {
  await taskOk(["cosign:sign", "cosign:verify"], { cwd: process.cwd(), env: { COSIGN_SIGN: "0" } });
  passed("cosign no-ops without a key, syft or the cosign binary");
}

if (import.meta.main) {
  await runMain(main);
}
