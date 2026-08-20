# UiHelper — MySigner Design System (canonical visual class strings)
# ──────────────────────────────────────────────────────────────────────
#
# Single source of truth for every reusable UI pattern in the
# authenticated app. Every partial, every Stimulus-built DOM element,
# every future feature sources its button/card/badge/input/banner from
# here. Drift = design debt.
#
# The five decision rules for future devs:
#
#   1. Authenticated view needs a button, input, badge, card, label, or
#      notification banner? → Use a helper method. If the method doesn't
#      exist, add it to this file before using an inline class string.
#
#   2. DaisyUI structural chrome (sidebar .menu, .drawer, .modal shell,
#      .dropdown shell, .stats, .mockup-*, .hero, .divider, .loading
#      spinner)? → Raw DaisyUI. The theme radii make them consistent.
#
#   3. Landing page, onboarding wizard picker, or marketing section
#      that legitimately needs big friendly radii? → Raw Tailwind with
#      explicit rounded-full / rounded-2xl / rounded-3xl. These sections
#      are ALLOWED to diverge from the authenticated-app aesthetic.
#
#   4. Layout/spacing (flex, gap, px, py, mt)? → Always inline.
#      Semantic visual identity (colors, radii, borders, backgrounds)?
#      → Always the helper (or extend the helper).
#
#   5. Any class string used in 2+ places? → Extract a constant and a
#      method here. Cost of adding a helper method: one minute.
#      Cost of visual drift: months of inconsistency.
#
# ──────────────────────────────────────────────────────────────────────
#
# Theme tokens (see app/assets/tailwind/application.css):
#   --radius-field: 0.5rem    → .btn, .input, .select, .textarea
#   --radius-box:   0.875rem  → .card, .modal-box, .alert, .dropdown-content
#   --radius-selector: 2rem   → .badge, .checkbox, .toggle, .range (unchanged to keep pill/circular)
#   --border: 1px             → DaisyUI component borders
#
# Color tokens used (all resolve per theme):
#   - base-100/200/300/content: page + neutral surfaces
#   - primary (lavender dark / pink-magenta light)
#   - success, warning, error, info (semantic)
#   - --color-cat-new / --color-cat-improved / --color-cat-fixed:
#     off-token green/blue/amber for status categories (Live/Improved/Review).
#     Same value in both themes (deliberate brand colours).
#
# JS mirrors: some constants are duplicated in Stimulus controllers that
# build DOM at runtime. Each mirrored constant is marked with a
# "JS MIRROR" comment. Any change here must be reflected in the
# corresponding controller in the same commit:
#
# - app/javascript/controllers/release_note_editor_controller.js — static INPUT_CLASSES
# - app/javascript/controllers/store_listing_sync_controller.js  — static SN_* constants
# - app/javascript/controllers/keyword_editor_controller.js      — KW_TAG, KW_CHIP_AVAILABLE/STAGED/TOO_LONG (all mirror Ruby); KW_TAG_DISABLED (JS-only: "already in use" chip has no server-rendered equivalent)
#
module UiHelper
  # ─────────────────────────────────────── Card container + header ────

  CARD_CONTAINER = "border border-base-content/[0.06] rounded-[0.875rem] bg-base-content/[0.02] overflow-hidden".freeze
  CARD_HEADER = "flex items-center gap-2.5 px-5 py-[0.875rem] border-b border-base-content/[0.04]".freeze
  CARD_HEADER_SPLIT = "flex items-center justify-between gap-2.5 px-5 py-[0.875rem] border-b border-base-content/[0.04]".freeze
  CARD_BODY = "p-5".freeze
  CARD_ICON = "flex items-center justify-center w-7 h-7 rounded-md bg-primary/[0.08] text-primary/50 text-xs shrink-0".freeze
  CARD_TITLE = "text-[0.8125rem] font-bold tracking-[-0.01em] text-base-content/70".freeze

  def card_container_classes = CARD_CONTAINER
  def card_header_classes = CARD_HEADER
  def card_header_split_classes = CARD_HEADER_SPLIT
  def card_body_classes = CARD_BODY
  def card_icon_classes = CARD_ICON
  def card_title_classes = CARD_TITLE

  # ─────────────────────────────────────────────────────── Buttons ────
  # JS MIRROR: release_note_editor_controller.js (via INPUT_CLASSES for bullet inputs)
  # JS MIRROR: store_listing_sync_controller.js (SN_* constants for banner builder)

  BTN_BASE = "inline-flex items-center gap-1.5 text-[0.8125rem] font-semibold px-4 py-2 rounded-lg border border-transparent cursor-pointer transition-all duration-150 whitespace-nowrap leading-tight disabled:opacity-50 disabled:cursor-not-allowed".freeze
  BTN_SM_MOD = "text-xs px-3 py-[0.375rem]".freeze
  BTN_XS_MOD = "text-[0.6875rem] px-2 py-1 gap-1 rounded-md".freeze
  BTN_PRIMARY = "bg-primary text-primary-content border-primary hover:bg-primary/90".freeze
  BTN_SUCCESS = "bg-success/[0.12] text-success border-success/20 hover:bg-success/20".freeze
  BTN_DESTRUCTIVE = "bg-error/[0.10] text-error border-error/20 hover:bg-error/20".freeze
  BTN_GHOST = "bg-transparent text-base-content/60 border-base-content/[0.1] hover:bg-base-content/5 hover:text-base-content/85 hover:border-base-content/15".freeze
  BTN_ACCENT = "bg-accent/[0.12] text-accent border-accent/20 hover:bg-accent/20".freeze

  def btn_base_classes = BTN_BASE
  def btn_primary_classes = "#{BTN_BASE} #{BTN_PRIMARY}"
  def btn_primary_sm_classes = "#{BTN_BASE} #{BTN_SM_MOD} #{BTN_PRIMARY}"
  def btn_success_classes = "#{BTN_BASE} #{BTN_SUCCESS}"
  def btn_success_sm_classes = "#{BTN_BASE} #{BTN_SM_MOD} #{BTN_SUCCESS}"
  def btn_destructive_classes = "#{BTN_BASE} #{BTN_DESTRUCTIVE}"
  def btn_destructive_sm_classes = "#{BTN_BASE} #{BTN_SM_MOD} #{BTN_DESTRUCTIVE}"
  def btn_ghost_classes = "#{BTN_BASE} #{BTN_GHOST}"
  def btn_ghost_sm_classes = "#{BTN_BASE} #{BTN_SM_MOD} #{BTN_GHOST}"
  def btn_ghost_xs_classes = "#{BTN_BASE} #{BTN_XS_MOD} #{BTN_GHOST}"
  def btn_accent_classes = "#{BTN_BASE} #{BTN_ACCENT}"
  def btn_accent_sm_classes = "#{BTN_BASE} #{BTN_SM_MOD} #{BTN_ACCENT}"

  # Square icon-only buttons (close buttons, expand/collapse, icon toolbars).
  # Default 32px square, sm 28px square. Both get a subtle hover tint.
  ICON_BTN = "inline-flex items-center justify-center w-8 h-8 rounded-lg text-base-content/50 hover:text-base-content/85 hover:bg-base-content/[0.05] transition-all cursor-pointer".freeze
  ICON_BTN_SM = "inline-flex items-center justify-center w-7 h-7 rounded-md text-base-content/50 hover:text-base-content/85 hover:bg-base-content/[0.05] transition-all cursor-pointer".freeze

  def icon_btn_classes = ICON_BTN
  def icon_btn_sm_classes = ICON_BTN_SM

  # ────────────────────────────────────────────── Badges + labels ────

  STATUS_BADGE_BASE = "inline-flex items-center gap-1 text-[0.6875rem] font-semibold px-2 py-[0.2rem] rounded-md border".freeze
  STATUS_LIVE = "bg-[var(--color-cat-new)/0.1] text-[var(--color-cat-new)] border-[var(--color-cat-new)/0.15]".freeze
  STATUS_REVIEW = "bg-[var(--color-cat-fixed)/0.1] text-[var(--color-cat-fixed)] border-[var(--color-cat-fixed)/0.15]".freeze
  STATUS_DRAFT = "bg-base-content/[0.06] text-base-content/45 border-base-content/[0.1]".freeze
  STATUS_REJECTED = "bg-error/[0.1] text-error border-error/[0.15]".freeze

  VERSION_BADGE = "inline-flex items-center gap-1 text-xs font-bold px-[0.6rem] py-[0.2rem] rounded-md bg-primary/[0.1] text-primary/85 border border-primary/[0.12] tabular-nums".freeze
  PLATFORM_BADGE = "inline-flex items-center gap-[0.3rem] text-[0.6875rem] font-semibold px-2 py-[0.2rem] rounded-md bg-base-content/[0.06] text-base-content/55 border border-base-content/[0.06]".freeze
  LOCALE_BADGE = "inline-flex items-center text-[0.625rem] font-semibold uppercase tracking-[0.04em] px-[0.4rem] py-[0.1rem] rounded bg-base-content/[0.06] text-base-content/55 border border-base-content/[0.06]".freeze
  MUTED_BADGE = "inline-flex items-center text-[0.625rem] font-semibold uppercase tracking-[0.04em] px-[0.4rem] py-[0.1rem] rounded bg-base-content/[0.06] text-base-content/40".freeze
  COUNT_BADGE = "text-[0.625rem] font-semibold px-[0.4rem] py-[0.1rem] rounded-full bg-base-content/[0.06] text-base-content/40".freeze
  PRO_BADGE = "inline-flex items-center gap-[0.3rem] text-[0.6rem] font-bold uppercase tracking-[0.06em] px-[0.35rem] py-[0.1rem] rounded bg-primary/[0.1] text-primary/70 border border-primary/[0.15]".freeze

  def status_badge_classes(state)
    variant = case state&.to_s
    when "live", "published", "applied", "READY_FOR_SALE" then STATUS_LIVE
    when "in_review", "submitted", "pending_review", "WAITING_FOR_REVIEW", "IN_REVIEW" then STATUS_REVIEW
    when "rejected", "REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY", "removed" then STATUS_REJECTED
    else STATUS_DRAFT
    end
    "#{STATUS_BADGE_BASE} #{variant}"
  end

  def status_badge_base_classes = STATUS_BADGE_BASE
  def status_live_classes = STATUS_LIVE
  def status_review_classes = STATUS_REVIEW
  def status_draft_classes = STATUS_DRAFT
  def version_badge_classes = VERSION_BADGE
  def platform_badge_classes = PLATFORM_BADGE
  def locale_badge_classes = LOCALE_BADGE
  def muted_badge_classes = MUTED_BADGE
  def count_badge_classes = COUNT_BADGE
  def pro_badge_classes = PRO_BADGE

  def pro_badge_html
    content_tag(:span, class: PRO_BADGE) do
      safe_join([ content_tag(:i, "", class: "fa-solid fa-crown text-[0.5rem]"), " Pro" ])
    end
  end

  # ───────────────────────────────────────────────────── Typography ────

  LABEL_UPPERCASE = "text-[0.6875rem] font-semibold uppercase tracking-[0.06em] text-base-content/35".freeze
  LABEL_FORM = "block text-[0.8125rem] font-semibold text-base-content/70 tracking-[-0.005em]".freeze
  FIELD_TEXT = "text-sm leading-relaxed text-base-content/80".freeze
  META_TEXT = "text-xs text-base-content/40".freeze
  HINT_TEXT = "text-xs text-base-content/35".freeze
  ERROR_TEXT = "flex items-center gap-1 text-xs font-medium text-error/90".freeze
  PANEL_TITLE = "flex items-center gap-1.5 text-[0.8125rem] font-bold text-base-content/60".freeze

  def label_uppercase_classes = LABEL_UPPERCASE
  def label_form_classes = LABEL_FORM
  def field_text_classes = FIELD_TEXT
  def meta_text_classes = META_TEXT
  def hint_text_classes = HINT_TEXT
  def error_text_classes = ERROR_TEXT
  def panel_title_classes = PANEL_TITLE

  # ────────────────────────────────────────────── Form inputs + hints ────
  # JS MIRROR: release_note_editor_controller.js :: static INPUT_CLASSES
  # Keep these two values in sync.

  INPUT = "block w-full text-sm leading-relaxed px-3 py-2 rounded-lg border border-base-content/[0.1] bg-base-content/[0.03] text-base-content/85 outline-none transition-[border-color,box-shadow,background] duration-150 hover:border-base-content/15 focus:border-primary/40 focus:bg-base-content/[0.05] focus:shadow-[0_0_0_3px_oklch(var(--color-primary)/0.08)]".freeze
  INPUT_ERROR_EXTRA = "border-error/40 shadow-[0_0_0_3px_oklch(var(--color-error)/0.08)]".freeze

  def input_field_classes = INPUT
  def input_error_extra_classes = INPUT_ERROR_EXTRA
  def textarea_field_classes = "#{INPUT} resize-y min-h-12"

  # ──────────────────────────────────────── Char counter + progress ────

  def char_badge_classes(count, limit)
    base = "inline-flex items-center text-[0.625rem] font-semibold tabular-nums px-[0.4rem] py-[0.1rem] rounded"
    return "#{base} bg-base-content/[0.04] text-base-content/30" if limit.nil? || limit.zero?
    over = count > limit
    warn = count > limit * 0.9 && !over
    variant =
      if over then "bg-error/[0.12] text-error/90 font-bold"
      elsif warn then "bg-warning/10 text-warning/80"
      else "bg-base-content/[0.04] text-base-content/30"
      end
    "#{base} #{variant}"
  end

  PROGRESS_TRACK = "h-[3px] rounded-[2px] bg-base-content/[0.06] overflow-hidden".freeze
  def progress_track_classes = PROGRESS_TRACK

  def progress_fill_classes(count, limit)
    base = "h-full rounded-[2px] transition-[width,background] duration-200"
    return "#{base} bg-primary/35" if limit.nil? || limit.zero?
    over = count > limit
    pct = (count.to_f / limit * 100).clamp(0, 100)
    if over then "#{base} bg-error/70"
    elsif pct > 90 then "#{base} bg-warning/60"
    else "#{base} bg-primary/35"
    end
  end

  # ─────────────────────────────────────────────── Empty state ────────

  EMPTY_STATE = "flex flex-col items-center justify-center text-center min-h-[40vh] p-12 border border-dashed border-base-content/[0.08] rounded-2xl".freeze
  EMPTY_STATE_ICON = "flex items-center justify-center w-16 h-16 rounded-full bg-primary/[0.08] text-primary/50 mb-5".freeze
  EMPTY_STATE_TITLE = "text-xl font-bold text-base-content/80 mb-2".freeze
  EMPTY_STATE_TEXT = "text-sm text-base-content/45 max-w-[28rem] leading-relaxed mb-6".freeze
  EMPTY_INLINE = "inline-flex items-center gap-1.5 text-[0.8125rem] text-base-content/30 italic".freeze

  def empty_state_classes = EMPTY_STATE
  def empty_state_icon_classes = EMPTY_STATE_ICON
  def empty_state_title_classes = EMPTY_STATE_TITLE
  def empty_state_text_classes = EMPTY_STATE_TEXT
  def empty_inline_classes = EMPTY_INLINE

  # ──────────────────────────────────────── Notification banners ──────
  # JS MIRROR: store_listing_sync_controller.js :: SN_* static constants

  SN_BASE = "relative rounded-[0.625rem] px-3 py-[0.625rem] border overflow-hidden".freeze
  SN_WARNING = "#{SN_BASE} border-warning/20 bg-warning/[0.06]".freeze
  SN_ERROR = "#{SN_BASE} border-error/20 bg-error/[0.06]".freeze
  SN_SUCCESS = "#{SN_BASE} border-success/20 bg-success/[0.06]".freeze
  SN_INFO = "#{SN_BASE} border-info/15 bg-info/[0.04]".freeze
  SN_MODIFIED = "#{SN_BASE} border-warning/15 bg-warning/[0.04]".freeze
  SN_NEUTRAL = "#{SN_BASE} border-base-content/[0.08] bg-base-content/[0.03]".freeze
  SN_LOADING = "#{SN_BASE} border-primary/[0.12] bg-primary/[0.04] animate-pulse".freeze

  SN_ICON_BASE = "flex items-center justify-center w-5 h-5 rounded-full shrink-0".freeze
  SN_ICON_WARNING = "#{SN_ICON_BASE} bg-warning/15 text-warning".freeze
  SN_ICON_ERROR = "#{SN_ICON_BASE} bg-error/15 text-error".freeze
  SN_ICON_SUCCESS = "#{SN_ICON_BASE} bg-success/15 text-success".freeze
  SN_ICON_INFO = "#{SN_ICON_BASE} bg-info/15 text-info".freeze
  SN_ICON_MODIFIED = "#{SN_ICON_BASE} bg-warning/[0.12] text-warning/80".freeze
  SN_ICON_NEUTRAL = "#{SN_ICON_BASE} bg-base-content/[0.08] text-base-content/50".freeze

  SN_CLOSE = "flex items-center justify-center w-5 h-5 rounded text-base-content/30 hover:text-base-content/70 hover:bg-base-content/[0.06] transition-all text-[0.625rem] cursor-pointer".freeze
  SN_PROGRESS_BASE = "absolute bottom-0 left-0 h-[2px] w-full rounded-b-[0.625rem] origin-left animate-[sn-countdown_linear_forwards]".freeze

  def sn_base_classes = SN_BASE
  def sn_warning_classes = SN_WARNING
  def sn_error_classes = SN_ERROR
  def sn_success_classes = SN_SUCCESS
  def sn_info_classes = SN_INFO
  def sn_modified_classes = SN_MODIFIED
  def sn_neutral_classes = SN_NEUTRAL
  def sn_loading_classes = SN_LOADING
  def sn_icon_warning_classes = SN_ICON_WARNING
  def sn_icon_error_classes = SN_ICON_ERROR
  def sn_icon_success_classes = SN_ICON_SUCCESS
  def sn_icon_info_classes = SN_ICON_INFO
  def sn_icon_modified_classes = SN_ICON_MODIFIED
  def sn_icon_neutral_classes = SN_ICON_NEUTRAL
  def sn_close_classes = SN_CLOSE
  def sn_progress_base_classes = SN_PROGRESS_BASE

  # ─────────────────────────────────────────── Tabs (main + sub) ──────

  TAB_BASE = "inline-flex items-center gap-[0.4rem] px-4 py-[0.625rem] text-[0.8125rem] font-semibold border-b-2 -mb-px whitespace-nowrap transition-colors duration-150".freeze
  TAB_INACTIVE = "#{TAB_BASE} text-base-content/45 border-transparent hover:text-base-content/85 hover:border-base-content/15".freeze
  TAB_ACTIVE = "#{TAB_BASE} text-primary border-primary hover:text-primary hover:border-primary".freeze

  SUBTAB_BASE = "inline-flex items-center gap-1 px-3 py-1.5 text-xs font-semibold border-b-2 -mb-px transition-colors".freeze
  SUBTAB_INACTIVE = "#{SUBTAB_BASE} text-base-content/40 border-transparent hover:text-base-content/75".freeze
  SUBTAB_ACTIVE = "#{SUBTAB_BASE} text-base-content/95 border-base-content/50".freeze

  TAB_BAR = "flex items-center gap-[0.125rem] border-b border-base-content/[0.08] mb-5 overflow-x-auto scrollbar-none".freeze
  SUBTAB_BAR = "flex items-center gap-[0.125rem] border-b border-base-content/[0.05] mb-4 overflow-x-auto scrollbar-none".freeze

  def tab_bar_classes = TAB_BAR
  def tab_active_classes = TAB_ACTIVE
  def tab_inactive_classes = TAB_INACTIVE
  def subtab_bar_classes = SUBTAB_BAR
  def subtab_active_classes = SUBTAB_ACTIVE
  def subtab_inactive_classes = SUBTAB_INACTIVE

  # ─────────────────────────────────── Keyword rank badges ────

  KEYWORD_RANK_BADGE = "inline-flex items-center text-[0.6875rem] font-semibold tabular-nums px-2 py-[0.2rem] rounded-md border".freeze
  KW_RANK_TOP10 = "bg-[var(--color-cat-new)/0.1] text-[var(--color-cat-new)] border-[var(--color-cat-new)/0.15]".freeze
  KW_RANK_TOP50 = "bg-[var(--color-cat-improved)/0.1] text-[var(--color-cat-improved)] border-[var(--color-cat-improved)/0.15]".freeze
  KW_RANK_BELOW50 = "bg-base-content/[0.06] text-base-content/45 border-base-content/[0.1]".freeze
  KW_NOT_RANKED = "bg-base-content/[0.04] text-base-content/30 border-base-content/[0.06]".freeze

  def keyword_rank_badge_classes(rank)
    variant = if rank.nil? then KW_NOT_RANKED
    elsif rank <= 10 then KW_RANK_TOP10
    elsif rank <= 50 then KW_RANK_TOP50
    else KW_RANK_BELOW50
    end
    "#{KEYWORD_RANK_BADGE} #{variant}"
  end

  KW_TAG = "inline-flex items-center gap-1 text-xs font-medium px-2 py-[0.25rem] rounded-md bg-primary/[0.08] text-primary/80 border border-primary/[0.1]".freeze
  KW_TAG_WARN = "inline-flex items-center gap-1 text-xs font-medium px-2 py-[0.25rem] rounded-md bg-warning/[0.1] text-warning/80 border border-warning/[0.15]".freeze

  def kw_tag_classes = KW_TAG
  def kw_tag_warn_classes = KW_TAG_WARN

  # --- Keyword-suggestion chip state helpers ---

  KW_CHIP_AVAILABLE = "inline-flex items-center gap-1 text-xs font-medium px-2 py-[0.25rem] rounded-md bg-primary/[0.08] text-primary/80 border border-primary/[0.1] cursor-pointer hover:bg-primary/[0.15] transition-colors"
  KW_CHIP_STAGED    = "inline-flex items-center gap-1 text-xs font-medium px-2 py-[0.25rem] rounded-md bg-success/[0.12] text-success/90 border border-success/30 cursor-pointer"
  KW_CHIP_TOO_LONG  = "inline-flex items-center gap-1 text-xs font-medium px-2 py-[0.25rem] rounded-md bg-base-content/[0.02] text-base-content/35 border border-dashed border-base-content/[0.12] cursor-not-allowed"

  def kw_chip_available_classes; KW_CHIP_AVAILABLE; end
  def kw_chip_staged_classes;    KW_CHIP_STAGED; end
  def kw_chip_too_long_classes;  KW_CHIP_TOO_LONG; end

  # --- Budget-bar segment helpers ---

  BUDGET_SEGMENT_CURRENT = "bg-primary/70 transition-[width] duration-150"
  BUDGET_SEGMENT_STAGED  = "bg-success/70 transition-[width] duration-150"

  def budget_segment_current_classes; BUDGET_SEGMENT_CURRENT; end
  def budget_segment_staged_classes;  BUDGET_SEGMENT_STAGED; end

  # --- Scratchpad row helpers ---

  SCRATCHPAD_ROW = "flex items-center gap-3 px-3 py-2 rounded-lg bg-base-content/[0.03] border border-base-content/[0.05]"

  def scratchpad_row_classes; SCRATCHPAD_ROW; end

  # ─────────────────────────────────── Sentiment badges ────

  SENTIMENT_POSITIVE = "#{STATUS_BADGE_BASE} bg-[var(--color-cat-new)/0.1] text-[var(--color-cat-new)] border-[var(--color-cat-new)/0.15]".freeze
  SENTIMENT_NEGATIVE = "#{STATUS_BADGE_BASE} bg-error/[0.1] text-error border-error/[0.15]".freeze
  SENTIMENT_NEUTRAL  = "#{STATUS_BADGE_BASE} bg-base-content/[0.06] text-base-content/45 border-base-content/[0.1]".freeze

  def sentiment_badge_classes(sentiment)
    case sentiment.to_s
    when "positive" then SENTIMENT_POSITIVE
    when "negative" then SENTIMENT_NEGATIVE
    else SENTIMENT_NEUTRAL
    end
  end

  # ─────────────────────────────────── Rating trend ────

  RATING_TREND_UP     = "inline-flex items-center gap-0.5 text-[var(--color-cat-new)] text-xs font-semibold".freeze
  RATING_TREND_DOWN   = "inline-flex items-center gap-0.5 text-error/80 text-xs font-semibold".freeze
  RATING_TREND_STABLE = "inline-flex items-center gap-0.5 text-base-content/40 text-xs font-semibold".freeze

  def rating_trend_classes(direction)
    case direction
    when :up    then RATING_TREND_UP
    when :down  then RATING_TREND_DOWN
    else RATING_TREND_STABLE
    end
  end

  # ─────────────────────────────────── CPP state badges ────

  CPP_STATE_PUBLISHED = "#{STATUS_BADGE_BASE} bg-[var(--color-cat-new)/0.1] text-[var(--color-cat-new)] border-[var(--color-cat-new)/0.15]".freeze
  CPP_STATE_DRAFT = "#{STATUS_BADGE_BASE} bg-base-content/[0.06] text-base-content/45 border-base-content/[0.1]".freeze

  def cpp_state_badge_classes(state)
    state.to_s == "PUBLISHED" ? CPP_STATE_PUBLISHED : CPP_STATE_DRAFT
  end

  KEYWORD_CHIP = "inline-flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1 rounded-md bg-primary/[0.08] text-primary/80 border border-primary/[0.1]".freeze

  def keyword_chip_classes = KEYWORD_CHIP

  # ─────────────────────────────────── Tracked-keyword display ────
  # Used by the TrackedKeyword card + detail partials on
  # app/views/keywords/_tracking_tab.html.erb. Kept here (not inline)
  # because they render semantic visual identity (rank color, popularity
  # dot strength, flag) that other tracking views may reuse.

  # Muted italic caption used for rank chips in transient states (Queued /
  # Not in top 250). Extracted so any future transient chip uses the same
  # typographic treatment without spawning a parallel class string.
  RANK_CAPTION = "text-xs text-base-content/40 italic".freeze
  def rank_caption_classes = RANK_CAPTION

  # Renders the current rank as "#N" with a subtle "last checked" tooltip.
  # Three distinct states for the nil-rank case:
  #   - rank present                 -> "#N"
  #   - rank nil, never checked      -> "Queued" (nightly job hasn't run for this TKC yet)
  #   - rank nil, but checked_at set -> "Not in top 250" (Apple's result set didn't include us)
  # Conflating the last two states made freshly-added keywords appear as
  # "Not in top 250" even though the nightly rank check hadn't run yet.
  # Tabular-nums keeps numbers aligned when rendered in a column of rows.
  #
  # Optional `estimate:` — an Aso::NextCheckEstimator::Estimate — sharpens
  # the Queued tooltip from a generic "runs nightly" to a tier-specific
  # "First result in ~14 hours — rank refreshes daily". Back-compat: a nil
  # estimate falls back to the pre-estimator copy.
  def rank_display(rank, last_checked_at:, estimate: nil)
    if rank
      tooltip = last_checked_at ? "Last checked #{time_ago_in_words(last_checked_at)} ago" : nil
      tag.span("##{rank}", class: "font-semibold tabular-nums text-primary/90", title: tooltip)
    elsif last_checked_at.nil?
      rank_queued_chip(estimate: estimate)
    else
      tag.span("Not in top 250", class: RANK_CAPTION,
               title: "Checked #{time_ago_in_words(last_checked_at)} ago — your app wasn't in Apple's top results for this keyword.")
    end
  end

  # "Queued" chip for a TKC awaiting its first nightly check. When an
  # estimate is passed, the tooltip reflects the tier's real cadence.
  def rank_queued_chip(estimate: nil)
    tooltip = if estimate
      "First result #{estimate.human} — rank refreshes #{estimate.refresh_cadence}"
    else
      "Next refresh runs nightly — results within 24 hours"
    end
    tag.span(class: RANK_CAPTION, title: tooltip) do
      concat tag.i("", class: "fa-regular fa-clock mr-1")
      concat "Queued"
    end
  end

  # Apple Search Popularity score is reported on a 5–100 scale.
  # Map it to 1–5 filled dots (ceil, clamped) for an at-a-glance signal
  # that sits well next to the keyword text without dominating it.
  def popularity_dots(score_5_to_100)
    return "".html_safe if score_5_to_100.nil?
    filled = ((score_5_to_100.to_f / 100) * 5).ceil.clamp(1, 5)
    tag.span(
      ("●" * filled + "○" * (5 - filled)),
      class: "tracking-widest text-warning/90 text-sm",
      title: "Apple Search Popularity: #{score_5_to_100}/100"
    )
  end

  # Secondary signal next to the rank: how many apps compete on this term.
  # Returns an empty html_safe string when count is nil so callers can
  # always render it without `if` guards.
  def competition_badge(count)
    return "".html_safe if count.nil?
    tag.span(pluralize(count, "app"), class: "text-xs font-medium text-base-content/55")
  end

  # Country flag via the regional-indicator codepoint trick. Guards against
  # non-ISO-3166 input so a typo in a seed or migration won't raise.
  # Known caveat: Windows Chrome still does not render flag emojis (open bug).
  # Acceptable degradation — users also see the country code next to the flag.
  def country_flag(iso2)
    return "".html_safe unless iso2.to_s =~ /\A[a-z]{2}\z/i
    iso2.upcase.chars.map { |c| [ c.ord + 127397 ].pack("U") }.join.html_safe
  end

  def star_rating_html(rating, max: 5)
    filled = rating.to_i.clamp(0, max)
    stars = ("\u2605" * filled) + ("\u2606" * (max - filled))
    content_tag(:span, stars, class: "text-warning/80 tracking-wider text-sm", title: "#{filled}/#{max}")
  end

  # ─────────────────────────────────────────────── Pricing cards ────
  # Pricing-page-only helpers. See docs/design-system.md §pricing for
  # how these interact with the Plan Studio partials.

  # Pricing tier accents use existing design-system colors (primary + warning)
  # rather than bespoke tokens so badges, buttons, and rings match the rest of the app.
  # Primary (brand purple) is for Pro. Warning (amber) is for Team's enterprise tone.
  PRICING_ACCENT_NEUTRAL = {
    border: "border-base-content/[0.08]",
    accent_text: "text-base-content/60",
    accent_bg: "bg-base-content/[0.04]",
    ring: ""
  }.freeze

  PRICING_ACCENT_PRO = {
    border: "border-primary/25",
    accent_text: "text-primary",
    accent_bg: "bg-primary/[0.08]",
    ring: "ring-2 ring-primary/35"
  }.freeze

  PRICING_ACCENT_TEAM = {
    border: "border-warning/30",
    accent_text: "text-warning",
    accent_bg: "bg-warning/[0.10]",
    ring: "ring-2 ring-warning/35"
  }.freeze

  def pricing_tier_accent_classes(tier)
    case tier.to_s
    when "pro"  then PRICING_ACCENT_PRO
    when "team" then PRICING_ACCENT_TEAM
    else             PRICING_ACCENT_NEUTRAL
    end
  end

  # Solid tier-colored fill for in-card usage progress bars.
  def pricing_progress_fill_classes(tier)
    case tier.to_s
    when "pro"  then "bg-primary/80"
    when "team" then "bg-warning/80"
    else             "bg-base-content/30"
    end
  end

  # Card shell — uniform height via h-full, uniform surface via bg-base-200.
  # Tier differentiation is expressed through the highlight ring, not surface
  # color. Hover lifts subtly; highlighted cards get a primary/warning ring.
  # Padding/gap scale down on narrow viewports so three columns don't crush
  # at 1024px; `p-8` stays in the class list as the large-screen value.
  PRICING_CARD_BASE = "relative grid grid-rows-[auto_auto_auto_auto_1fr] h-full min-w-0 rounded-[0.875rem] p-6 sm:p-7 lg:p-8 gap-5 lg:gap-6 border bg-base-200 transition-all duration-200 hover:-translate-y-1".freeze

  # is_highlighted: true applies the tier's ring (primary for pro, warning for
  # team) to make the "current plan or recommended" card pop.
  def pricing_card_classes(tier:, is_current:, is_recommended:, is_highlighted: nil)
    accent = pricing_tier_accent_classes(tier)
    # Back-compat: if caller didn't pass is_highlighted, fall back to is_recommended
    highlight = is_highlighted.nil? ? is_recommended : is_highlighted
    ring = highlight ? accent[:ring] : ""
    current_flag = is_current ? "is-current-plan" : ""
    [ PRICING_CARD_BASE, accent[:border], ring, current_flag ].reject(&:blank?).join(" ")
  end

  # ─────────────────────────────────────── Pricing context badges ────
  # Rendered inside .pricing-card as absolute-positioned pill badges.
  # Priority: scheduled_change > current_tier > most_popular.

  PRICING_BADGE_BASE = "inline-flex items-center gap-1 text-[0.6875rem] font-semibold uppercase tracking-[0.04em] px-2 py-[0.2rem] rounded-md border absolute top-5 right-5".freeze

  def pricing_context_badge(tier:, viewer_context:)
    tier = tier.to_s

    # Scheduled-change badges take priority over everything else
    if (sc = viewer_context.scheduled_change).present?
      return scheduled_change_badge_for(tier, sc)
    end

    # Derive effective current_tier from viewer_type when current_tier is nil
    effective_tier = viewer_context.current_tier.presence || case viewer_context.viewer_type
                                                             when :free         then "free"
                                                             when :pro, :pro_trialing then "pro"
                                                             when :team         then "team"
                                                             end

    if effective_tier == tier
      return your_plan_badge(tier, viewer_context)
    end

    if viewer_context.show_most_popular_on?(tier)
      return most_popular_badge(tier)
    end

    nil
  end

  def your_plan_badge(tier, viewer_context)
    accent = pricing_tier_accent_classes(tier)
    label = viewer_context.trialing? ? "Your trial · #{viewer_context.trial_days}d left" : "Your plan"
    content_tag(:span, label, class: "#{PRICING_BADGE_BASE} #{accent[:accent_bg]} #{accent[:accent_text]} #{accent[:border]}")
  end

  def most_popular_badge(tier)
    accent = pricing_tier_accent_classes(tier)
    content_tag(:span, "Most popular", class: "#{PRICING_BADGE_BASE} #{accent[:accent_bg]} #{accent[:accent_text]} #{accent[:border]}")
  end

  def scheduled_change_badge_for(tier, sc)
    from_tier = sc[:from].to_s
    to_tier = sc[:to].to_s
    if tier == to_tier
      accent = pricing_tier_accent_classes(tier)
      content_tag(:span, "Pending → #{to_tier.capitalize}", class: "#{PRICING_BADGE_BASE} #{accent[:accent_bg]} #{accent[:accent_text]} #{accent[:border]}")
    elsif tier == from_tier
      accent = pricing_tier_accent_classes(tier)
      content_tag(:span, "Your plan (until change)", class: "#{PRICING_BADGE_BASE} #{accent[:accent_bg]} #{accent[:accent_text]} #{accent[:border]}")
    end
  end

  # ─────────────────────────────────────────── Pricing CTA hashes ────
  # Returns { label:, style:, disabled:, action: }.
  # The partial consumes this to render the actual button.

  def pricing_cta(tier:, viewer_context:)
    tier = tier.to_s
    v = viewer_context.viewer_type

    case [ v, tier ]
    when [ :prospect, "free" ] then { label: "Start for free", style: :outline_neutral, disabled: false, action: :sign_up }
    when [ :prospect, "pro" ]  then { label: "Start 14-day Pro trial", style: :primary_pro, disabled: false, action: :sign_up_trial }
    when [ :prospect, "team" ] then { label: "Go Team", style: :primary_team, disabled: false, action: :sign_up_team }

    when [ :free, "free" ] then { label: "Your plan", style: :ghost, disabled: true, action: :none }
    when [ :free, "pro" ]  then { label: "Start Pro", style: :primary_pro, disabled: false, action: :paddle_checkout }
    when [ :free, "team" ] then { label: "Start Team", style: :primary_team, disabled: false, action: :paddle_checkout }

    when [ :pro_trialing, "free" ] then { label: "End trial", style: :ghost, disabled: false, action: :end_trial }
    # Trial users on the Pro card can convert their trial into a paid Pro
    # subscription at any point during the 14-day window. Paddle's webhook
    # processor then clears trial_started_at/trial_ends_at via
    # BillingSubscription.recalculate_user_plan! so they don't get
    # double-downgraded by TrialExpirationJob later.
    when [ :pro_trialing, "pro" ]  then { label: "Activate Pro · #{viewer_context.trial_days}d trial left", style: :primary_pro, disabled: false, action: :paddle_checkout }
    when [ :pro_trialing, "team" ] then { label: "Upgrade to Team", style: :primary_team, disabled: false, action: :paddle_checkout }

    when [ :pro, "free" ] then { label: "Downgrade to Free", style: :ghost, disabled: false, action: :open_preview }
    when [ :pro, "pro" ]  then { label: "Your plan", style: :ghost, disabled: true, action: :none }
    when [ :pro, "team" ] then { label: "Upgrade to Team", style: :primary_team, disabled: false, action: :open_preview }

    when [ :team, "free" ] then { label: "Downgrade to Free", style: :ghost, disabled: false, action: :open_preview }
    when [ :team, "pro" ]  then { label: "Downgrade to Pro", style: :ghost, disabled: false, action: :open_preview }
    when [ :team, "team" ] then { label: "Your plan", style: :ghost, disabled: true, action: :none }
    end
  end

  def pricing_cta_button_classes(style)
    base = "inline-flex items-center justify-center gap-2 w-full text-sm font-semibold px-5 py-3 rounded-lg border cursor-pointer transition-all duration-150 disabled:opacity-60 disabled:cursor-not-allowed"
    case style
    when :primary_pro    then "#{base} bg-primary text-primary-content border-transparent hover:brightness-110"
    when :primary_team   then "#{base} bg-warning text-warning-content border-transparent hover:brightness-110"
    when :outline_pro    then "#{base} bg-transparent text-primary border-primary/40 hover:bg-primary/[0.06]"
    when :outline_neutral then "#{base} bg-transparent text-base-content border-base-content/25 hover:bg-base-content/[0.04]"
    when :ghost          then "#{base} bg-base-content/[0.04] text-base-content/70 border-base-content/[0.08] hover:bg-base-content/[0.08]"
    else base
    end
  end

  # ─────────────────────────────────────── Pricing-card helpers ────

  def tier_default_tagline(tier)
    case tier.to_s
    when "free" then "One organization to explore the product end-to-end."
    when "pro"  then "For teams shipping apps with store uploads and room to grow."
    when "team" then "For agencies and multi-app operations at scale."
    end
  end

  def resolve_price(tier, interval, billing_offering)
    return { amount: "$0", suffix: "", detail: "Free forever", savings: nil } if tier == "free"

    return { amount: "Contact", suffix: "", detail: "Paddle not configured", savings: nil } if billing_offering.nil?

    plan = billing_offering[interval.to_sym] || billing_offering[interval.to_s]
    return { amount: "—", suffix: "", detail: "", savings: nil } if plan.nil?

    if interval.to_s == "monthly"
      monthly_int = plan[:price].to_i
      monthly_str = plan[:price] == monthly_int ? "$#{monthly_int}" : "$#{plan[:price]}"
      { amount: monthly_str, suffix: "/mo", detail: "Billed monthly", savings: nil }
    else
      monthly_equivalent = (plan[:price].to_f / 12).round(2)
      pretty = monthly_equivalent == monthly_equivalent.to_i ? monthly_equivalent.to_i.to_s : format("%.2f", monthly_equivalent)
      yearly_int = plan[:price].to_i
      yearly_str = plan[:price] == yearly_int ? "$#{yearly_int}" : "$#{plan[:price]}"
      savings = plan[:savings_vs_monthly] || plan[:savings] || nil
      { amount: "$#{pretty}", suffix: "/mo", detail: "#{yearly_str}/year billed annually", savings: savings.present? ? "Save #{savings} vs monthly" : nil }
    end
  end

  def feature_bullets(tier)
    # Keyword-tracking bullets are pulled from Billing::PlanCatalog (which
    # reads Pricing::Entitlements). Keeping them here in a hardcoded string
    # would drift the moment a limit changes — see CLAUDE.md.
    keyword_bullets = Billing::PlanCatalog.keyword_tracking_bullets(tier)

    case tier.to_s
    when "free" then [
      "1 organization · 1 seat",
      "1 screenshot project · 5 scenes",
      "Daily store + review sync",
      "300 MB media · 500 MB export",
      *keyword_bullets
    ]
    when "pro" then [
      "3 organizations · 1 seat each",
      "60 store uploads/day",
      "Store sync every 6h · reviews every 2h",
      "Custom product pages",
      "Reply templates for reviews",
      "5 review-monitoring apps",
      *keyword_bullets,
      "100 AI translations + 50 rewrites/mo",
      "90-day analytics history"
    ]
    when "team" then [
      "10 organizations · 10 seats each",
      "300 store uploads/day",
      "Store sync every 3h · reviews every 30 min",
      "Audit log + 365-day retention",
      "Role-based access control",
      "SAML 2.0 SSO",
      "999 review-monitoring apps",
      *keyword_bullets,
      "500 AI translations + 200 rewrites/mo"
    ]
    end
  end

  # Returns a Hash suitable for passing to Rails tag helpers as `data:`.
  # Replaces an earlier `build_cta_data_attrs` that returned an HTML-attr
  # string concatenated via `raw` — inputs are catalog constants today,
  # but returning a hash removes the raw/%Q interpolation footgun entirely.
  #
  # Stimulus action params need the `{controller}_{name}_param` key shape
  # (Rails turns the underscores into kebab-case). The earlier version emitted
  # bare `data-tier` / `data-paddle-checkout-tier` attributes which Stimulus
  # ignored entirely — every plan-card CTA was a silent no-op in prod.
  def cta_data_attrs(cta, tier, interval)
    case cta[:action]
    when :paddle_checkout
      price_id = Billing::Configuration.paddle_price_id_for(tier: tier, interval: interval)
      {
        action: "paddle-checkout#open",
        paddle_checkout_price_id_param: price_id,
        paddle_checkout_plan_tier_param: tier,
        paddle_checkout_billing_interval_param: interval
      }
    when :open_preview
      {
        action: "pricing-plans#openPreview",
        pricing_plans_plan_tier_param: tier,
        pricing_plans_billing_interval_param: interval,
        pricing_plans_label_param: cta[:label]
      }
    when :sign_up, :sign_up_trial, :sign_up_team
      { action: "click->pricing-plans#goToSignup" }
    when :end_trial
      { action: "click->pricing-plans#openEndTrial" }
    else
      {}
    end
  end
end
