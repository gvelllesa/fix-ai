import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface AiProxyRequest {
  action?: "generate_content" | "eu_vin_decode" | "live_voice_session";
  model?: string;
  prompt?: string;
  systemInstruction?: string;
  mediaParts?: Array<{ mimeType: string; dataBase64: string }>;
  vin?: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized user session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const body = (await req.json()) as AiProxyRequest;
    const action = body.action ?? "generate_content";

    if (action === "eu_vin_decode") {
      const euVinKey = Deno.env.get("EU_VIN_API_KEY");
      if (!euVinKey || !body.vin) {
        return new Response(
          JSON.stringify({ error: "EU VIN decoder unavailable or missing VIN" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const partnerToken = Deno.env.get("EU_VIN_PARTNER_TOKEN") ?? "FIX_AI_PARTNER_TOKEN";
      const vinResp = await fetch(
        `https://api.carmd.com/v3.0/decode?vin=${encodeURIComponent(body.vin)}`,
        {
          headers: {
            "content-type": "application/json",
            "authorization": `Basic ${euVinKey}`,
            "partner-token": partnerToken,
          },
        },
      );

      if (!vinResp.ok) {
        return new Response(
          JSON.stringify({ error: `VIN upstream returned ${vinResp.status}` }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const vinData = await vinResp.json();
      return new Response(JSON.stringify(vinData), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "live_voice_session") {
      return new Response(
        JSON.stringify({
          error: "Ephemeral Gemini Live session token exchange is disabled until backend provisioning.",
        }),
        { status: 501, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Enforce server-side AI quota via atomic Postgres RPC
    const { error: quotaError } = await supabase.rpc("consume_ai_quota");
    if (quotaError) {
      return new Response(
        JSON.stringify({ error: quotaError.message }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiApiKey) {
      return new Response(
        JSON.stringify({ error: "Server GEMINI_API_KEY secret is not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const model = body.model ?? "gemini-2.5-flash";
    const parts: Array<Record<string, unknown>> = [];

    if (body.prompt && body.prompt.trim().length > 0) {
      parts.push({ text: body.prompt });
    }

    if (Array.isArray(body.mediaParts)) {
      for (const media of body.mediaParts) {
        if (media.mimeType && media.dataBase64) {
          parts.push({
            inline_data: {
              mime_type: media.mimeType,
              data: media.dataBase64,
            },
          });
        }
      }
    }

    const payload: Record<string, unknown> = {
      contents: [{ role: "user", parts }],
    };

    if (body.systemInstruction) {
      payload.systemInstruction = {
        parts: [{ text: body.systemInstruction }],
      };
    }

    const geminiUrl =
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(geminiApiKey)}`;

    const upstream = await fetch(geminiUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!upstream.ok) {
      const errText = await upstream.text();
      return new Response(
        JSON.stringify({ error: `Gemini upstream error (${upstream.status})`, details: errText }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const result = await upstream.json();
    const candidateText =
      result?.candidates?.[0]?.content?.parts
        ?.map((p: { text?: string }) => p.text ?? "")
        .join("") ?? "";

    return new Response(
      JSON.stringify({ text: candidateText }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
