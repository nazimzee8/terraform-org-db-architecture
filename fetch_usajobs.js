export async function fetchUsajobs({ query, locationName, resultsPerPage = 100, page = 1 }) {
  const EMAIL = process.env.USAJOBS_USER_AGENT_EMAIL;
  const API_KEY = process.env.USAJOBS_API_KEY;

  if (!EMAIL || !API_KEY) {
    throw new Error("Missing USAJOBS_USER_AGENT_EMAIL or USAJOBS_API_KEY env vars");
  }

  const params = new URLSearchParams({
    Keyword: query,
    LocationName: locationName,
    ResultsPerPage: String(resultsPerPage),
    Page: String(page)
  });

  const url = `https://data.usajobs.gov/api/search?${params.toString()}`;

  const res = await fetch(url, {
    headers: {
      Host: "data.usajobs.gov",
      "User-Agent": EMAIL,
      "Authorization-Key": API_KEY
    }
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`USAJOBS error ${res.status}: ${text}`);
  }

  return await res.json();
}

export function extractUsajobsDescription(item) {
  const d = item?.MatchedObjectDescriptor;

  const summary = d?.UserArea?.Details?.JobSummary ?? "";
  const duties = d?.UserArea?.Details?.MajorDuties ?? "";
  const requirements = d?.UserArea?.Details?.KeyRequirements ?? "";
  const qualifications = d?.UserArea?.Details?.Qualifications ?? "";

  return [summary, duties, requirements, qualifications]
    .filter(Boolean)
    .join("\n\n");
}

export function normalizeUsajobsPosting(item) {
  const d = item?.MatchedObjectDescriptor;
  return {
    source: "usajobs",
    source_job_id: item?.MatchedObjectId ?? null,
    source_url: d?.PositionURI ?? null,
    title: d?.PositionTitle ?? null,
    company: d?.OrganizationName ?? null,
    location_raw: d?.PositionLocationDisplay ?? null,
    country: "US",
    date_posted: d?.PublicationStartDate ?? null,
    date_expires: d?.ApplicationCloseDate ?? null
  };
}
