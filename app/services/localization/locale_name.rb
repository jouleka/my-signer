module Localization
  # Maps BCP-47 locale tags (e.g. "en-CA", "zh-Hans") to human-readable
  # language names (e.g. "English (Canada)", "Chinese (Simplified)") for use
  # in AI prompts. Without this, LLMs occasionally misread ambiguous region
  # codes — notably "en-CA" gets mistaken for French Canadian.
  class LocaleName
    LANGUAGE_MAP = {
      "en" => "English",
      "fr" => "French",
      "de" => "German",
      "es" => "Spanish",
      "it" => "Italian",
      "pt" => "Portuguese",
      "nl" => "Dutch",
      "ja" => "Japanese",
      "ko" => "Korean",
      "zh" => "Chinese",
      "ru" => "Russian",
      "tr" => "Turkish",
      "ar" => "Arabic",
      "th" => "Thai",
      "vi" => "Vietnamese",
      "pl" => "Polish",
      "sv" => "Swedish",
      "da" => "Danish",
      "fi" => "Finnish",
      "no" => "Norwegian",
      "nb" => "Norwegian Bokmål",
      "he" => "Hebrew",
      "ms" => "Malay",
      "id" => "Indonesian",
      "hi" => "Hindi",
      "el" => "Greek",
      "ro" => "Romanian",
      "hu" => "Hungarian",
      "cs" => "Czech",
      "sk" => "Slovak",
      "uk" => "Ukrainian",
      "ca" => "Catalan",
      "hr" => "Croatian",
      "bg" => "Bulgarian"
    }.freeze

    REGION_MAP = {
      "US" => "United States",
      "GB" => "United Kingdom",
      "CA" => "Canada",
      "AU" => "Australia",
      "DE" => "Germany",
      "FR" => "France",
      "ES" => "Spain",
      "MX" => "Mexico",
      "IT" => "Italy",
      "BR" => "Brazil",
      "PT" => "Portugal",
      "NL" => "Netherlands",
      "BE" => "Belgium",
      "CH" => "Switzerland",
      "AT" => "Austria",
      "JP" => "Japan",
      "KR" => "South Korea",
      "CN" => "China",
      "TW" => "Taiwan",
      "HK" => "Hong Kong",
      "SG" => "Singapore",
      "IN" => "India"
    }.freeze

    SCRIPT_MAP = {
      "Hans" => "Simplified",
      "Hant" => "Traditional",
      "Latn" => "Latin",
      "Cyrl" => "Cyrillic"
    }.freeze

    # Returns a human-readable language name for a BCP-47 tag.
    # Examples:
    #   "en-CA"       → "English (Canada)"
    #   "zh-Hans"     → "Chinese (Simplified)"
    #   "zh-Hans-CN"  → "Chinese (Simplified, China)"
    #   "ja"          → "Japanese"
    #   "xx-YY"       → "xx-YY"  (unknown — fall back to the original tag)
    def self.human(tag)
      return tag.to_s if tag.blank?
      parts = tag.to_s.split("-")
      return tag.to_s unless LANGUAGE_MAP.key?(parts[0])

      lang = LANGUAGE_MAP[parts[0]]
      modifiers = parts[1..].to_a.map { |p| SCRIPT_MAP[p] || REGION_MAP[p] }.compact
      modifiers.empty? ? lang : "#{lang} (#{modifiers.join(", ")})"
    end

    # Formatted for prompts: "en-CA (English, Canada)". Includes both forms
    # so the model has the raw tag AND the disambiguation.
    def self.prompt_label(tag)
      tag_str = tag.to_s
      return tag_str if tag_str.blank?
      parts = tag_str.split("-")
      return tag_str unless LANGUAGE_MAP.key?(parts[0])

      lang = LANGUAGE_MAP[parts[0]]
      modifiers = parts[1..].to_a.map { |p| SCRIPT_MAP[p] || REGION_MAP[p] }.compact
      modifiers.empty? ? "#{tag_str} (#{lang})" : "#{tag_str} (#{lang}, #{modifiers.join(", ")})"
    end
  end
end
