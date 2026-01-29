export async function fetchAdzuna({ country = "us", page = 1, what, where, resultsPerPage = 50 }) {
  const APP_ID = process.env.ADZUNA_APP_ID;
  const APP_KEY = process.env.ADZUNA_APP_KEY;

  if (!APP_ID || !APP_KEY) {
    throw new Error("Missing ADZUNA_APP_ID or ADZUNA_APP_KEY env vars");
  }

  const params = new URLSearchParams({
    app_id: APP_ID,
    app_key: APP_KEY,
    results_per_page: String(resultsPerPage),
    what: what ?? "",
    where: where ?? "",
    content_type: "application/json"
  });

  const url = `https://api.adzuna.com/v1/api/jobs/${country}/search/${page}?${params.toString()}`;

  const res = await fetch(url);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Adzuna error ${res.status}: ${text}`);
  }

  return await res.json();
}

export function normalizeAdzunaPosting(job) {
  return {
    source: "adzuna",
    source_job_id: job?.id ?? null,
    source_url: job?.redirect_url ?? null,
    title: job?.title ?? null,
    company: job?.company?.display_name ?? null,
    location_raw: job?.location?.display_name ?? null,
    country: (job?.country ?? "US").toUpperCase(),
    date_posted: job?.created ?? null,
    date_expires: null
  };
}

export function extractAdzunaDescription(job) {
  return job?.description ?? "";
}
