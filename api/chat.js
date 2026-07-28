// Serverless proxy for the AI Co-Pilot (Vercel function).
// ---------------------------------------------------------------------------
// The app is a static site — the R code runs in the visitor's browser and can
// never read a Vercel environment variable. This tiny function is the bridge:
// it runs on Vercel's servers, reads OPENAI_API_KEY from the project env, and
// forwards the chat request to OpenAI. The key never reaches the browser.
//
// Set it in Vercel: Project → Settings → Environment Variables →
//   OPENAI_API_KEY = sk-...   (Production + Preview)
//
// The app calls this at /api/chat when the user has NOT pasted a personal key.
// ---------------------------------------------------------------------------

export const config = { maxDuration: 60 }; // agent rounds + vision can exceed the 10s default

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: { message: "Method not allowed; use POST." } });
  }
  const key = process.env.OPENAI_API_KEY;
  if (!key) {
    return res.status(500).json({
      error: { message: "OPENAI_API_KEY is not set in this Vercel project's environment variables." },
    });
  }
  try {
    // req.body is a parsed object when Content-Type is application/json;
    // re-stringify so we forward exactly what OpenAI expects.
    const payload = typeof req.body === "string" ? req.body : JSON.stringify(req.body);
    const upstream = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: payload,
    });
    const text = await upstream.text();
    res.status(upstream.status);
    res.setHeader("Content-Type", "application/json");
    return res.send(text);
  } catch (e) {
    return res.status(502).json({ error: { message: "Proxy error: " + String(e) } });
  }
}
