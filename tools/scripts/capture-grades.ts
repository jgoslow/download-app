#!/usr/bin/env bun
/**
 * Report aggregate test-value / accuracy trends across the audio corpus.
 *
 * Grouped by app version (and overall) so a rising mean accuracy / testValue on a
 * fixed corpus is tangible evidence the app's capture pipeline is improving.
 *
 * Usage:
 *   bun run tools/scripts/capture-grades.ts            # corpus manifest
 *   bun run tools/scripts/capture-grades.ts <folder>   # a BasnCaptures archive dir
 */

import { existsSync, readFileSync, readdirSync, statSync } from "fs";
import { join, resolve } from "path";

const REPO = resolve(import.meta.dir, "../..");
const CORPUS_MANIFEST = join(REPO, "BasnTests/Fixtures/AudioCorpus/manifest.json");

type Grade = {
  testValue?: number;
  outcomeAccuracy?: string;
  actionCount?: number;
  routedVia?: string;
  audio?: { noiseScore?: number };
  appVersion?: string;
  keepAsFixture?: boolean;
};

type Record = { name?: string; grade?: Grade; speaker?: Record<string, unknown> };

function loadFromManifest(): Record[] {
  if (!existsSync(CORPUS_MANIFEST)) return [];
  return JSON.parse(readFileSync(CORPUS_MANIFEST, "utf8"));
}

function loadFromArchive(root: string): Record[] {
  const out: Record[] = [];
  for (const day of readdirSync(root)) {
    const dayDir = join(root, day);
    if (!statSync(dayDir).isDirectory()) continue;
    for (const cap of readdirSync(dayDir)) {
      const gradePath = join(dayDir, cap, "grade.json");
      if (existsSync(gradePath)) {
        out.push({ name: cap, grade: JSON.parse(readFileSync(gradePath, "utf8")) });
      }
    }
  }
  return out;
}

const arg = process.argv.slice(2).find((a) => !a.startsWith("--"));
const records = arg ? loadFromArchive(arg) : loadFromManifest();

if (records.length === 0) {
  console.log("No graded captures found. Populate the corpus or pass an archive folder.");
  process.exit(0);
}

function mean(xs: number[]): number {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;
}

function summarize(label: string, recs: Record[]) {
  const grades = recs.map((r) => r.grade).filter(Boolean) as Grade[];
  const testValues = grades.map((g) => g.testValue ?? 0);
  const accuracy: Record<string, number> = {};
  for (const g of grades) {
    const a = g.outcomeAccuracy ?? "ungraded";
    accuracy[a] = (accuracy[a] ?? 0) + 1;
  }
  const noise = grades.map((g) => g.audio?.noiseScore).filter((n): n is number => n != null);
  const correct = (accuracy["correct"] ?? 0);
  const reviewed = grades.filter((g) => g.outcomeAccuracy).length;

  console.log(`\n${label}  (${recs.length} captures)`);
  console.log(`  mean testValue : ${mean(testValues).toFixed(1)}`);
  console.log(`  accuracy       : ${Object.entries(accuracy).map(([k, v]) => `${k}=${v}`).join("  ")}`);
  if (reviewed > 0) console.log(`  correct rate   : ${((correct / reviewed) * 100).toFixed(0)}% of reviewed`);
  console.log(`  mean actions   : ${mean(grades.map((g) => g.actionCount ?? 0)).toFixed(1)}`);
  if (noise.length) console.log(`  noise spread   : ${Math.min(...noise).toFixed(2)}–${Math.max(...noise).toFixed(2)} (mean ${mean(noise).toFixed(2)})`);
}

// Overall + per app version
summarize("ALL", records);

const byVersion = new Map<string, Record[]>();
for (const r of records) {
  const v = r.grade?.appVersion ?? "unknown";
  byVersion.set(v, [...(byVersion.get(v) ?? []), r]);
}
if (byVersion.size > 1) {
  console.log("\n── by app version ──");
  for (const v of [...byVersion.keys()].sort()) {
    summarize(`v${v}`, byVersion.get(v)!);
  }
}

// Diversity-matrix coverage (corpus only)
const speakers = records.map((r) => r.speaker).filter(Boolean) as Record<string, unknown>[];
if (speakers.length) {
  const axis = (key: string) => new Set(speakers.map((s) => s[key]).filter(Boolean));
  console.log("\n── diversity coverage ──");
  for (const key of ["accent", "environment", "mic"]) {
    console.log(`  ${key.padEnd(12)}: ${[...axis(key)].join(", ") || "(none)"}`);
  }
}
