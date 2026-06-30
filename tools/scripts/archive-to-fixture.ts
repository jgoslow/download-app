#!/usr/bin/env bun
/**
 * Promote a debug capture archive folder into a test fixture.
 *
 * Archive folders are produced by the app's "Archive captures" debug toggle at:
 *   ~/Library/Containers/com.lyra.basn.debug/Data/Documents/BasnCaptures/<date>/<time-id>/
 * Each contains audio.wav, scenario.json, metadata.json, grade.json (+ analysis/plan).
 *
 * Usage:
 *   bun run tools/scripts/archive-to-fixture.ts <archive-folder> --scenario
 *   bun run tools/scripts/archive-to-fixture.ts <archive-folder> --corpus
 *
 *   --scenario  Copy scenario.json into BasnCore parse-layer fixtures.
 *   --corpus    Copy audio.wav + append the entry (with grade) to the audio
 *               corpus manifest for the end-to-end audio tests.
 */

import { existsSync, readFileSync, writeFileSync, copyFileSync } from "fs";
import { basename, join, resolve } from "path";

const REPO = resolve(import.meta.dir, "../..");
const SCENARIO_DIR = join(REPO, "BasnCore/Tests/BasnCoreTests/Fixtures/Scenarios");
const CORPUS_DIR = join(REPO, "BasnTests/Fixtures/AudioCorpus");

const args = process.argv.slice(2);
const folder = args.find((a) => !a.startsWith("--"));
const mode = args.includes("--corpus") ? "corpus" : args.includes("--scenario") ? "scenario" : null;

if (!folder || !mode) {
  console.error("Usage: archive-to-fixture.ts <archive-folder> --scenario|--corpus");
  process.exit(1);
}
if (!existsSync(folder)) {
  console.error(`Archive folder not found: ${folder}`);
  process.exit(1);
}

const scenarioPath = join(folder, "scenario.json");
if (!existsSync(scenarioPath)) {
  console.error(`No scenario.json in ${folder} (was this capture archived?)`);
  process.exit(1);
}
const scenario = JSON.parse(readFileSync(scenarioPath, "utf8"));

function slugify(name: string): string {
  return (name || "capture")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48) || "capture";
}

if (mode === "scenario") {
  const slug = slugify(scenario.name);
  const dest = join(SCENARIO_DIR, `${slug}.json`);
  if (existsSync(dest)) {
    console.error(`Fixture already exists: ${dest} — rename scenario.name or remove it first.`);
    process.exit(1);
  }
  // Parse-layer fixtures don't need the audio fields.
  delete scenario.audioFile;
  delete scenario.werThreshold;
  delete scenario.speaker;
  writeFileSync(dest, JSON.stringify(scenario, null, 2) + "\n");
  console.log(`✓ Wrote scenario fixture: ${dest}`);
  console.log("  Remember to add a @Test in CaptureScenarioTests.swift.");
  process.exit(0);
}

// mode === "corpus"
const grade = existsSync(join(folder, "grade.json"))
  ? JSON.parse(readFileSync(join(folder, "grade.json"), "utf8"))
  : null;

if (grade && grade.keepAsFixture === false) {
  console.error("Refusing to promote: grade.json has keepAsFixture=false. Re-grade it in the Review sheet.");
  process.exit(1);
}
if (grade && grade.keepAsFixture == null) {
  console.warn("⚠ Capture is not yet marked keepAsFixture — promoting anyway. Grade it for best corpus quality.");
}

const audioSrc = join(folder, "audio.wav");
if (!existsSync(audioSrc)) {
  console.error(`No audio.wav in ${folder} — text-input captures can't join the audio corpus.`);
  process.exit(1);
}

const slug = slugify(scenario.name);
const audioFile = `${slug}.wav`;
copyFileSync(audioSrc, join(CORPUS_DIR, audioFile));

const manifestPath = join(CORPUS_DIR, "manifest.json");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

const entry = {
  ...scenario,
  audioFile,
  expectedTranscript: scenario.expectedTranscript ?? scenario.rawText,
  werThreshold: scenario.werThreshold ?? 0.15,
  grade: grade ?? undefined,
};

manifest.push(entry);
writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n");
console.log(`✓ Copied audio → ${join(CORPUS_DIR, audioFile)}`);
console.log(`✓ Appended entry "${scenario.name}" to manifest.json (${manifest.length} total)`);
if (!entry.speaker) {
  console.log("  ⚠ No speaker metadata — edit the manifest entry to record accent/environment/mic for the diversity matrix.");
}
