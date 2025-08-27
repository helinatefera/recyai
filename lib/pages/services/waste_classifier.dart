import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WasteClassifier {
  final String? apiKey = dotenv.env['OPENAI_API_KEY'];
  final List<Map<String, dynamic>> tools = [
    {
      "type": "function",
      "function": {
        "name": "processMaterialClassification",
        "description":
            "Processes material classification data from a waste image analyzed by a real-time recycling model on mobile devices, where hazardous, organic, or food waste cannot be recycled.",
        "parameters": {
          "type": "object",
          "properties": {
            "level1": {
              "type": "string",
              "description":
                  "Primary material category from the hierarchy: paper cups, cardboard boxes, cardboard packaging, plastic water bottle, Styrofoam, plastic cup lids, plastic food containers, plastic shopping bags, plastic soda bottles, plastic trash bags, plastic straws, plastic items, Paper, Metals, Glass, Organic, E-Waste, Textiles, Hazardous.",
            },
            "visualAnalysis": {
              "type": "string",
              "description": "Cue that influenced the material classification.",
            },
            "recyclable": {
              "type": "string",
              "description":
                  "Whether the material is recyclable, with values 'Yes' or 'No'.",
            },
            "disposalTip": {
              "type": "string",
              "description": "How to recycle or dispose of the material.",
            },
            "brand": {
              "type": "string",
              "description":
                  "Brand name or identifier if visible, otherwise 'Unknown'.",
            },
            "confidence": {
              "type": "string",
              "description":
                  "Confidence level of the classification, with values 'High', 'Medium', or 'Low'.",
            },
          },
          "required": [
            "level1",
            "level2",
            "level3",
            "level4",
            "visualAnalysis",
            "recyclable",
            "disposalTip",
            "brand",
            "confidence",
          ],
          "additionalProperties": false,
        },
      },
    },
  ];
  final String apiEndPoint = "https://api.openai.com/v1/chat/completions";
  final failStatusResponse = {'success': false};

  WasteClassifier() {
    if (apiKey == null || apiKey!.isEmpty) {
      throw Exception(
        "OPENAI_API_KEY is not set or is empty. The app cannot function without a valid API key.",
      );
    }
  }

  Future<Map<String, dynamic>> classify(File imageFile) async {
    String imageBase64 = await toBase64(imageFile);
    String prompt = buildAPICallParameter(imageBase64);
    dynamic apiResponse = await makeAPICall(prompt);
    if (apiResponse?['success'] == false) return failStatusResponse;

    if (isValidToolCall(apiResponse)) {
      dynamic arguments = jsonDecode(
        apiResponse['tool_calls'][0]['function']['arguments'],
      );

      return {
        'label': arguments['level1'],
        'brand': arguments['brand'],
        'tips': arguments['disposalTip'],
        'recyclable': arguments['recyclable']?.toLowerCase() == 'yes',
        'confidence': arguments['confidence'],
      };
    }

    return parseTextReponse(apiResponse);
  }

  Future<Map<String, dynamic>> makeAPICall(String prompt) async {
    try {
      final httpResponse = await http.post(
        Uri.parse(apiEndPoint),
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
        },
        body: prompt,
      );

      if (httpResponse.statusCode != 200) {
        return failStatusResponse;
      }

      final result = jsonDecode(httpResponse.body);
      final message = result['choices']?[0]?['message'];
      if (message == null) {
        return failStatusResponse;
      }

      return message;
    } catch (e) {
      return failStatusResponse;
    }
  }

  String buildAPICallParameter(
    String imageBase64, {
    int maxTokens = 200,
    int temperature = 0,
  }) {
    return jsonEncode({
      "model": "gpt-4o",
      "messages": [
        {
          "role": "user",
          "content": [
            {
              "type": "text",
              "text": """
You are a material classification model for real-time recycling on mobile devices.

Safety first:
- If the item is HAZARDOUS (batteries, bulbs, chemicals, sharps) or E-WASTE (electronics), it is NEVER for household bins. Use Outcome: Special Drop-off.
- If the item is ORGANIC or FOOD WASTE, it is not recyclable curbside. Use Outcome: Green Bin.

Classify the single, closest item using this Level 1 MATERIAL FAMILY (choose one):
Paper, Cardboard, Plastic, Metal, Glass, Organic, E-Waste, Textiles, Hazardous, Unknown

Material detail rules:
- PLASTIC: If you have HIGH confidence (e.g., visible resin code or distinctive cues), name the resin: PET, HDPE, PP, etc. Otherwise say "Plastic".
- METAL: If HIGH confidence, specify "Aluminum" or "Steel". Otherwise say "Metal".
- If confidence is not HIGH, prefer the generic ("Plastic", "Metal").

Outcome mapping:
- Outcome: Blue Bin for recyclables accepted curbside in most programs (clean Paper/Cardboard, PET/HDPE bottles, Aluminum cans, clear Glass jars, etc.).
- Outcome: Green Bin for Non-Recyclables and Organics (contaminated or mixed items, plastic film/bags, Styrofoam, food-soiled paper, most to-go cups/lids, textiles).
- Outcome: Special Drop-off ONLY for Hazardous and E-Waste (never place in household bins).

RecyScore (1–5) rubric (ease of recycling):
5 = Widely accepted curbside when clean (e.g., PET bottle, Aluminum can)
4 = Accepted with prep or locally variable (e.g., Glass jar—rinse; clean cardboard with tape removed)
3 = Sometimes recyclable / low-value / size issues (e.g., small rigid plastics, mixed materials)
2 = Not curbside; store/special drop-off if available (e.g., plastic film, batteries)
1 = Landfill or hazardous—do not bin (e.g., Styrofoam clamshell, used paper cup, chemicals)

Other rules:
- If the item shows food/liquid contamination, set Outcome to Green Bin unless a simple prep (empty/rinse) clearly makes it Blue Bin.
- If multiple materials are visible (e.g., paper cup with plastic lid), classify the dominant item and mention the secondary in the Disposal Tip.
- Brand extraction: only if a clear logo or legible brand text is visible; otherwise 'Unknown'.
- If uncertain overall, use Level 1: Unknown, Outcome: Green Bin, Confidence: Low, and advise a clearer photo.

Call the processMaterialClassification function with EXACTLY these fields:

  Level 1: <Paper|Cardboard|Plastic|Metal|Glass|Organic|E-Waste|Textiles|Hazardous|Unknown>
  Material Detail: <PET|HDPE|PP|Aluminum|Steel|Plastic|Metal|Glass|Paper|Cardboard|Textile|Unknown>
  Outcome: <Blue Bin|Green Bin|Special Drop-off>
  Visual Analysis: <brief cues: shape, seams, translucency, resin code, ridges, logos>
  Recyclable: <Yes|No>  # Blue Bin = Yes; Green Bin or Special Drop-off = No
  Disposal Tip: <1 concise instruction, e.g., "Empty & rinse; Blue bin", "Do not bin; take to e-waste drop-off", "Landfill here">
  Brand: <brand name or 'Unknown'>
  Confidence: <High|Medium|Low>
  RecyScore: <1|2|3|4|5>

Respond concisely.
""",
            },
            {
              "type": "image_url",
              "image_url": {"url": "data:image/jpeg;base64,$imageBase64"},
            },
          ],
        },
      ],
      "tools": tools,
      "max_tokens": maxTokens,
      "temperature": temperature,
    });
  }

  Map<String, dynamic> parseTextReponse(dynamic message) {
    final text =
        message['choices']?[0]?['message']['content']?.toString().trim() ?? '';

    if (text.isNotEmpty) {
      String level1 = 'Unknown';
      String brand = 'Unknown';
      String tips = 'No tip provided';
      bool isRecyclable = false;
      String confidence = 'Unknown';

      final l1 = RegExp(
        r'Level 1:\s*(.*)',
        caseSensitive: false,
      ).firstMatch(text);
      final tipMatch = RegExp(
        r'D ménTip:\s*(.*)',
        caseSensitive: false,
      ).firstMatch(text);
      final brandMatch = RegExp(
        r'Brand:\s*(.*)',
        caseSensitive: false,
      ).firstMatch(text);
      final recyclableMatch = RegExp(
        r'Recyclable:\s*(yes|no)',
        caseSensitive: false,
      ).firstMatch(text);
      final confidenceMatch = RegExp(
        r'Confidence:\s*(High|Medium|Low)',
        caseSensitive: false,
      ).firstMatch(text);

      if (l1 != null) level1 = l1.group(1)?.trim() ?? level1;
      if (tipMatch != null) tips = tipMatch.group(1)?.trim() ?? tips;
      if (brandMatch != null) brand = brandMatch.group(1)?.trim() ?? brand;
      if (recyclableMatch != null) {
        isRecyclable = recyclableMatch.group(1)?.toLowerCase() == 'yes';
      }
      if (confidenceMatch != null) {
        confidence = confidenceMatch.group(1)?.trim() ?? confidence;
      }

      return {
        'label': level1,
        'brand': brand,
        'tips': tips,
        'recyclable': isRecyclable,
        'confidence': confidence,
      };
    }

    return failStatusResponse;
  }

  bool isValidToolCall(dynamic message) {
    final toolCalls = message['tool_calls'];
    if (toolCalls != null && toolCalls is List && toolCalls.isNotEmpty) {
      final toolCall = toolCalls[0];
      if (toolCall['type'] == 'function' &&
          toolCall['function']['name'] == 'processMaterialClassification') {
        final arguments = jsonDecode(toolCall['function']['arguments']);
        return _validateToolCallArguments(arguments);
      }
    }
    return false;
  }

  bool _validateToolCallArguments(Map<String, dynamic> arguments) {
    const requiredKeys = [
      'level1',
      'visualAnalysis',
      'recyclable',
      'disposalTip',
      'brand',
      'confidence',
    ];
    for (var key in requiredKeys) {
      if (!arguments.containsKey(key) ||
          arguments[key] is! String ||
          (arguments[key] as String).isEmpty) {
        return false;
      }
    }
    // Validate recyclable is 'Yes' or 'No'
    if (!['Yes', 'No'].contains(arguments['recyclable'])) {
      return false;
    }
    // Validate confidence is 'High', 'Medium', or 'Low'
    if (!['High', 'Medium', 'Low'].contains(arguments['confidence'])) {
      return false;
    }
    return true;
  }

  Future<String> toBase64(
    File imageFile, {
    int width = 128,
    int height = 128,
  }) async {
    return base64Encode(
      img.encodeJpg(
        img.copyResize(
          img.decodeImage(await imageFile.readAsBytes())!,
          width: width,
          height: height,
        ),
      ),
    );
  }
}
