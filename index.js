import crypto from "crypto";
import { Storage } from "@google-cloud/storage";
import { scanJobDescription, cleanText } from "./keywordScan.js";

import {
  fetchUsajobs,
  extractUsajobsDescription,
  normalizeUsajobsPosting
} from "./sources/usajobs.js";

import {
  fetchAdzuna,
  extractAdzunaDescription,
  normalizeAdzunaPosting
} from "./sources/adzuna.js";

const storage = new Storage();
const BUCKET = process.env.INGESTION_BUCKET;

function jobUid(source, sourceJobId) {
  return crypto
    .createHash("sha256")
    .update(`${source}:${sourceJobId}`)
    .digest("hex");
}

async function writeJsonToGCS(path, payload) {
  const file = storage.bucket(BUCKET).file(path);
  await file.save(JSON.stringify(payload, null, 2), {
    contentType: "application/json"
  });
}

async function run() {
  if (!BUCKET) throw new Error("Missing env var INGESTION_BUCKET");

  const ingestTs = new Date().toISOString();

  // ---------------------------
  // 1) USAJOBS fetch + scan
  // ---------------------------
  const usajobsJson = await fetchUsajobs({
    query: process.env.USAJOBS_QUERY ?? "software engineer",
    locationName: process.env.USAJOBS_LOCATION ?? "United States",
    resultsPerPage: 100,
    page: 1
  });

  const usajobsItems = usajobsJson?.SearchResult?.SearchResultItems ?? [];
  const usajobsEnriched = usajobsItems.map((item) => {
    const normalized = normalizeUsajobsPosting(item);
    const descriptionRaw = extractUsajobsDescription(item);
    const signals = scanJobDescription(descriptionRaw);

    return {
      ingest_ts: ingestTs,
      job_uid: jobUid(normalized.source, normalized.source_job_id),
      ...normalized,
      description_clean: cleanText(descriptionRaw),
      keyword_signals: signals
    };
  });

  await writeJsonToGCS(
    `enriched/usajobs/ingest_ts=${ingestTs.slice(0, 13)}/batch.json`,
    { ingest_ts: ingestTs, source: "usajobs", results: usajobsEnriched }
  );

  // ---------------------------
  // 2) Adzuna fetch + scan
  // ---------------------------
  const adzunaJson = await fetchAdzuna({
    country: process.env.ADZUNA_COUNTRY ?? "us",
    page: 1,
    what: process.env.ADZUNA_WHAT ?? "software engineer",
    where: process.env.ADZUNA_WHERE ?? "United States",
    resultsPerPage: 50
  });

  const adzunaJobs = adzunaJson?.results ?? [];
  const adzunaEnriched = adzunaJobs.map((job) => {
    const normalized = normalizeAdzunaPosting(job);
    const descriptionRaw = extractAdzunaDescription(job);
    const signals = scanJobDescription(descriptionRaw);

    return {
      ingest_ts: ingestTs,
      job_uid: jobUid(normalized.source, normalized.source_job_id),
      ...normalized,
      description_clean: cleanText(descriptionRaw),
      keyword_signals: signals
    };
  });

  await writeJsonToGCS(
    `enriched/adzuna/ingest_ts=${ingestTs.slice(0, 13)}/batch.json`,
    { ingest_ts: ingestTs, source: "adzuna", results: adzunaEnriched }
  );

  console.log("✅ Success");
  console.log(`USAJOBS enriched jobs: ${usajobsEnriched.length}`);
  console.log(`Adzuna enriched jobs:  ${adzunaEnriched.length}`);
}

run().catch((err) => {
  console.error("❌ Job failed:", err);
  process.exit(1);
});
