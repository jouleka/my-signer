module ReleaseNotes
  class ConversionHints
    HINTS = [
      {
        key: "benefit_focused",
        label: "Lead with user benefits",
        description: "Focus on what users gain, not internal technical changes.",
        example: "Instead of 'Fixed database sync', try 'Your data now syncs instantly'"
      },
      {
        key: "active_voice",
        label: "Use active, energetic language",
        description: "Active voice feels more direct and engaging to readers.",
        example: "Instead of 'Bugs were fixed', try 'We squashed 5 bugs'"
      },
      {
        key: "specifics_over_vague",
        label: "Be specific about improvements",
        description: "Concrete details build trust and excitement.",
        example: "Instead of 'Performance improvements', try 'App launches 40% faster'"
      },
      {
        key: "length_warning",
        label: "Keep it concise",
        description: "Google Play limits release notes to 500 characters.",
        example: "Prioritize your top changes and trim filler words"
      },
      {
        key: "highlight_requested",
        label: "Mention user-requested features",
        description: "Calling out community-requested features boosts engagement.",
        example: "Call out features your users asked for, e.g. 'You asked, we delivered: dark mode is here!'"
      }
    ].freeze

    PASSIVE_VOICE_PATTERN = /\bwas\s+\w+ed\b|\bwere\s+\w+ed\b|\bbeen\s+\w+ed\b/i
    VAGUE_LANGUAGE_PATTERN = /\bvarious\b|\bseveral\b|\bsome\b|\bminor\b.*\bfix/i

    # Analyze rendered release notes text and return applicable writing hints.
    # Hints are Android-focused for conversion optimization.
    #
    # @param rendered_text [String] The rendered release notes text to analyze
    # @param platform [Symbol] :ios or :android
    # @return [Array<Hash>] Applicable hint hashes
    def self.analyze(rendered_text, platform:)
      return [] if platform == :ios
      return [] if rendered_text.blank?

      applicable = []

      if PASSIVE_VOICE_PATTERN.match?(rendered_text)
        applicable << HINTS.find { |h| h[:key] == "active_voice" }
      end

      if VAGUE_LANGUAGE_PATTERN.match?(rendered_text)
        applicable << HINTS.find { |h| h[:key] == "specifics_over_vague" }
      end

      if rendered_text.length > 400
        applicable << HINTS.find { |h| h[:key] == "length_warning" }
      end

      applicable.compact
    end
  end
end
