class ScreenshotProject < ApplicationRecord
  belongs_to :organization
  has_many :screenshot_scenes, -> { order(:position) }, dependent: :destroy
  has_many :screenshot_uploads, dependent: :destroy
  has_many :screenshot_exports, dependent: :destroy
  has_one_attached :background_image
  has_many_attached :custom_sticker_images

  after_destroy :cleanup_export_files

  validates :name, presence: true, uniqueness: { scope: :organization_id, message: "already exists for this organization" }
  validates :platform, presence: true, inclusion: { in: %w[ios android both] }
  validate :organization_project_limit, on: :create
  validate :ensure_plan_accessible_on_current_plan, on: :update
  validate :validate_locales
  validate :validate_background_image

  before_validation :strip_blank_locales

  APP_STORE_LOCALES = %w[
    en-US en-GB en-AU en-CA da de-DE el es-ES es-MX fi fr-CA fr-FR hi
    hr hu id it ja ko ms nl-NL no pl pt-BR pt-PT ro ru sk sv th tr uk
    vi zh-Hans zh-Hant ar ca cs he
  ].freeze

  GOOGLE_PLAY_LOCALES = %w[
    af am ar be bg bn-BD ca cs-CZ da-DK de-DE el-GR en-AU en-CA en-GB
    en-IN en-SG en-US en-ZA es-419 es-ES es-US et eu-ES fa fi-FI fil
    fr-CA fr-FR gl-ES hi-IN hr hu-HU hy-AM id is-IS it-IT iw-IL ja-JP
    ka-GE kk km-KH kn-IN ko-KR ky-KG lo-LA lt lv mk-MK ml-IN mn-MN
    mr-IN ms ms-MY my-MM nb-NO ne-NP nl-NL no-NO pa pl-PL pt-BR pt-PT
    ro rm ru-RU si-LK sk sl sq sr sv-SE sw ta-IN te-IN th tr-TR uk
    vi zh-CN zh-HK zh-TW zu
  ].freeze

  MAX_LOCALES = 40

  def self.plan_accessible_ids_for(organization)
    Pricing::OrganizationOverageStatus.new(organization).kept_screenshot_projects.map(&:id)
  end

  def self.plan_frozen_ids_for(organization)
    Pricing::OrganizationOverageStatus.new(organization).overflow_screenshot_projects.map(&:id)
  end

  def multi_locale?
    locales.present? && locales.any?
  end

  def default_locale
    locales.first.presence || "en-US"
  end

  def max_screenshot_scenes_per_project
    organization&.entitlements&.max_screenshot_scenes_per_project ||
      Pricing::Entitlements.for_user(nil).max_screenshot_scenes_per_project
  end

  def plan_access_state
    plan_frozen_on_current_plan? ? "plan_frozen" : "active"
  end

  def plan_frozen_on_current_plan?
    return false unless persisted? && organization.present?

    !self.class.plan_accessible_ids_for(organization).include?(id)
  end

  def plan_accessible_on_current_plan?
    !plan_frozen_on_current_plan?
  end

  def plan_frozen_reason
    return nil unless plan_frozen_on_current_plan?

    count = organization.entitlements.max_screenshot_projects_per_organization
    "This screenshot project is read-only on the #{organization.plan_tier.titleize} plan. Only the oldest #{count} screenshot project#{'s' unless count == 1} remain editable."
  end

  def plan_upgrade_prompt_payload(source:)
    current_plan = organization.plan_tier
    required_plan = organization.entitlements.next_plan_tier
    count = organization.entitlements.max_screenshot_projects_per_organization
    suggestion =
      if required_plan.present? && required_plan.to_s != current_plan.to_s
        "Upgrade from #{current_plan.to_s.titleize} to #{required_plan.to_s.titleize} to unlock this screenshot project."
      else
        "Keep the oldest #{count} screenshot project#{'s' unless count == 1} on the #{current_plan.to_s.titleize} plan or reduce usage to unlock this project."
      end

    Pricing::UpgradePromptPayload.build(
      current_plan: current_plan,
      required_plan: required_plan,
      feature: "this screenshot project",
      message: plan_frozen_reason || "This screenshot project is frozen on the current plan.",
      suggestion: suggestion,
      source: source
    )
  end

  def self.oldest_plan_accessible_for(organization)
    Pricing::OrganizationOverageStatus.new(organization).kept_screenshot_projects.first
  end

  private def ensure_plan_accessible_on_current_plan
    return if plan_accessible_on_current_plan?

    errors.add(:base, plan_frozen_reason || "This screenshot project is frozen on the current plan.")
  end

  private def strip_blank_locales
    self.locales = locales.reject(&:blank?) if locales.present?
  end

  private def validate_locales
    return if locales.blank?
    if locales.size > MAX_LOCALES
      errors.add(:locales, "cannot have more than #{MAX_LOCALES} locales")
    end
    locales.each do |locale|
      unless APP_STORE_LOCALES.include?(locale)
        errors.add(:locales, "contains unsupported locale: #{locale}. Must be one of: #{APP_STORE_LOCALES.join(', ')}")
      end
    end
  end

  ALLOWED_BG_IMAGE_TYPES = %w[image/png image/jpeg image/webp].freeze
  MAX_BG_IMAGE_SIZE = 10.megabytes

  ALLOWED_CUSTOM_STICKER_TYPES = %w[image/png image/jpeg image/webp].freeze
  MAX_CUSTOM_STICKER_SIZE = 5.megabytes
  MAX_CUSTOM_STICKERS_PER_PROJECT = 50

  private def validate_background_image
    return unless background_image.attached?
    unless ALLOWED_BG_IMAGE_TYPES.include?(background_image.content_type)
      errors.add(:background_image, "must be PNG, JPEG, or WebP")
    end
    if background_image.byte_size > MAX_BG_IMAGE_SIZE
      errors.add(:background_image, "must be less than 10 MB")
    end
  end

  private def organization_project_limit
    return unless organization

    limit = organization.entitlements.max_screenshot_projects_per_organization
    if organization.screenshot_projects.count >= limit
      errors.add(
        :base,
        :quota_exhausted,
        message: "Organization has reached the maximum of #{limit} screenshot projects on the #{organization.plan_tier.titleize} plan",
        feature: :screenshot_projects,
        current_plan: organization.plan_tier,
        next_plan: organization.entitlements.next_plan_tier
      )
    end
  end

  POPULAR_EMOJIS = {
    smileys: %w[😀 😃 😄 😁 😆 🥹 😅 🤣 😂 🙂 😊 😇 🥰 😍 🤩 😘 😜 🤪 😎 🤓 🥳 😤 🔥 💯],
    hands: %w[👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👍 👎 ✊ 👊 🤛],
    people: %w[👶 👧 🧒 👦 👩 🧑 👨 👩‍🦱 👨‍🦱 👩‍🦰 👨‍🦰 🧔 👵 🧓 👴 👮 💂 👷 🤴 👸 🦸 🧙 👼 🎅],
    animals: %w[🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 🦆 🦅 🦋 🐝 🐞 🐙],
    food: %w[🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍒 🍑 🥭 🍍 🥝 🍔 🍕 🌮 🍣 🍩 🍰 🧁 🍦 ☕ 🧋],
    objects: %w[⭐ 🌟 ✨ 💫 🌈 ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 💎 👑 🏆 🎯 🎪 🎨 🎬 📱 💻 🖥️ ⌚],
    symbols: %w[✅ ❌ ⭕ 🔴 🟡 🟢 🔵 ⬆️ ➡️ ⬇️ ⬅️ ↩️ 🔄 ⚡ 💥 🌀 🔔 🎵 🎶 💬 💭 🏷️ 📌 🔗],
    flags: %w[🇺🇸 🇬🇧 🇩🇪 🇫🇷 🇪🇸 🇮🇹 🇯🇵 🇰🇷 🇨🇳 🇧🇷 🇮🇳 🇷🇺 🇨🇦 🇦🇺 🇲🇽 🏳️‍🌈 🏴‍☠️ 🚩 🏁 🎌 🏳️ 🇵🇹 🇳🇱 🇸🇪]
  }.freeze

  GOOGLE_FONTS_BY_CATEGORY = {
    "Sans-Serif" => [
      "Inter", "Roboto", "Open Sans", "Poppins", "Montserrat", "Lato",
      "Raleway", "Nunito", "Work Sans", "DM Sans", "Space Grotesk",
      "Outfit", "Sora", "Manrope", "Plus Jakarta Sans", "Lexend",
      "Urbanist", "Figtree", "Noto Sans", "Source Sans 3", "Barlow",
      "Karla", "Rubik", "Mulish", "Quicksand", "Exo 2", "Overpass",
      "Red Hat Display", "Albert Sans", "Libre Franklin", "Cabin",
      "Titillium Web", "Josefin Sans", "Catamaran", "Mukta", "Archivo",
      "Public Sans", "Hind", "Jost", "Assistant", "Signika",
      "Varela Round", "Maven Pro", "Comfortaa", "Abel", "Sarabun",
      "IBM Plex Sans", "Nunito Sans", "PT Sans", "Dosis", "Kanit"
    ],
    "Serif" => [
      "Playfair Display", "Bitter", "Merriweather", "Lora", "Crimson Text",
      "Libre Baskerville", "EB Garamond", "Cormorant Garamond", "Spectral",
      "Noto Serif", "Source Serif 4", "PT Serif", "Vollkorn", "Literata",
      "DM Serif Display", "Domine", "Cardo", "Alegreya", "Old Standard TT",
      "Unna", "Cormorant", "Gilda Display", "Zilla Slab", "Arvo",
      "Rokkitt"
    ],
    "Display" => [
      "Bebas Neue", "Oswald", "Anton", "Teko", "Barlow Condensed",
      "Fjalla One", "Passion One", "Bungee", "Black Ops One", "Russo One",
      "Righteous", "Orbitron", "Audiowide", "Changa", "Khand",
      "Big Shoulders Display", "Racing Sans One", "Black Han Sans",
      "Secular One", "Alfa Slab One", "Lilita One", "Fredoka",
      "Baloo 2", "Luckiest Guy", "Bungee Shade"
    ],
    "Handwriting" => [
      "Pacifico", "Permanent Marker", "Dancing Script", "Caveat",
      "Satisfy", "Great Vibes", "Sacramento", "Kalam", "Indie Flower",
      "Shadows Into Light", "Amatic SC", "Patrick Hand",
      "Architects Daughter", "Gloria Hallelujah", "Rock Salt",
      "Covered By Your Grace", "Homemade Apple", "Nothing You Could Do",
      "Reenie Beanie", "Yellowtail"
    ],
    "Monospace" => [
      "Fira Code", "JetBrains Mono", "Source Code Pro", "IBM Plex Mono",
      "Space Mono", "Inconsolata", "Ubuntu Mono", "Roboto Mono",
      "Red Hat Mono", "DM Mono"
    ]
  }.freeze

  GOOGLE_FONTS = GOOGLE_FONTS_BY_CATEGORY.values.flatten.freeze

  DEFAULT_TEXT_SETTINGS = {
    "caption_font_family" => "Inter",
    "caption_text_align" => "center",
    "caption_mode" => "zone",
    "caption_zone_size" => 12,
    "caption_font_weight" => 700,
    "caption_letter_spacing" => 0,
    "caption_line_height" => 1.3,
    "caption_vertical_position" => nil,
    "subtitle_font_size" => 20,
    "subtitle_color" => "#CCCCCC",
    "subtitle_font_family" => "Inter",
    "subtitle_font_weight" => 400,
    "subtitle_letter_spacing" => 0,
    "subtitle_line_height" => 1.3,
    "text_bg_enabled" => false,
    "text_bg_color" => "#000000",
    "text_bg_opacity" => 50,
    "text_bg_radius" => 12,
    "text_bg_padding_x" => 24,
    "text_bg_padding_y" => 12,
    "caption_stroke_enabled" => false,
    "caption_stroke_color" => "#000000",
    "caption_stroke_width" => 2,
    "caption_gradient_enabled" => false,
    "caption_gradient_start" => "#FF6B6B",
    "caption_gradient_end" => "#4ECDC4"
  }.freeze

  DEVICE_FRAMES = {
    "none" => { label: "No Frame", width: nil, height: nil, platform: "both" },
    "iphone_16_pro_max" => {
      label: "iPhone 16 Pro Max", width: 1320, height: 2868, platform: "ios",
      vb_width: 440, vb_height: 956,
      screen_x: 20, screen_y: 40, screen_width: 400, screen_height: 876, screen_rx: 30
    },
    "iphone_15_pro_max" => {
      label: "iPhone 15 Pro Max", width: 1290, height: 2796, platform: "ios",
      vb_width: 430, vb_height: 932,
      screen_x: 18, screen_y: 38, screen_width: 394, screen_height: 856, screen_rx: 28
    },
    "iphone_11_pro_max" => {
      label: "iPhone 11 Pro Max", width: 1242, height: 2688, platform: "ios",
      vb_width: 428, vb_height: 896,
      screen_x: 18, screen_y: 50, screen_width: 392, screen_height: 800, screen_rx: 26
    },
    "iphone_8_plus" => {
      label: "iPhone 8 Plus", width: 1242, height: 2208, platform: "ios",
      vb_width: 414, vb_height: 736,
      screen_x: 18, screen_y: 90, screen_width: 378, screen_height: 556, screen_rx: 4
    },
    "ipad_pro_129" => {
      label: "iPad Pro 12.9\"", width: 2048, height: 2732, platform: "ios",
      vb_width: 684, vb_height: 912,
      screen_x: 24, screen_y: 24, screen_width: 636, screen_height: 864, screen_rx: 12
    },
    "ipad_pro_11" => {
      label: "iPad Pro 11\"", width: 1668, height: 2388, platform: "ios",
      vb_width: 556, vb_height: 796,
      screen_x: 22, screen_y: 22, screen_width: 512, screen_height: 752, screen_rx: 10
    },
    "pixel_9" => {
      label: "Pixel 9", width: 1080, height: 2424, platform: "android",
      vb_width: 360, vb_height: 808,
      screen_x: 14, screen_y: 32, screen_width: 332, screen_height: 744, screen_rx: 22
    },
    "generic_phone" => {
      label: "Generic Phone", width: 1080, height: 1920, platform: "both",
      vb_width: 360, vb_height: 640,
      screen_x: 14, screen_y: 30, screen_width: 332, screen_height: 580, screen_rx: 16
    },
    "generic_tablet_7" => {
      label: "Generic 7\" Tablet", width: 1200, height: 1920, platform: "android",
      vb_width: 400, vb_height: 640,
      screen_x: 20, screen_y: 20, screen_width: 360, screen_height: 600, screen_rx: 8
    },
    "generic_tablet_10" => {
      label: "Generic 10\" Tablet", width: 1600, height: 2560, platform: "android",
      vb_width: 534, vb_height: 854,
      screen_x: 24, screen_y: 24, screen_width: 486, screen_height: 806, screen_rx: 10
    }
  }.freeze

  DEFAULT_CUSTOM_SETTINGS = DEFAULT_TEXT_SETTINGS.merge(
    "background_type" => "solid",
    "background_color" => "#000000",
    "caption_color" => "#FFFFFF",
    "caption_font_size" => 32,
    "caption_position" => "top",
    "device_frame" => "none",
    "screenshot_padding" => 8,
    "screenshot_offset_y" => 0,
    "perspective_preset" => "none",
    "perspective_rotate_x" => 0,
    "perspective_rotate_y" => 0,
    "perspective_distance" => 2000,
    "perspective_shadow" => false,
    "perspective_reflection" => false,
    "layout_mode" => "auto"
  ).freeze

  PERSPECTIVE_PRESETS = {
    "none"         => { label: "None",         rotate_x: 0,   rotate_y: 0,   distance: 2000 },
    "slight_left"  => { label: "Slight Left",  rotate_x: 0,   rotate_y: 12,  distance: 2000 },
    "slight_right" => { label: "Slight Right", rotate_x: 0,   rotate_y: -12, distance: 2000 },
    "left_tilt"    => { label: "Left Tilt",    rotate_x: 5,   rotate_y: 25,  distance: 2000 },
    "right_tilt"   => { label: "Right Tilt",   rotate_x: 5,   rotate_y: -25, distance: 2000 },
    "top_down"     => { label: "Top Down",     rotate_x: 20,  rotate_y: 0,   distance: 2000 },
    "bottom_up"    => { label: "Bottom Up",    rotate_x: -20, rotate_y: 0,   distance: 2000 },
    "hero_left"    => { label: "Hero Left",    rotate_x: 8,   rotate_y: 30,  distance: 2000 },
    "hero_right"   => { label: "Hero Right",   rotate_x: 8,   rotate_y: -30, distance: 2000 },
    "showcase"     => { label: "Showcase",     rotate_x: 12,  rotate_y: -20, distance: 2000 },
    "isometric"    => { label: "Isometric",    rotate_x: 18,  rotate_y: 22,  distance: 2000 },
    "flat_lay"     => { label: "Flat Lay",     rotate_x: 35,  rotate_y: 0,   distance: 2000 }
  }.freeze

  TEMPLATES = {
    # 1. Sunset Showcase — mesh sunset + 3D showcase + reflection + gradient text + emoji/badge stickers
    "sunset_showcase" => {
      label: "Sunset Showcase",
      description: "Warm gold gradient with elegant serif typography and reflective framing",
      settings: {
        "caption_text" => "Designed to shine",
        "caption_font_family" => "Playfair Display",
        "caption_font_size" => 94,
        "caption_color" => "#451a03",
        "caption_text_align" => "right",
        "caption_mode" => "zone",
        "caption_position" => "top",
        "caption_zone_size" => 22,
        "caption_letter_spacing" => 1,
        "caption_line_height" => 1.1,
        "caption_vertical_position" => "50",
        "subtitle_font_family" => "Crimson Text",
        "subtitle_font_size" => 43,
        "subtitle_color" => "#92400e",
        "text_bg_enabled" => false,
        "caption_stroke_enabled" => false,
        "caption_gradient_enabled" => false,
        "background_type" => "gradient",
        "gradient_start" => "#fef3c7",
        "gradient_end" => "#fbbf24",
        "gradient_direction" => "to-bottom",
        "device_frame" => "iphone_16_pro_max",
        "screenshot_padding" => 1,
        "screenshot_offset_y" => -4,
        "perspective_preset" => "none",
        "perspective_rotate_x" => 0,
        "perspective_rotate_y" => 0,
        "perspective_distance" => 2000,
        "perspective_shadow" => true,
        "perspective_reflection" => true,
        "text_position_x" => 49.4,
        "text_position_y" => 15.3
      }
    },
    # 2. Geometric Bold — wave pattern + huge display text + stroke + emoji stickers
    "geometric_bold" => {
      label: "Geometric Bold",
      description: "Waves pattern with oversized Anton/Cyan typography and bold stroke",
      settings: {
        "caption_text" => "STAND OUT",
        "subtitle_text" => "Patterns that grab attention",
        "caption_font_family" => "Anton",
        "caption_font_weight" => 400,
        "caption_font_size" => 106,
        "caption_color" => "#459fb5",
        "caption_text_align" => "center",
        "caption_mode" => "zone",
        "caption_position" => "top",
        "caption_zone_size" => 12,
        "caption_letter_spacing" => 8,
        "caption_line_height" => 1.0,
        "caption_vertical_position" => "5",
        "subtitle_font_family" => "Barlow Condensed",
        "subtitle_font_weight" => 300,
        "subtitle_font_size" => 63,
        "subtitle_color" => "#67e8f9",
        "text_bg_enabled" => false,
        "caption_stroke_enabled" => true,
        "caption_stroke_color" => "#0f172a",
        "caption_stroke_width" => 3,
        "caption_gradient_enabled" => false,
        "background_type" => "pattern",
        "pattern_id" => "waves",
        "pattern_color" => "#22d3ee",
        "pattern_bg_color" => "#0f172a",
        "pattern_scale" => 200,
        "device_frame" => "pixel_9",
        "screenshot_padding" => 5,
        "screenshot_offset_y" => 3,
        "perspective_preset" => "custom",
        "perspective_rotate_x" => 12,
        "perspective_rotate_y" => 0,
        "perspective_distance" => 2000,
        "perspective_shadow" => true,
        "perspective_reflection" => true,
        "default_stickers" => [
          { "type" => "emoji", "emoji" => "\u{1F525}", "x" => 87, "y" => 11, "size" => 72, "rotation" => 0 }
        ]
      }
    },
    # 3. Neon Hero — solid dark + hero right 3D + gradient+stroke+pill + emoji/icon stickers
    "neon_hero" => {
      label: "Neon Hero",
      description: "High-contrast gradient with huge Urbanist type and custom hero tilt",
      settings: {
        "caption_text" => "Light it up",
        "subtitle_text" => "GRADIENT \u00B7 GLOW \u00B7 3D",
        "background_type" => "gradient",
        "gradient_start" => "#000000",
        "gradient_end" => "#764ba2",
        "gradient_direction" => "to-bottom",
        "caption_color" => "#ffffff",
        "caption_font_family" => "Urbanist",
        "caption_font_weight" => 800,
        "caption_font_size" => 142,
        "caption_text_align" => "center",
        "caption_mode" => "zone",
        "caption_position" => "top",
        "caption_zone_size" => 16,
        "caption_letter_spacing" => -1,
        "caption_line_height" => 1.1,
        "caption_vertical_position" => "50",
        "subtitle_color" => "#e879f9",
        "subtitle_font_family" => "Urbanist",
        "subtitle_font_size" => 47,
        "text_bg_enabled" => true,
        "text_bg_color" => "#7c3aed",
        "text_bg_opacity" => 25,
        "text_bg_radius" => 20,
        "caption_stroke_enabled" => true,
        "caption_stroke_color" => "#7c3aed",
        "caption_stroke_width" => 2,
        "caption_gradient_enabled" => true,
        "caption_gradient_start" => "#06b6d4",
        "caption_gradient_end" => "#e879f9",
        "device_frame" => "generic_phone",
        "screenshot_padding" => 8,
        "screenshot_offset_y" => -5,
        "perspective_preset" => "custom",
        "perspective_rotate_x" => 2,
        "perspective_rotate_y" => -24,
        "perspective_distance" => 2000,
        "perspective_shadow" => true,
        "perspective_reflection" => true,
        "text_position_x" => 50.7,
        "text_position_y" => 92.1,
        "default_stickers" => [
          { "type" => "emoji", "emoji" => "\u26A1", "x" => 81, "y" => 8, "size" => 56, "rotation" => 0 },
          { "type" => "asset", "asset_key" => "sparkles", "x" => 18, "y" => 8, "size" => 64, "rotation" => 0, "color" => "#E879F9" }
        ]
      }
    },
    # 4. Warm Editorial — warm gradient + serif fonts + right-align + subtle tilt + emoji/badge stickers
    "warm_editorial" => {
      label: "Warm Editorial",
      description: "Gold editorial style with refined serif pairings and premium badge accents",
      settings: {
        "caption_text" => "",
        "subtitle_text" => "",
        "caption_font_family" => "Playfair Display",
        "caption_font_size" => 76,
        "caption_color" => "#451a03",
        "caption_text_align" => "right",
        "caption_mode" => "zone",
        "caption_position" => "top",
        "caption_zone_size" => 22,
        "caption_letter_spacing" => 1,
        "caption_line_height" => 1.1,
        "caption_vertical_position" => "50",
        "subtitle_font_family" => "Crimson Text",
        "subtitle_font_size" => 44,
        "subtitle_color" => "#92400e",
        "text_bg_enabled" => false,
        "caption_stroke_enabled" => false,
        "caption_gradient_enabled" => false,
        "background_type" => "gradient",
        "gradient_start" => "#fef3c7",
        "gradient_end" => "#fbbf24",
        "gradient_direction" => "to-bottom",
        "device_frame" => "iphone_16_pro_max",
        "screenshot_padding" => 2,
        "screenshot_offset_y" => -20,
        "perspective_preset" => "custom",
        "perspective_rotate_x" => 0,
        "perspective_rotate_y" => 21,
        "perspective_distance" => 2000,
        "perspective_shadow" => true,
        "perspective_reflection" => true,
        "default_stickers" => [
          { "type" => "emoji", "emoji" => "\u{1F451}", "x" => 91, "y" => 4, "size" => 144, "rotation" => 15 },
          { "type" => "asset", "asset_key" => "editors_choice", "x" => 26, "y" => 7, "size" => 400, "rotation" => 0, "color" => "#92400E" }
        ]
      }
    },
    # 5. Tech Grid — neon mesh + isometric 3D + monospace + icon/badge stickers
    "tech_grid" => {
      label: "Tech Grid",
      description: "Neon mesh with terminal-style type, low-angle tilt, and launch badges",
      settings: {
        "caption_text" => "Built for speed",
        "subtitle_text" => "// performance meets design",
        "background_type" => "mesh",
        "mesh_preset" => "neon",
        "mesh_color_1" => "#1a1a4e",
        "mesh_color_2" => "#2d2d7f",
        "mesh_color_3" => "#15154b",
        "caption_color" => "#4ade80",
        "caption_font_family" => "JetBrains Mono",
        "caption_font_size" => 85,
        "caption_text_align" => "center",
        "caption_mode" => "zone",
        "caption_position" => "top",
        "caption_zone_size" => 14,
        "caption_letter_spacing" => -0.5,
        "caption_line_height" => 1.2,
        "caption_vertical_position" => "50",
        "subtitle_color" => "#86efac",
        "subtitle_font_family" => "Fira Code",
        "subtitle_font_weight" => 300,
        "subtitle_font_size" => 35,
        "text_bg_enabled" => false,
        "caption_stroke_enabled" => false,
        "caption_gradient_enabled" => false,
        "device_frame" => "pixel_9",
        "screenshot_padding" => 7,
        "perspective_preset" => "custom",
        "perspective_rotate_x" => -9,
        "perspective_rotate_y" => 1,
        "perspective_distance" => 2000,
        "perspective_shadow" => true,
        "perspective_reflection" => true,
        "text_position_x" => 48.5,
        "text_position_y" => 95.4,
        "default_stickers" => [
          { "type" => "asset", "asset_key" => "rocket", "x" => 89, "y" => 97, "size" => 120, "rotation" => 0, "color" => "#4ADE80" },
          { "type" => "asset", "asset_key" => "number_one_app", "x" => 25, "y" => 89, "size" => 267, "rotation" => 0, "color" => "#4ADE80" }
        ]
      }
    },
    # 6. Value Promise — bold benefit headline at top, centered device, vibrant gradient (conversion pattern 1/3)
    "value_promise" => {
      label: "Value Promise",
      description: "Bold benefit headline with hero screenshot — proven conversion opener",
      settings: {
        "caption_text" => "The smarter way\nto get things done",
        "subtitle_text" => "Save hours every week",
        "caption_font_family" => "Inter",
        "caption_font_weight" => 800,
        "caption_font_size" => 88,
        "caption_color" => "#ffffff",
        "caption_text_align" => "center",
        "caption_mode" => "zone",
        "caption_position" => "top",
        "caption_zone_size" => 24,
        "caption_letter_spacing" => -1,
        "caption_line_height" => 1.1,
        "caption_vertical_position" => "50",
        "subtitle_font_family" => "Inter",
        "subtitle_font_weight" => 400,
        "subtitle_font_size" => 40,
        "subtitle_color" => "#e0e7ff",
        "subtitle_letter_spacing" => 0.5,
        "subtitle_line_height" => 1.3,
        "text_bg_enabled" => false,
        "caption_stroke_enabled" => false,
        "caption_gradient_enabled" => false,
        "background_type" => "gradient",
        "gradient_start" => "#4338ca",
        "gradient_end" => "#7c3aed",
        "gradient_direction" => "to-bottom",
        "device_frame" => "iphone_16_pro_max",
        "screenshot_padding" => 4,
        "screenshot_offset_y" => -6,
        "perspective_preset" => "none",
        "perspective_rotate_x" => 0,
        "perspective_rotate_y" => 0,
        "perspective_distance" => 2000,
        "perspective_shadow" => true,
        "perspective_reflection" => false,
        "text_position_x" => 50,
        "text_position_y" => 10
      }
    },
    # 7. Feature Showcase — device with perspective tilt, feature callout text (conversion pattern 2/3)
    "feature_showcase" => {
      label: "Feature Showcase",
      description: "Angled device with feature callout — highlight your app in action",
      settings: {
        "caption_text" => "Swipe to organize",
        "subtitle_text" => "Drag, drop, done",
        "caption_font_family" => "DM Sans",
        "caption_font_weight" => 700,
        "caption_font_size" => 78,
        "caption_color" => "#1e293b",
        "caption_text_align" => "left",
        "caption_mode" => "zone",
        "caption_position" => "top",
        "caption_zone_size" => 18,
        "caption_letter_spacing" => -0.5,
        "caption_line_height" => 1.15,
        "caption_vertical_position" => "50",
        "subtitle_font_family" => "DM Sans",
        "subtitle_font_weight" => 400,
        "subtitle_font_size" => 38,
        "subtitle_color" => "#64748b",
        "subtitle_letter_spacing" => 0,
        "subtitle_line_height" => 1.3,
        "text_bg_enabled" => false,
        "caption_stroke_enabled" => false,
        "caption_gradient_enabled" => false,
        "background_type" => "gradient",
        "gradient_start" => "#f0f9ff",
        "gradient_end" => "#e0f2fe",
        "gradient_direction" => "to-bottom",
        "device_frame" => "iphone_16_pro_max",
        "screenshot_padding" => 5,
        "screenshot_offset_y" => -3,
        "perspective_preset" => "custom",
        "perspective_rotate_x" => 5,
        "perspective_rotate_y" => -15,
        "perspective_distance" => 2000,
        "perspective_shadow" => true,
        "perspective_reflection" => true,
        "text_position_x" => 25,
        "text_position_y" => 14,
        "default_stickers" => [
          { "type" => "asset", "asset_key" => "anno_arrow_curved", "x" => 48, "y" => 42, "size" => 72, "rotation" => 90, "color" => "#3b82f6" }
        ]
      }
    },
    # 8. Social Proof — star ratings, trust badges, quote text (conversion pattern 3/3)
    "social_proof" => {
      label: "Social Proof",
      description: "Star ratings and trust badges — build credibility with social proof",
      settings: {
        "caption_text" => "Loved by 50,000+\nhappy users",
        "subtitle_text" => "\"Best app I've ever used\" — App Store review",
        "caption_font_family" => "Inter",
        "caption_font_weight" => 700,
        "caption_font_size" => 76,
        "caption_color" => "#18181b",
        "caption_text_align" => "center",
        "caption_mode" => "zone",
        "caption_position" => "top",
        "caption_zone_size" => 22,
        "caption_letter_spacing" => -0.5,
        "caption_line_height" => 1.15,
        "caption_vertical_position" => "50",
        "subtitle_font_family" => "Inter",
        "subtitle_font_weight" => 400,
        "subtitle_font_size" => 34,
        "subtitle_color" => "#71717a",
        "subtitle_letter_spacing" => 0,
        "subtitle_line_height" => 1.4,
        "text_bg_enabled" => false,
        "caption_stroke_enabled" => false,
        "caption_gradient_enabled" => false,
        "background_type" => "gradient",
        "gradient_start" => "#fafafa",
        "gradient_end" => "#f4f4f5",
        "gradient_direction" => "to-bottom",
        "device_frame" => "iphone_16_pro_max",
        "screenshot_padding" => 3,
        "screenshot_offset_y" => -8,
        "perspective_preset" => "none",
        "perspective_rotate_x" => 0,
        "perspective_rotate_y" => 0,
        "perspective_distance" => 2000,
        "perspective_shadow" => true,
        "perspective_reflection" => false,
        "text_position_x" => 50,
        "text_position_y" => 12,
        "default_stickers" => [
          { "type" => "asset", "asset_key" => "star_rating_5", "x" => 50, "y" => 5, "size" => 120, "rotation" => 0, "color" => "#f59e0b" },
          { "type" => "asset", "asset_key" => "editors_choice", "x" => 88, "y" => 92, "size" => 300, "rotation" => 0, "color" => "#18181B" },
          { "type" => "asset", "asset_key" => "top_rated", "x" => 12, "y" => 92, "size" => 300, "rotation" => 0, "color" => "#18181B" }
        ]
      }
    },
    # 9. Playful Party — confetti pattern + flat lay 3D + handwriting fonts + pill bg + multi stickers
    "playful_party" => {
      label: "Playful Party",
      description: "Confetti poster style with giant celebratory stickers and soft text pill",
      settings: {
        "caption_text" => "Celebrate every launch",
        "subtitle_text" => "Your app deserves a party",
        "background_type" => "pattern",
        "pattern_id" => "confetti",
        "pattern_color" => "#f472b6",
        "pattern_bg_color" => "#fff1f2",
        "pattern_scale" => 120,
        "caption_color" => "#be185d",
        "caption_font_family" => "Pacifico",
        "caption_font_weight" => 400,
        "caption_font_size" => 68,
        "caption_text_align" => "center",
        "caption_mode" => "zone",
        "caption_position" => "top",
        "caption_zone_size" => 16,
        "caption_line_height" => 1.2,
        "caption_vertical_position" => "50",
        "subtitle_color" => "#9d174d",
        "subtitle_font_family" => "Caveat",
        "subtitle_font_weight" => 700,
        "subtitle_font_size" => 53,
        "text_bg_enabled" => true,
        "text_bg_color" => "#ffffff",
        "text_bg_opacity" => 70,
        "text_bg_radius" => 24,
        "caption_stroke_enabled" => false,
        "caption_gradient_enabled" => false,
        "device_frame" => "iphone_16_pro_max",
        "screenshot_padding" => 0,
        "screenshot_offset_y" => -16,
        "perspective_preset" => "custom",
        "perspective_rotate_x" => 0,
        "perspective_rotate_y" => 5,
        "perspective_distance" => 2000,
        "perspective_shadow" => true,
        "perspective_reflection" => true,
        "text_position_x" => 50.8,
        "text_position_y" => 14.4,
        "default_stickers" => [
          { "type" => "emoji", "emoji" => "\u{1F389}", "x" => 91, "y" => 5, "size" => 109, "rotation" => 0 },
          { "type" => "emoji", "emoji" => "\u{1F3A8}", "x" => 15, "y" => 4, "size" => 129, "rotation" => -10 },
          { "type" => "asset", "asset_key" => "anno_starburst", "x" => 49, "y" => 95, "size" => 125, "rotation" => 0, "color" => "#F472B6" }
        ]
      }
    }
  }.freeze

  PATTERN_LIBRARY = {
    tiles: [
      { id: "dots", label: "Dots", file: "pattern_library/dots.svg" },
      { id: "grid", label: "Grid", file: "pattern_library/grid.svg" },
      { id: "diagonal_lines", label: "Diagonal Lines", file: "pattern_library/diagonal_lines.svg" },
      { id: "cross_hatch", label: "Cross Hatch", file: "pattern_library/cross_hatch.svg" },
      { id: "chevrons", label: "Chevrons", file: "pattern_library/chevrons.svg" },
      { id: "circles", label: "Circles", file: "pattern_library/circles.svg" },
      { id: "hexagons", label: "Hexagons", file: "pattern_library/hexagons.svg" },
      { id: "waves", label: "Waves", file: "pattern_library/waves.svg" },
      { id: "triangles", label: "Triangles", file: "pattern_library/triangles.svg" },
      { id: "diamonds", label: "Diamonds", file: "pattern_library/diamonds.svg" }
    ],
    procedural: [
      { id: "perlin_noise", label: "Noise" },
      { id: "confetti", label: "Confetti" },
      { id: "topography", label: "Topography" }
    ]
  }.freeze

  STICKER_SIZE_DEFAULTS = {
    "annotations" => 80,
    "icons" => 64,
    "badges" => 96,
    "ui_elements" => 80
  }.freeze

  STICKER_LIBRARY = {
    annotations: { label: "Annotations", icon: "fa-solid fa-pen-fancy", items: [
      # Arrows
      { key: "anno_arrow_straight", label: "Straight Arrow", file: "sticker_library/annotations/arrow_straight.svg", tags: "arrow straight direction pointer" },
      { key: "anno_arrow_curved", label: "Curved Arrow", file: "sticker_library/annotations/arrow_curved.svg", tags: "arrow curved arc direction" },
      { key: "anno_arrow_double", label: "Double Arrow", file: "sticker_library/annotations/arrow_double.svg", tags: "arrow double both directions" },
      { key: "anno_pointer_hand", label: "Pointer Hand", file: "sticker_library/annotations/pointer_hand.svg", tags: "pointer hand cursor tap click" },
      # Highlights
      { key: "anno_highlight_circle", label: "Circle Highlight", file: "sticker_library/annotations/highlight_circle.svg", tags: "highlight circle ring focus" },
      { key: "anno_highlight_rect", label: "Rectangle Highlight", file: "sticker_library/annotations/highlight_rect.svg", tags: "highlight rectangle box frame" },
      { key: "anno_underline", label: "Underline", file: "sticker_library/annotations/underline.svg", tags: "underline emphasis line" },
      { key: "anno_bracket_left", label: "Bracket", file: "sticker_library/annotations/bracket_left.svg", tags: "bracket brace group" },
      # Callouts
      { key: "anno_speech_bubble", label: "Speech Bubble", file: "sticker_library/annotations/speech_bubble.svg", tags: "speech bubble chat callout text" },
      { key: "anno_thought_bubble", label: "Thought Bubble", file: "sticker_library/annotations/thought_bubble.svg", tags: "thought bubble think cloud" },
      { key: "anno_callout_box", label: "Callout Box", file: "sticker_library/annotations/callout_box.svg", tags: "callout box tooltip label" },
      # Indicators
      { key: "anno_numbered_1", label: "Number 1", file: "sticker_library/annotations/numbered_1.svg", tags: "number one 1 step first" },
      { key: "anno_numbered_2", label: "Number 2", file: "sticker_library/annotations/numbered_2.svg", tags: "number two 2 step second" },
      { key: "anno_numbered_3", label: "Number 3", file: "sticker_library/annotations/numbered_3.svg", tags: "number three 3 step third" },
      { key: "anno_numbered_4", label: "Number 4", file: "sticker_library/annotations/numbered_4.svg", tags: "number four 4 step fourth" },
      { key: "anno_numbered_5", label: "Number 5", file: "sticker_library/annotations/numbered_5.svg", tags: "number five 5 step fifth" },
      { key: "anno_badge_check", label: "Badge Check", file: "sticker_library/annotations/badge_check.svg", tags: "badge check verified approved yes" },
      { key: "anno_badge_x", label: "Badge X", file: "sticker_library/annotations/badge_x.svg", tags: "badge x cross no wrong" },
      { key: "anno_starburst", label: "Starburst", file: "sticker_library/annotations/starburst.svg", tags: "starburst star explosion new" }
    ] },
    icons: { label: "Icons", icon: "fa-solid fa-icons", items: [
      # Arrows & Pointers
      { key: "arrow_right", label: "Arrow Right", file: "sticker_library/icons/arrow-right.svg", tags: "arrow direction pointer right", subcategory: "arrows" },
      { key: "arrow_up_right", label: "Arrow Up Right", file: "sticker_library/icons/arrow-up-right.svg", tags: "arrow direction diagonal up right", subcategory: "arrows" },
      { key: "arrow_down", label: "Arrow Down", file: "sticker_library/icons/arrow-down.svg", tags: "arrow direction down", subcategory: "arrows" },
      { key: "move", label: "Move", file: "sticker_library/icons/move.svg", tags: "move drag arrows cross", subcategory: "arrows" },
      { key: "pointer", label: "Pointer", file: "sticker_library/icons/pointer.svg", tags: "pointer hand cursor click", subcategory: "arrows" },
      { key: "corner_down_right", label: "Corner Down Right", file: "sticker_library/icons/corner-down-right.svg", tags: "arrow corner turn right", subcategory: "arrows" },
      { key: "redo", label: "Redo", file: "sticker_library/icons/redo.svg", tags: "redo forward repeat", subcategory: "arrows" },
      { key: "undo", label: "Undo", file: "sticker_library/icons/undo.svg", tags: "undo back reverse", subcategory: "arrows" },
      { key: "chevron_right", label: "Chevron Right", file: "sticker_library/icons/chevron-right.svg", tags: "chevron arrow right next", subcategory: "arrows" },
      { key: "chevrons_right", label: "Chevrons Right", file: "sticker_library/icons/chevrons-right.svg", tags: "chevrons arrow right fast forward", subcategory: "arrows" },
      { key: "mouse_pointer", label: "Mouse Pointer", file: "sticker_library/icons/mouse-pointer.svg", tags: "mouse pointer cursor click", subcategory: "arrows" },
      { key: "navigation", label: "Navigation", file: "sticker_library/icons/navigation.svg", tags: "navigation compass direction send", subcategory: "arrows" },
      # Checkmarks & Status
      { key: "check", label: "Check", file: "sticker_library/icons/check.svg", tags: "check done complete yes", subcategory: "status" },
      { key: "check_circle", label: "Check Circle", file: "sticker_library/icons/check-circle.svg", tags: "check circle done verified", subcategory: "status" },
      { key: "x", label: "X", file: "sticker_library/icons/x.svg", tags: "x close cancel remove", subcategory: "status" },
      { key: "x_circle", label: "X Circle", file: "sticker_library/icons/x-circle.svg", tags: "x circle close cancel error", subcategory: "status" },
      { key: "alert_triangle", label: "Alert Triangle", file: "sticker_library/icons/alert-triangle.svg", tags: "alert warning triangle caution", subcategory: "status" },
      { key: "alert_circle", label: "Alert Circle", file: "sticker_library/icons/alert-circle.svg", tags: "alert warning circle caution", subcategory: "status" },
      { key: "info", label: "Info", file: "sticker_library/icons/info.svg", tags: "info information help circle", subcategory: "status" },
      { key: "ban", label: "Ban", file: "sticker_library/icons/ban.svg", tags: "ban block forbidden stop", subcategory: "status" },
      { key: "circle_check", label: "Circle Check", file: "sticker_library/icons/circle-check.svg", tags: "circle check verified approved", subcategory: "status" },
      { key: "shield_check", label: "Shield Check", file: "sticker_library/icons/shield-check.svg", tags: "shield check security verified safe", subcategory: "status" },
      # Stars & Ratings
      { key: "star", label: "Star", file: "sticker_library/icons/star.svg", tags: "star favorite rating", subcategory: "stars" },
      { key: "heart", label: "Heart", file: "sticker_library/icons/heart.svg", tags: "heart love favorite like", subcategory: "stars" },
      { key: "thumbs_up", label: "Thumbs Up", file: "sticker_library/icons/thumbs-up.svg", tags: "thumbs up like approve good", subcategory: "stars" },
      { key: "trophy", label: "Trophy", file: "sticker_library/icons/trophy.svg", tags: "trophy award winner prize", subcategory: "stars" },
      { key: "award", label: "Award", file: "sticker_library/icons/award.svg", tags: "award medal prize achievement", subcategory: "stars" },
      { key: "crown", label: "Crown", file: "sticker_library/icons/crown.svg", tags: "crown king queen royal", subcategory: "stars" },
      { key: "medal", label: "Medal", file: "sticker_library/icons/medal.svg", tags: "medal award prize achievement", subcategory: "stars" },
      { key: "gem", label: "Gem", file: "sticker_library/icons/gem.svg", tags: "gem diamond jewel precious", subcategory: "stars" },
      { key: "flame", label: "Flame", file: "sticker_library/icons/flame.svg", tags: "flame fire hot trending", subcategory: "stars" },
      { key: "sparkles", label: "Sparkles", file: "sticker_library/icons/sparkles.svg", tags: "sparkles magic stars shine", subcategory: "stars" },
      # Communication
      { key: "message_circle", label: "Message Circle", file: "sticker_library/icons/message-circle.svg", tags: "message chat bubble circle", subcategory: "communication" },
      { key: "message_square", label: "Message Square", file: "sticker_library/icons/message-square.svg", tags: "message chat bubble square", subcategory: "communication" },
      { key: "phone", label: "Phone", file: "sticker_library/icons/phone.svg", tags: "phone call contact", subcategory: "communication" },
      { key: "mail", label: "Mail", file: "sticker_library/icons/mail.svg", tags: "mail email envelope letter", subcategory: "communication" },
      { key: "bell", label: "Bell", file: "sticker_library/icons/bell.svg", tags: "bell notification alert ring", subcategory: "communication" },
      { key: "send", label: "Send", file: "sticker_library/icons/send.svg", tags: "send paper plane message", subcategory: "communication" },
      { key: "at_sign", label: "At Sign", file: "sticker_library/icons/at-sign.svg", tags: "at sign email mention", subcategory: "communication" },
      { key: "megaphone", label: "Megaphone", file: "sticker_library/icons/megaphone.svg", tags: "megaphone announce speaker loud", subcategory: "communication" },
      { key: "radio", label: "Radio", file: "sticker_library/icons/radio.svg", tags: "radio broadcast signal wave", subcategory: "communication" },
      { key: "podcast", label: "Podcast", file: "sticker_library/icons/podcast.svg", tags: "podcast audio microphone broadcast", subcategory: "communication" },
      # Actions
      { key: "download", label: "Download", file: "sticker_library/icons/download.svg", tags: "download save arrow down", subcategory: "actions" },
      { key: "upload", label: "Upload", file: "sticker_library/icons/upload.svg", tags: "upload arrow up send", subcategory: "actions" },
      { key: "share_2", label: "Share", file: "sticker_library/icons/share-2.svg", tags: "share network social connect", subcategory: "actions" },
      { key: "link", label: "Link", file: "sticker_library/icons/link.svg", tags: "link chain url connect", subcategory: "actions" },
      { key: "external_link", label: "External Link", file: "sticker_library/icons/external-link.svg", tags: "external link open new window", subcategory: "actions" },
      { key: "search", label: "Search", file: "sticker_library/icons/search.svg", tags: "search find magnify glass", subcategory: "actions" },
      { key: "plus", label: "Plus", file: "sticker_library/icons/plus.svg", tags: "plus add new create", subcategory: "actions" },
      { key: "minus", label: "Minus", file: "sticker_library/icons/minus.svg", tags: "minus remove subtract", subcategory: "actions" },
      { key: "copy", label: "Copy", file: "sticker_library/icons/copy.svg", tags: "copy duplicate clone", subcategory: "actions" },
      { key: "clipboard", label: "Clipboard", file: "sticker_library/icons/clipboard.svg", tags: "clipboard paste board", subcategory: "actions" },
      # Media
      { key: "play", label: "Play", file: "sticker_library/icons/play.svg", tags: "play media video start", subcategory: "media" },
      { key: "pause", label: "Pause", file: "sticker_library/icons/pause.svg", tags: "pause media stop", subcategory: "media" },
      { key: "camera", label: "Camera", file: "sticker_library/icons/camera.svg", tags: "camera photo picture", subcategory: "media" },
      { key: "image", label: "Image", file: "sticker_library/icons/image.svg", tags: "image photo picture", subcategory: "media" },
      { key: "video", label: "Video", file: "sticker_library/icons/video.svg", tags: "video camera record", subcategory: "media" },
      { key: "music", label: "Music", file: "sticker_library/icons/music.svg", tags: "music note audio sound", subcategory: "media" },
      { key: "mic", label: "Mic", file: "sticker_library/icons/mic.svg", tags: "mic microphone audio voice", subcategory: "media" },
      { key: "volume_2", label: "Volume", file: "sticker_library/icons/volume-2.svg", tags: "volume sound speaker audio", subcategory: "media" },
      # Commerce
      { key: "shopping_cart", label: "Shopping Cart", file: "sticker_library/icons/shopping-cart.svg", tags: "shopping cart buy store", subcategory: "commerce" },
      { key: "credit_card", label: "Credit Card", file: "sticker_library/icons/credit-card.svg", tags: "credit card payment money", subcategory: "commerce" },
      { key: "dollar_sign", label: "Dollar Sign", file: "sticker_library/icons/dollar-sign.svg", tags: "dollar money currency price", subcategory: "commerce" },
      { key: "tag", label: "Tag", file: "sticker_library/icons/tag.svg", tags: "tag label price sale", subcategory: "commerce" },
      { key: "gift", label: "Gift", file: "sticker_library/icons/gift.svg", tags: "gift present box surprise", subcategory: "commerce" },
      { key: "percent", label: "Percent", file: "sticker_library/icons/percent.svg", tags: "percent discount sale off", subcategory: "commerce" },
      { key: "receipt", label: "Receipt", file: "sticker_library/icons/receipt.svg", tags: "receipt invoice bill", subcategory: "commerce" },
      { key: "wallet", label: "Wallet", file: "sticker_library/icons/wallet.svg", tags: "wallet money payment", subcategory: "commerce" },
      # UI Elements
      { key: "menu", label: "Menu", file: "sticker_library/icons/menu.svg", tags: "menu hamburger bars navigation", subcategory: "ui" },
      { key: "settings", label: "Settings", file: "sticker_library/icons/settings.svg", tags: "settings gear cog preferences", subcategory: "ui" },
      { key: "home", label: "Home", file: "sticker_library/icons/home.svg", tags: "home house main", subcategory: "ui" },
      { key: "user", label: "User", file: "sticker_library/icons/user.svg", tags: "user person profile account", subcategory: "ui" },
      { key: "users", label: "Users", file: "sticker_library/icons/users.svg", tags: "users people group team", subcategory: "ui" },
      { key: "shield", label: "Shield", file: "sticker_library/icons/shield.svg", tags: "shield security protection", subcategory: "ui" },
      { key: "lock", label: "Lock", file: "sticker_library/icons/lock.svg", tags: "lock secure password", subcategory: "ui" },
      { key: "unlock", label: "Unlock", file: "sticker_library/icons/unlock.svg", tags: "unlock open access", subcategory: "ui" },
      { key: "eye", label: "Eye", file: "sticker_library/icons/eye.svg", tags: "eye view visible show", subcategory: "ui" },
      { key: "eye_off", label: "Eye Off", file: "sticker_library/icons/eye-off.svg", tags: "eye off hide invisible", subcategory: "ui" },
      # Charts & Data
      { key: "bar_chart_2", label: "Bar Chart", file: "sticker_library/icons/bar-chart-2.svg", tags: "bar chart graph data stats", subcategory: "charts" },
      { key: "trending_up", label: "Trending Up", file: "sticker_library/icons/trending-up.svg", tags: "trending up growth increase", subcategory: "charts" },
      { key: "trending_down", label: "Trending Down", file: "sticker_library/icons/trending-down.svg", tags: "trending down decline decrease", subcategory: "charts" },
      { key: "pie_chart", label: "Pie Chart", file: "sticker_library/icons/pie-chart.svg", tags: "pie chart graph data", subcategory: "charts" },
      { key: "activity", label: "Activity", file: "sticker_library/icons/activity.svg", tags: "activity pulse heartbeat", subcategory: "charts" },
      { key: "signal", label: "Signal", file: "sticker_library/icons/signal.svg", tags: "signal bars strength", subcategory: "charts" },
      { key: "gauge", label: "Gauge", file: "sticker_library/icons/gauge.svg", tags: "gauge meter speed", subcategory: "charts" },
      { key: "database", label: "Database", file: "sticker_library/icons/database.svg", tags: "database storage server", subcategory: "charts" },
      # Devices
      { key: "smartphone", label: "Smartphone", file: "sticker_library/icons/smartphone.svg", tags: "smartphone phone mobile device", subcategory: "devices" },
      { key: "tablet", label: "Tablet", file: "sticker_library/icons/tablet.svg", tags: "tablet ipad device", subcategory: "devices" },
      { key: "monitor", label: "Monitor", file: "sticker_library/icons/monitor.svg", tags: "monitor screen display desktop", subcategory: "devices" },
      { key: "laptop", label: "Laptop", file: "sticker_library/icons/laptop.svg", tags: "laptop computer notebook", subcategory: "devices" },
      { key: "wifi", label: "Wifi", file: "sticker_library/icons/wifi.svg", tags: "wifi wireless internet", subcategory: "devices" },
      { key: "bluetooth", label: "Bluetooth", file: "sticker_library/icons/bluetooth.svg", tags: "bluetooth wireless connect", subcategory: "devices" },
      { key: "cpu", label: "CPU", file: "sticker_library/icons/cpu.svg", tags: "cpu processor chip hardware", subcategory: "devices" },
      { key: "cloud", label: "Cloud", file: "sticker_library/icons/cloud.svg", tags: "cloud server storage", subcategory: "devices" },
      # Nature & Misc
      { key: "zap", label: "Zap", file: "sticker_library/icons/zap.svg", tags: "zap lightning bolt energy", subcategory: "nature" },
      { key: "rocket", label: "Rocket", file: "sticker_library/icons/rocket.svg", tags: "rocket launch fast speed", subcategory: "nature" },
      { key: "target", label: "Target", file: "sticker_library/icons/target.svg", tags: "target goal aim focus", subcategory: "nature" },
      { key: "globe", label: "Globe", file: "sticker_library/icons/globe.svg", tags: "globe world earth international", subcategory: "nature" },
      { key: "sun", label: "Sun", file: "sticker_library/icons/sun.svg", tags: "sun light bright day", subcategory: "nature" },
      { key: "moon", label: "Moon", file: "sticker_library/icons/moon.svg", tags: "moon night dark", subcategory: "nature" },
      { key: "compass", label: "Compass", file: "sticker_library/icons/compass.svg", tags: "compass direction navigate", subcategory: "nature" },
      { key: "map_pin", label: "Map Pin", file: "sticker_library/icons/map-pin.svg", tags: "map pin location marker", subcategory: "nature" },
      { key: "clock", label: "Clock", file: "sticker_library/icons/clock.svg", tags: "clock time watch", subcategory: "nature" },
      { key: "calendar", label: "Calendar", file: "sticker_library/icons/calendar.svg", tags: "calendar date schedule", subcategory: "nature" },
      # Social
      { key: "github", label: "GitHub", file: "sticker_library/icons/github.svg", tags: "github code dev social", subcategory: "social" },
      { key: "twitter", label: "Twitter", file: "sticker_library/icons/twitter.svg", tags: "twitter social media bird", subcategory: "social" },
      { key: "instagram", label: "Instagram", file: "sticker_library/icons/instagram.svg", tags: "instagram social media photo", subcategory: "social" },
      { key: "youtube", label: "YouTube", file: "sticker_library/icons/youtube.svg", tags: "youtube video social media", subcategory: "social" },
      { key: "linkedin", label: "LinkedIn", file: "sticker_library/icons/linkedin.svg", tags: "linkedin social professional", subcategory: "social" },
      { key: "facebook", label: "Facebook", file: "sticker_library/icons/facebook.svg", tags: "facebook social media", subcategory: "social" },
      { key: "twitch", label: "Twitch", file: "sticker_library/icons/twitch.svg", tags: "twitch streaming gaming social", subcategory: "social" },
      { key: "dribbble", label: "Dribbble", file: "sticker_library/icons/dribbble.svg", tags: "dribbble design social portfolio", subcategory: "social" }
    ] },
    badges: { label: "Trust Badges", icon: "fa-solid fa-award", items: [
      { key: "editors_choice", label: "Editor's Choice", file: "sticker_library/badges/editors_choice.svg", tags: "editor choice award featured" },
      { key: "number_one_app", label: "#1 App", file: "sticker_library/badges/number_one_app.svg", tags: "number one top best first" },
      { key: "app_of_the_day", label: "App of the Day", file: "sticker_library/badges/app_of_the_day.svg", tags: "app day featured spotlight" },
      { key: "top_rated", label: "Top Rated", file: "sticker_library/badges/top_rated.svg", tags: "top rated best stars review" },
      { key: "best_of_year", label: "Best of Year", file: "sticker_library/badges/best_of_year.svg", tags: "best year annual award" },
      { key: "featured", label: "Featured", file: "sticker_library/badges/featured.svg", tags: "featured spotlight highlight" },
      { key: "staff_pick", label: "Staff Pick", file: "sticker_library/badges/staff_pick.svg", tags: "staff pick curated recommended" },
      { key: "trending", label: "Trending", file: "sticker_library/badges/trending.svg", tags: "trending popular hot rising" },
      { key: "highly_recommended", label: "Highly Recommended", file: "sticker_library/badges/highly_recommended.svg", tags: "highly recommended approved trusted" },
      { key: "five_star_rated", label: "5-Star Rated", file: "sticker_library/badges/five_star_rated.svg", tags: "five star rated review perfect" }
    ] },
    ui_elements: { label: "UI Elements", icon: "fa-solid fa-toggle-on", items: [
      { key: "pill_badge", label: "Pill Badge", file: "sticker_library/ui_elements/pill_badge.svg", tags: "pill badge label tag" },
      { key: "star_rating_5", label: "5 Stars", file: "sticker_library/ui_elements/star_rating_5.svg", tags: "star rating five review" },
      { key: "star_rating_4", label: "4 Stars", file: "sticker_library/ui_elements/star_rating_4.svg", tags: "star rating four review" },
      { key: "star_rating_3", label: "3 Stars", file: "sticker_library/ui_elements/star_rating_3.svg", tags: "star rating three review" },
      { key: "notification_dot", label: "Notification Dot", file: "sticker_library/ui_elements/notification_dot.svg", tags: "notification dot badge alert" },
      { key: "toggle_on", label: "Toggle On", file: "sticker_library/ui_elements/toggle_on.svg", tags: "toggle switch on enabled" },
      { key: "progress_bar", label: "Progress Bar", file: "sticker_library/ui_elements/progress_bar.svg", tags: "progress bar loading status" },
      { key: "download_badge", label: "Download Badge", file: "sticker_library/ui_elements/download_badge.svg", tags: "download badge button get" }
    ] }
  }.freeze

  TEMPLATE_KEYS = TEMPLATES.keys.freeze

  validates :template, inclusion: { in: TEMPLATE_KEYS }, allow_nil: true

  def self.exports_root
    Rails.root.join("storage", "screenshot_exports")
  end

  def exports_directory
    self.class.exports_root.join(export_path_component(organization_id, "organization_id"), export_path_component(id, "id"))
  end

  def ensure_resolution_directory!(width:, height:)
    resolution_dir = verified_export_path(exports_directory.join("#{Integer(width)}x#{Integer(height)}"))
    resolution_dir.mkpath
    resolution_dir
  end

  def clear_exports_directory!
    dir = verified_export_path(exports_directory)
    dir.rmtree if dir.exist?
    dir
  end

  # Total export storage used by this organization across all projects (cached 60s)
  def self.org_export_storage_bytes(organization_id, use_cache: true)
    return compute_org_export_storage_bytes(organization_id) unless use_cache

    Rails.cache.fetch("org_export_storage:#{organization_id}", expires_in: 60.seconds) do
      compute_org_export_storage_bytes(organization_id)
    end
  end

  def self.invalidate_export_quota_cache!(organization_id)
    Rails.cache.delete("org_export_storage:#{organization_id}")
  end

  def self.org_media_storage_bytes(organization_id, use_cache: true)
    return compute_org_media_storage_bytes(organization_id) unless use_cache

    Rails.cache.fetch("org_media_storage:#{organization_id}", expires_in: 60.seconds) do
      compute_org_media_storage_bytes(organization_id)
    end
  end

  def self.invalidate_media_quota_cache!(organization_id)
    Rails.cache.delete("org_media_storage:#{organization_id}")
  end

  def org_within_export_quota?(additional_bytes = 0, use_cache: true)
    current = self.class.org_export_storage_bytes(organization_id, use_cache: use_cache)
    (current + additional_bytes) <= max_export_storage_bytes_per_organization
  end

  def org_within_media_quota?(additional_bytes = 0, use_cache: true)
    current = self.class.org_media_storage_bytes(organization_id, use_cache: use_cache)
    (current + additional_bytes) <= max_media_storage_bytes_per_organization
  end

  def max_export_storage_bytes_per_organization
    organization.entitlements.max_export_storage_bytes_per_organization
  end

  def max_media_storage_bytes_per_organization
    organization.entitlements.max_media_storage_bytes_per_organization
  end

  def export_storage_bytes
    dir = exports_directory
    return 0 unless dir.exist?

    dir.glob("**/*").sum { |f| f.file? ? f.size : 0 }
  end

  def self.template_settings(key)
    settings = TEMPLATES.dig(key, :settings) || DEFAULT_TEXT_SETTINGS
    settings.except("default_stickers")
  end

  EXPORT_PRESETS = {
    "ios_required" => [
      { label: "iPhone 6.9\" (1320x2868)", width: 1320, height: 2868, device_frame: "iphone_16_pro_max" },
      { label: "iPhone 6.7\" (1290x2796)", width: 1290, height: 2796, device_frame: "iphone_15_pro_max" },
      { label: "iPhone 6.5\" (1242x2688)", width: 1242, height: 2688, device_frame: "iphone_11_pro_max" }
    ],
    "ios_optional" => [
      { label: "iPhone 5.5\" (1242x2208)", width: 1242, height: 2208, device_frame: "iphone_8_plus" }
    ],
    "ios_ipad" => [
      { label: "iPad 12.9\" (2048x2732)", width: 2048, height: 2732, device_frame: "ipad_pro_129" },
      { label: "iPad 11\" (1668x2388)", width: 1668, height: 2388, device_frame: "ipad_pro_11" }
    ],
    "android_phone" => [
      { label: "Phone (1080x1920)", width: 1080, height: 1920, device_frame: "generic_phone" }
    ],
    "android_tablet_7" => [
      { label: "7\" Tablet (1200x1920)", width: 1200, height: 1920, device_frame: "generic_tablet_7" }
    ],
    "android_tablet_10" => [
      { label: "10\" Tablet (1600x2560)", width: 1600, height: 2560, device_frame: "generic_tablet_10" }
    ]
  }.freeze

  private

  def self.compute_org_export_storage_bytes(organization_id)
    local_bytes = 0
    org_dir = exports_root.join(organization_id.to_s)
    if org_dir.exist?
      org_dir.glob("**/*").each do |f|
        local_bytes += f.size if f.file?
      end
    end
    cloud_bytes = ScreenshotExport.org_cloud_export_storage_bytes(organization_id)
    local_bytes + cloud_bytes
  end
  private_class_method :compute_org_export_storage_bytes

  def self.compute_org_media_storage_bytes(organization_id)
    project_attachment_bytes = ActiveStorage::Attachment
      .joins(:blob)
      .joins("INNER JOIN screenshot_projects ON screenshot_projects.id = active_storage_attachments.record_id")
      .where(record_type: "ScreenshotProject")
      .where(name: [ "background_image", "custom_sticker_images" ])
      .where(screenshot_projects: { organization_id: organization_id })
      .sum("active_storage_blobs.byte_size")

    scene_attachment_bytes = ActiveStorage::Attachment
      .joins(:blob)
      .joins("INNER JOIN screenshot_scenes ON screenshot_scenes.id = active_storage_attachments.record_id")
      .joins("INNER JOIN screenshot_projects ON screenshot_projects.id = screenshot_scenes.screenshot_project_id")
      .where(record_type: "ScreenshotScene", name: "source_image")
      .where(screenshot_projects: { organization_id: organization_id })
      .sum("active_storage_blobs.byte_size")

    # Keep legacy binary-scene images in the accounting as well.
    legacy_scene_bytes = ScreenshotScene
      .joins(:screenshot_project)
      .where(screenshot_projects: { organization_id: organization_id })
      .where.not(source_image_data: nil)
      .sum(Arel.sql("octet_length(source_image_data)"))

    project_attachment_bytes + scene_attachment_bytes + legacy_scene_bytes.to_i
  end
  private_class_method :compute_org_media_storage_bytes

  def cleanup_export_files
    clear_exports_directory!
    self.class.invalidate_export_quota_cache!(organization_id)
    self.class.invalidate_media_quota_cache!(organization_id)
  end

  def export_path_component(value, attribute_name)
    component = value.to_s
    raise SecurityError, "Unsafe export path: #{attribute_name} must be numeric" unless component.match?(/\A\d+\z/)

    component
  end

  def verified_export_path(path)
    root = self.class.exports_root.expand_path.to_s
    expanded = path.expand_path.to_s
    return Pathname.new(expanded) if expanded == root || expanded.start_with?("#{root}/")

    raise SecurityError, "Unsafe export path escaped exports root"
  end
end
