// A throwaway directory for tests.

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

// PREFIX names the directories so a leftover one says where it came from.
const PREFIX = "taskfiles-ci-";

// TempDir is a directory of its own, removed by cleanup.
export interface TempDir {
  dir: string;
  write(path: string, content: string): string;
  cleanup(): void;
}

// tempDir makes an empty directory.
export function tempDir(): TempDir {
  const dir = mkdtempSync(join(tmpdir(), PREFIX));
  return {
    dir,
    write(path, content) {
      const file = join(dir, path);
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, content);
      return file;
    },
    cleanup: () => rmSync(dir, { recursive: true, force: true }),
  };
}
