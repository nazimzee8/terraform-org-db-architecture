const AI_KEYWORDS = [
  "llm",
  "large language model",
  "generative ai",
  "genai",
  "automation",
  "automated",
  "machine learning",
  "artificial intelligence",
  "copilot",
  "agentic",
  "ai-assisted",
  "rpa"
];

const OFFSHORING_KEYWORDS = [
  "offshore",
  "offshoring",
  "outsourcing",
  "outsource",
  "nearshore",
  "global delivery",
  "third-party",
  "vendor",
  "managed service provider",
  "msp",
  "shared services"
];

export function cleanText(text) {
  if (!text) return "";
  return text
    .replace(/<[^>]*>/g, " ")       
    .replace(/\s+/g, " ")          
    .trim()
    .toLowerCase();
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function findMatches(text, keywords) {
  const matches = new Set();

  for (const kw of keywords) {
    const escaped = escapeRegex(kw);

    const pattern =
      kw.length <= 3
        ? new RegExp(`\\b${escaped}\\b`, "g")
        : new RegExp(escaped, "g");

    if (pattern.test(text)) matches.add(kw);
  }

  return [...matches];
}

function bucketize(score) {
  if (score === 0) return "none";
  if (score <= 1) return "low";
  if (score <= 3) return "medium";
  return "high";
}

export function scanJobDescription(descriptionRaw) {
  const text = cleanText(descriptionRaw);

  const aiFound = findMatches(text, AI_KEYWORDS);
  const offFound = findMatches(text, OFFSHORING_KEYWORDS);

  const aiScore = aiFound.length;
  const offScore = offFound.length;

  return {
    ai_keyword_count: aiFound.length,
    offshoring_keyword_count: offFound.length,
    ai_keywords_found: aiFound,
    offshoring_keywords_found: offFound,
    ai_score: aiScore,
    offshoring_score: offScore,
    ai_signal_level: bucketize(aiScore),
    offshoring_signal_level: bucketize(offScore)
  };
}
