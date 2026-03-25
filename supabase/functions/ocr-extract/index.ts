import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

const allowedOrigin = Deno.env.get('ALLOWED_ORIGIN') || '*';

const corsHeaders = {
  'Access-Control-Allow-Origin': allowedOrigin,
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const geminiKey = Deno.env.get('GOOGLE_GEMINI_API_KEY');
  if (!geminiKey) {
    console.error('GOOGLE_GEMINI_API_KEY is not configured');
    return new Response(
      JSON.stringify({ error: 'OCR service not configured (missing Gemini key)', invoice_no: null, amount: null, date: null }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  try {
    const { image } = await req.json(); // base64-encoded image (no data URI prefix)

    if (!image) {
      return new Response(
        JSON.stringify({ error: 'No image provided', invoice_no: null, amount: null, date: null }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Detect mime type from base64 header or default to jpeg
    let mimeType = 'image/jpeg';
    if (image.startsWith('/9j/')) mimeType = 'image/jpeg';
    else if (image.startsWith('iVBOR')) mimeType = 'image/png';
    else if (image.startsWith('JVBERi')) mimeType = 'application/pdf';

    console.log(`OCR: Sending image to Gemini (${mimeType}, ${Math.round(image.length * 0.75 / 1024)}KB)...`);

    // Call Gemini API with the image
    const geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{
            parts: [
              {
                text: `You are an invoice/receipt OCR system. Extract these fields from the image:
1. invoice_no - The invoice number, bill number, receipt number, or reference number
2. amount - The total amount (numeric value only, no currency symbols, no commas)
3. date - The invoice/bill date in YYYY-MM-DD format

Return ONLY a JSON object with these three fields. If a field cannot be found, set it to null.
Example: {"invoice_no": "INV-2024-001", "amount": "2510.00", "date": "2024-07-19"}`,
              },
              {
                inlineData: {
                  mimeType: mimeType,
                  data: image,
                },
              },
            ],
          }],
          generationConfig: {
            responseMimeType: 'application/json',
            temperature: 0.1,
          },
        }),
      }
    );

    if (!geminiResponse.ok) {
      const errorText = await geminiResponse.text();
      console.error('Gemini API error:', errorText);
      let errorMessage = `Gemini API error (HTTP ${geminiResponse.status})`;
      try {
        const errorJson = JSON.parse(errorText);
        if (errorJson?.error?.message) {
          errorMessage = errorJson.error.message;
        }
      } catch (_) { /* use default message */ }
      return new Response(
        JSON.stringify({ error: errorMessage, invoice_no: null, amount: null, date: null }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const geminiData = await geminiResponse.json();
    const textContent = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!textContent) {
      console.error('Gemini returned no text content:', JSON.stringify(geminiData).substring(0, 300));
      return new Response(
        JSON.stringify({ error: 'No data extracted from image', invoice_no: null, amount: null, date: null }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('Gemini raw response:', textContent.substring(0, 300));

    // Parse the JSON response from Gemini
    let parsed: { invoice_no: string | null; amount: string | null; date: string | null };
    try {
      parsed = JSON.parse(textContent);
    } catch (_) {
      // If Gemini returned text with markdown code blocks, try to extract JSON
      const jsonMatch = textContent.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        parsed = JSON.parse(jsonMatch[0]);
      } else {
        console.error('Failed to parse Gemini response as JSON:', textContent);
        return new Response(
          JSON.stringify({ error: 'Failed to parse extracted data', invoice_no: null, amount: null, date: null }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Clean up the amount - remove any currency symbols or commas
    if (parsed.amount) {
      parsed.amount = parsed.amount.toString().replace(/[^0-9.]/g, '');
    }

    const result = {
      invoice_no: parsed.invoice_no || null,
      amount: parsed.amount || null,
      date: parsed.date || null,
    };

    console.log('OCR result:', JSON.stringify(result));

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (e) {
    console.error('OCR function error:', e);
    return new Response(
      JSON.stringify({ error: e.message, invoice_no: null, amount: null, date: null }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
