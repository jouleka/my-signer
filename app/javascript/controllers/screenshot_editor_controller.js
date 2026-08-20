import { Controller } from "@hotwired/stimulus"
import { loadFontForCanvas } from "lib/font_loader"
import { renderCaptionGroup } from "lib/screenshot/caption_renderer"
import { roundRect, renderScreenshot as renderScreenshotOnCanvas } from "lib/screenshot/frame_renderer"
import { HistoryManager } from "lib/screenshot/history_manager"
import { renderStickers, hitTestSticker, hitTestStickerDelete, hitTestStickerRotation, hitTestStickerResize } from "lib/screenshot/sticker_renderer"
import { loadStickerImage, getStickerImage, preloadStickerImages, preloadEntireLibrary, clearCache as clearStickerCache } from "lib/screenshot/sticker_image_cache"
import { StickerInteraction } from "lib/screenshot/sticker_interaction"
import { renderMeshGradient, MESH_PRESETS } from "lib/screenshot/mesh_gradient_renderer"
import { renderPattern, ensurePatternLoaded, getCachedPattern, isProceduralPattern, clearPatternCache } from "lib/screenshot/pattern_renderer"
import { renderWithPerspective, PERSPECTIVE_PRESETS, inversePerspectivePoint } from "lib/screenshot/perspective_renderer"
import { loadCustomImage, getCustomImage, preloadCustomImages, clearCustomImageCache } from "lib/screenshot/custom_image_cache"
import { calculateTextOverlayPercentage, isGooglePlayPlatform } from "lib/screenshot/text_compliance_checker"
import { generateDarkVariant, generateLightVariant, isDarkScene } from "lib/screenshot/dark_mode_transform"

export default class extends Controller {
  static targets = [
    "canvas", "canvasContainer", "previewSize",
    "captionText", "captionPosition", "captionFontSize", "captionColor", "captionColorText",
    "subtitleText", "subtitleFontSize", "subtitleColor", "subtitleColorText",
    "captionFontFamily", "subtitleFontFamily",
    "captionFontWeight", "subtitleFontWeight",
    "captionTextAlign", "captionMode", "captionZoneSize", "captionZoneSizeLabel",
    "captionLetterSpacing", "captionLetterSpacingLabel",
    "captionLineHeight", "captionLineHeightLabel",
    "captionVerticalPosition", "captionVerticalPositionLabel",
    "textBgEnabled", "textBgControls", "textBgColor", "textBgOpacity", "textBgOpacityLabel", "textBgRadius", "textBgRadiusLabel",
    "captionStrokeEnabled", "captionStrokeControls", "captionStrokeColor", "captionStrokeWidth", "captionStrokeWidthLabel",
    "captionGradientEnabled", "captionGradientControls", "captionGradientStart", "captionGradientEnd",
    "backgroundType", "backgroundColor", "backgroundColorText",
    "solidControls", "gradientControls", "gradientStart", "gradientEnd", "gradientDirection",
    "paddingControls", "screenshotPadding", "paddingLabel",
    "deviceFrame", "thumbnail", "sceneData", "saveButton", "saveIcon", "saveLabel",
    "sceneOverrideEnabled", "sceneOverrideControls",
    "sceneOverrideCaptionColor", "sceneOverrideCaptionFontSize", "sceneOverrideSubtitleColor", "sceneOverrideSubtitleFontSize",
    "overrideBadge", "overridableControls", "overrideActiveIndicator", "effectsActiveBadge",
    "alignLeft", "alignCenter", "alignRight",
    "modeZoneControls", "modeOverlayControls",
    "dragPositionLabel", "resetDragButton",
    "rotationLabel", "resetRotationButton",
    "layoutMode", "autoLayoutPanel", "freeformPanel",
    "posModeBtnAuto", "posModeBtnFreeform",
    "alignmentControls",
    "undoButton", "redoButton",
    "localeBar",
    "stickerControls", "stickerSize", "stickerSizeLabel",
    "stickerSectionBtnEmoji", "stickerSectionBtnLibrary", "stickerSectionBtnImages",
    "stickerEmojiSection", "stickerLibrarySection", "stickerImagesSection",
    "customImageGallery", "customImageUpload",
    "stickerLibrarySearch", "stickerColor", "stickerColorText", "stickerColorControls",
    "stickerText", "stickerTextControls",
    "stickerBgColor", "stickerBgColorControls", "stickerBgEnabled",
    "stickerSectionBtnText", "stickerTextSection", "newTextStickerInput",
    "meshControls", "meshPreset", "meshColor1", "meshColor2", "meshColor3",
    "patternControls", "patternId", "patternColor", "patternColorText", "patternBgColor", "patternBgColorText", "patternScale", "patternScaleLabel",
    "imageControls", "backgroundImageFit", "backgroundImageBlur", "backgroundImageBlurLabel", "backgroundImageBrightness", "backgroundImageBrightnessLabel", "backgroundImagePreview", "backgroundImageRemoveBtn",
    "panoramicControls", "panoramicPreview", "panoramicRemoveBtn", "panoramicSliceOverlay", "panoramicHint",
    "panoramicBlur", "panoramicBlurLabel", "panoramicBrightness", "panoramicBrightnessLabel",
    "perspectivePreset", "perspectiveRotateX", "perspectiveRotateXLabel",
    "perspectiveRotateY", "perspectiveRotateYLabel", "perspectiveDist", "perspectiveDistLabel",
    "perspectiveShadow", "perspectiveReflection", "perspectiveControls",
    "screenshotOffsetY", "screenshotOffsetYLabel",
    "editorTabBtn", "editorTabContent",
    "saveDropdown", "saveDropdownToggle", "dirtyCountBadge",
    "googlePlayTextWarning", "googlePlayTextPercent",
    "darkModeToggle", "darkModeIcon"
  ]

  static values = {
    projectId: Number,
    projectUrl: String,
    settings: Object,
    presets: Object,
    frames: Object,
    brand: Object,
    locales: Array,
    currentLocale: String,
    template: String,
    platform: String,
    stickerLibrary: Object,
    patternLibrary: Object,
    backgroundImageUrl: String,
    customStickerImages: Array
  }

  connect() {
    this.imageCache = new Map()
    this.currentSceneId = null
    this.frameImageCache = new Map()
    this._mainCtx = null
    this._lastTextBounds = null
    this._lastResizeHandles = null
    this._isDragging = false
    this._isResizing = false
    this._isRotating = false
    this._dragStartPos = null
    this._dragPointerOffset = null
    this._resizeHandleIndex = -1
    this._resizeStartY = 0
    this._resizeStartTitleSize = 32
    this._resizeStartSubtitleSize = 20
    this._lastRotationHandle = null
    this._rotateStartAngle = 0
    this._rotateStartRotation = 0
    this._handlesVisible = true
    this._renderVersion = 0
    this._lastRenderedImage = null

    // Perspective interaction state
    this._perspectiveQuad = null

    // Reusable offscreen canvas for perspective rendering (avoids creating one per frame)
    this._offscreenCanvas = null
    this._offscreenCtx = null

    // Reusable static layer (background + screenshot + caption)
    this._staticLayerCanvas = null
    this._staticLayerCtx = null
    this._staticLayerDirty = true

    // Cached pointer mapping while dragging to avoid layout reads on every move event
    this._canvasRectCache = null
    this._canvasScaleX = 1
    this._canvasScaleY = 1

    // RAF throttling for interaction renders
    this._rafPending = false
    this._hoverRafPending = false

    // Interaction state for draft-quality perspective
    this._isInteracting = false

    // Sticker state
    this._stickers = []
    this._stickerBounds = []
    this._selectedStickerId = null
    this._stickerInteraction = new StickerInteraction()
    this._stickerResizeHandleIndex = -1
    this._stickerRotateStartAngle = 0
    this._stickerRotateStartRotation = 0
    this._stickerAssetUrlMap = null

    // Dark mode variant state
    this._darkModeActive = false
    this._darkModePreToggleSettings = null

    // Background image state
    this._backgroundImage = null
    this._backgroundImageLoaded = false
    this._backgroundImageLoading = false
    const initialBgType = this._settingVal("background_type", "solid")
    if (this.backgroundImageUrlValue && (initialBgType === "image" || initialBgType === "panoramic")) {
      this._ensureBackgroundImageLoaded()
    }

    // Undo/Redo history
    this._history = new HistoryManager()
    this._historyDebounceTimer = null

    // Keyboard shortcuts
    this._boundKeyDown = this._handleKeyDown.bind(this)
    document.addEventListener("keydown", this._boundKeyDown)

    // Hover cursor for drag (RAF-throttled to avoid 120Hz hit-testing)
    if (this.hasCanvasTarget) {
      this._boundMouseMove = (event) => {
        if (this._hoverRafPending) return
        this._hoverRafPending = true
        requestAnimationFrame(() => {
          this._hoverRafPending = false
          this._onCanvasHover(event)
        })
      }
      this.canvasTarget.addEventListener("mousemove", this._boundMouseMove)
    }

    // Preload active font+weight pairs only.
    const fontLoads = [
      {
        family: this._settingVal("caption_font_family", "Inter"),
        weight: this._settingVal("caption_font_weight", 700)
      },
      {
        family: this._settingVal("subtitle_font_family", "Inter"),
        weight: this._settingVal("subtitle_font_weight", 400)
      }
    ]
    Promise.allSettled(fontLoads.map(({ family, weight }) => loadFontForCanvas(family, weight)))

    this.settingsValue = this._normalizeCaptionLayoutSettings({ ...(this.settingsValue || {}) })
    this._enforceLockedCaptionLayoutTargets()
    this._normalizeAllSceneCaptionLayoutOverrides()
    this._syncModeVisibility()
    this._syncEffectToggles()
    this._initializeSceneDirtyTracking()

    if (this.hasSceneDataTarget) {
      const firstScene = this.sceneDataTargets[0]
      if (firstScene) {
        this.selectSceneById(firstScene.dataset.sceneId)
        // Push initial state for undo history
        this._pushHistoryImmediate()
        // Warm nearby scenes without flooding the image endpoint.
        this._preloadAdjacentSceneImages()
      }
    }
  }

  disconnect() {
    this._removeDragListeners()
    if (this.hasCanvasTarget && this._boundMouseMove) {
      this.canvasTarget.removeEventListener("mousemove", this._boundMouseMove)
    }
    if (this._boundKeyDown) {
      document.removeEventListener("keydown", this._boundKeyDown)
    }
    clearTimeout(this._historyDebounceTimer)
    clearStickerCache()
    clearCustomImageCache()
    clearPatternCache()
    this._mainCtx = null
    this._offscreenCanvas = null
    this._offscreenCtx = null
    this._staticLayerCanvas = null
    this._staticLayerCtx = null
    this._stickerAssetUrlMap = null
    this._canvasRectCache = null
    this._persistedSceneSnapshotKeys = null
    this._dirtySceneIds = null
  }

  // --- Target accessor helpers ---

  _targetVal(name, fallback = "") {
    const cap = name.charAt(0).toUpperCase() + name.slice(1)
    return this[`has${cap}Target`] ? this[`${name}Target`].value : fallback
  }

  _targetIntVal(name, fallback = 0) {
    return parseInt(this._targetVal(name, fallback)) || fallback
  }

  _targetFloatVal(name, fallback = 0) {
    return parseFloat(this._targetVal(name, fallback)) || fallback
  }

  _targetChecked(name) {
    const cap = name.charAt(0).toUpperCase() + name.slice(1)
    return this[`has${cap}Target`] ? this[`${name}Target`].checked : false
  }

  _swapFrameForPlatform(frameKey, targetPlatform) {
    const FRAME_MAP = {
      // iOS → Android equivalents
      iphone_16_pro_max: "pixel_9",
      iphone_15_pro_max: "pixel_9",
      iphone_11_pro_max: "pixel_9",
      iphone_8_plus: "pixel_9",
      ipad_pro_129: "generic_tablet_10",
      ipad_pro_11: "generic_tablet_7",
      // Android → iOS equivalents
      pixel_9: "iphone_16_pro_max",
      generic_tablet_7: "ipad_pro_11",
      generic_tablet_10: "ipad_pro_129"
    }
    return FRAME_MAP[frameKey] || "generic_phone"
  }

  _settingVal(key, fallback) {
    const s = this.settingsValue || {}
    return s[key] != null ? s[key] : fallback
  }

  _parseJSON(raw, fallback = {}) {
    try {
      const parsed = JSON.parse(raw || "{}")
      return parsed && typeof parsed === "object" ? parsed : fallback
    } catch {
      return fallback
    }
  }

  _normalizeCaptionLayoutSettings(settings = {}) {
    if (!settings || typeof settings !== "object") return settings
    settings.caption_mode = "zone"
    settings.caption_position = "top"
    return settings
  }

  _enforceLockedCaptionLayoutTargets() {
    if (this.hasCaptionModeTarget) this.captionModeTarget.value = "zone"
    if (this.hasCaptionPositionTarget) this.captionPositionTarget.value = "top"
  }

  _normalizeAllSceneCaptionLayoutOverrides() {
    if (!this.hasSceneDataTarget) return

    this.sceneDataTargets.forEach((sceneData) => {
      const overrides = this._parseJSON(sceneData.dataset.sceneOverrides || "{}", {})
      let changed = false

      if (Object.prototype.hasOwnProperty.call(overrides, "caption_mode") && overrides.caption_mode !== "zone") {
        overrides.caption_mode = "zone"
        changed = true
      }
      if (Object.prototype.hasOwnProperty.call(overrides, "caption_position") && overrides.caption_position !== "top") {
        overrides.caption_position = "top"
        changed = true
      }

      if (changed) sceneData.dataset.sceneOverrides = JSON.stringify(overrides)
    })
  }

  _deepSortKeys(value) {
    if (Array.isArray(value)) return value.map(v => this._deepSortKeys(v))
    if (value && typeof value === "object") {
      return Object.keys(value).sort().reduce((acc, key) => {
        acc[key] = this._deepSortKeys(value[key])
        return acc
      }, {})
    }
    return value
  }

  _sceneSnapshotFromData(sceneData) {
    return {
      caption_text: sceneData.dataset.sceneCaption || "",
      subtitle_text: sceneData.dataset.sceneSubtitle || "",
      overrides: this._parseJSON(sceneData.dataset.sceneOverrides || "{}", {}),
      locale_variants: this._parseJSON(sceneData.dataset.sceneLocaleVariants || "{}", {})
    }
  }

  _sceneSnapshotKey(sceneData) {
    return JSON.stringify(this._deepSortKeys(this._sceneSnapshotFromData(sceneData)))
  }

  _buildSceneBodyFromData(sceneData) {
    const snapshot = this._sceneSnapshotFromData(sceneData)
    const body = {
      caption_text: snapshot.caption_text,
      subtitle_text: snapshot.subtitle_text,
      overrides: snapshot.overrides
    }
    if (this.localesValue && this.localesValue.length > 0) {
      body.locale_variants = snapshot.locale_variants
    }
    return body
  }

  _initializeSceneDirtyTracking() {
    this._persistedSceneSnapshotKeys = new Map()
    this._dirtySceneIds = new Set()
    if (!this.hasSceneDataTarget) return

    this.sceneDataTargets.forEach(sceneData => {
      this._persistedSceneSnapshotKeys.set(String(sceneData.dataset.sceneId), this._sceneSnapshotKey(sceneData))
    })
    this._updateAllSceneDirtyStates()
  }

  _syncCurrentSceneDraftToDOM() {
    if (!this.currentSceneId) return
    const sceneData = this.findSceneData(this.currentSceneId)
    if (!sceneData) return

    this._saveCurrentLocaleTextToDOM()
    sceneData.dataset.sceneOverrides = JSON.stringify(this._getSceneOverrides())
    this._updateSceneDirtyState(sceneData.dataset.sceneId)
  }

  _setSceneDirtyIndicator(sceneId, isDirty) {
    this.thumbnailTargets.forEach(thumb => {
      const sid = thumb.dataset.screenshotEditorSceneIdParam
      if (String(sid) !== String(sceneId)) return
      const dot = thumb.querySelector("[data-scene-unsaved-dot]")
      if (dot) dot.classList.toggle("hidden", !isDirty)
    })
  }

  _updateSceneDirtyState(sceneId) {
    if (!sceneId) return false
    const sceneData = this.findSceneData(sceneId)
    if (!sceneData) return false

    const persistedKey = this._persistedSceneSnapshotKeys?.get(String(sceneId))
    if (!persistedKey) {
      this._setSceneDirtyIndicator(sceneId, false)
      return false
    }

    const isDirty = this._sceneSnapshotKey(sceneData) !== persistedKey
    if (isDirty) {
      this._dirtySceneIds?.add(String(sceneId))
    } else {
      this._dirtySceneIds?.delete(String(sceneId))
    }
    this._setSceneDirtyIndicator(sceneId, isDirty)
    return isDirty
  }

  _updateAllSceneDirtyStates() {
    if (!this.hasSceneDataTarget) return
    this.sceneDataTargets.forEach(sceneData => {
      this._updateSceneDirtyState(sceneData.dataset.sceneId)
    })
    this._updateDirtyCountBadge()
  }

  _markSceneAsPersisted(sceneId) {
    const sceneData = this.findSceneData(sceneId)
    if (!sceneData) return
    if (!this._persistedSceneSnapshotKeys) this._persistedSceneSnapshotKeys = new Map()
    this._persistedSceneSnapshotKeys.set(String(sceneId), this._sceneSnapshotKey(sceneData))
    this._updateSceneDirtyState(sceneId)
  }

  // --- Scene selection ---

  selectScene(event) {
    const sceneId = event.params.sceneId || event.currentTarget.dataset.screenshotEditorSceneIdParam
    this.selectSceneById(sceneId)
  }

  selectSceneById(sceneId) {
    // Persist current scene draft before switching scenes
    this._syncCurrentSceneDraftToDOM()

    // Reset dark mode toggle when switching scenes
    this._darkModeActive = false
    this._darkModePreToggleSettings = null
    this._syncDarkModeToggleUI()

    this.currentSceneId = sceneId

    this.thumbnailTargets.forEach(thumb => {
      const thumbSceneId = thumb.dataset.actionParams
        ? JSON.parse(thumb.dataset.actionParams).sceneId
        : thumb.closest("[data-screenshot-editor-scene-id-param]")?.dataset.screenshotEditorSceneIdParam

      const border = thumb.querySelector("div")
      if (border) {
        if (String(thumbSceneId) === String(sceneId)) {
          border.classList.add("border-primary", "shadow-lg")
          border.classList.remove("border-base-200")
        } else {
          border.classList.remove("border-primary", "shadow-lg")
          border.classList.add("border-base-200")
        }
      }
    })

    const sceneData = this.findSceneData(sceneId)
    if (sceneData) {
      // Load locale-aware caption/subtitle
      if (this.localesValue && this.localesValue.length > 0) {
        this._loadLocaleText()
      } else {
        if (this.hasCaptionTextTarget) {
          this.captionTextTarget.value = sceneData.dataset.sceneCaption || ""
        }
        if (this.hasSubtitleTextTarget) {
          this.subtitleTextTarget.value = sceneData.dataset.sceneSubtitle || ""
        }
      }

      // Load per-scene overrides
      this._loadSceneOverrides(sceneData)
    }

    this._updatePanoramicSliceOverlay()
    this._invalidateStaticLayer()
    this.loadAndRender(sceneId)
    this._preloadAdjacentSceneImages()
  }

  _loadSceneOverrides(sceneData) {
    let overrides = {}
    try { overrides = JSON.parse(sceneData.dataset.sceneOverrides || "{}") } catch {}

    // Only consider style overrides for the toggle — ignore drag position, rotation, and stickers
    const styleOverrideKeys = this.constructor.SCENE_STYLE_OVERRIDE_KEYS
    const hasStyleOverrides = styleOverrideKeys.some(k => overrides[k] != null)

    // For non-style scene overrides (e.g. template-applied background/perspective),
    // reflect effective values in the main controls so users can keep editing this scene.
    const nonStyleOverrideKeys = this.constructor.SCENE_SETTING_OVERRIDE_KEYS.filter(
      key => !styleOverrideKeys.includes(key)
    )
    const uiSettings = {}
    nonStyleOverrideKeys.forEach((key) => {
      if (overrides[key] !== undefined) {
        uiSettings[key] = overrides[key]
      } else if (this.settingsValue && this.settingsValue[key] !== undefined) {
        uiSettings[key] = this.settingsValue[key]
      }
    })
    if (Object.keys(uiSettings).length > 0) {
      this._applySettingsToUI(uiSettings)
    }

    if (this.hasSceneOverrideEnabledTarget) {
      this.sceneOverrideEnabledTarget.checked = hasStyleOverrides
    }
    if (this.hasSceneOverrideControlsTarget) {
      this.sceneOverrideControlsTarget.classList.toggle("hidden", !hasStyleOverrides)
    }
    this._syncOverrideVisualState(hasStyleOverrides)
    this._syncSectionBadges()

    if (this.hasSceneOverrideCaptionColorTarget) {
      this.sceneOverrideCaptionColorTarget.value = overrides.caption_color || this._targetVal("captionColor", "#FFFFFF")
    }
    if (this.hasSceneOverrideCaptionFontSizeTarget) {
      this.sceneOverrideCaptionFontSizeTarget.value = overrides.caption_font_size || this._targetIntVal("captionFontSize", 32)
    }
    if (this.hasSceneOverrideSubtitleColorTarget) {
      this.sceneOverrideSubtitleColorTarget.value = overrides.subtitle_color || this._targetVal("subtitleColor", "#CCCCCC")
    }
    if (this.hasSceneOverrideSubtitleFontSizeTarget) {
      this.sceneOverrideSubtitleFontSizeTarget.value = overrides.subtitle_font_size || this._targetIntVal("subtitleFontSize", 20)
    }

    // Load drag position label
    const hasDragPos = overrides.text_position_x != null && overrides.text_position_y != null
    if (this.hasDragPositionLabelTarget) {
      this.dragPositionLabelTarget.textContent = hasDragPos
        ? `${overrides.text_position_x}%, ${overrides.text_position_y}%`
        : "Auto"
    }
    if (this.hasResetDragButtonTarget) {
      this.resetDragButtonTarget.classList.toggle("hidden", !hasDragPos)
    }

    // Load rotation label
    const hasRotation = overrides.text_rotation != null
    if (this.hasRotationLabelTarget) {
      this.rotationLabelTarget.textContent = hasRotation ? `${overrides.text_rotation}°` : "0°"
    }
    if (this.hasResetRotationButtonTarget) {
      this.resetRotationButtonTarget.classList.toggle("hidden", !hasRotation)
    }

    // Load stickers from overrides
    this._loadStickersFromOverrides(overrides)

    // Sync positioning mode UI based on scene state
    this._syncPositioningModeUI(hasDragPos ? "freeform" : "auto")
  }

  _getSceneOverrides() {
    const sceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null
    const overrides = {}
    let stored = {}
    if (sceneData) {
      try { stored = JSON.parse(sceneData.dataset.sceneOverrides || "{}") } catch {}
      Object.assign(overrides, stored)
    }

    // Sync non-style override keys from the current controls.
    // For keys already stored, update to their latest UI value.
    // For keys NOT yet stored, detect new changes by comparing against
    // the project-level default — if different, record as a scene override.
    const currentSettings = this.getCurrentSettings()
    this.constructor.SCENE_SETTING_OVERRIDE_KEYS.forEach((key) => {
      if (this.constructor.SCENE_STYLE_OVERRIDE_KEYS.includes(key)) return
      if (currentSettings[key] === undefined) return
      if (stored[key] !== undefined) {
        // Already an override — keep it synced with the current control value
        overrides[key] = currentSettings[key]
      } else if (this.settingsValue && this.settingsValue[key] !== undefined) {
        // New change: store as override only when it differs from project default
        if (String(currentSettings[key]) !== String(this.settingsValue[key])) {
          overrides[key] = currentSettings[key]
        }
      }
    })

    // Stickers are always saved (independent of scene override toggle)
    if (this._stickers && this._stickers.length > 0) {
      overrides.stickers = this._stickers.map(s => this._sanitizeStickerForPersistence(s))
    } else {
      delete overrides.stickers
    }

    // Scene style overrides are controlled by the explicit per-scene toggle.
    if (!this._targetChecked("sceneOverrideEnabled")) {
      this.constructor.SCENE_STYLE_OVERRIDE_KEYS.forEach((key) => delete overrides[key])
      return overrides
    }

    if (this.hasSceneOverrideCaptionColorTarget) {
      const val = this.sceneOverrideCaptionColorTarget.value
      if (val !== this._targetVal("captionColor", "#FFFFFF")) {
        overrides.caption_color = val
      } else {
        delete overrides.caption_color
      }
    }
    if (this.hasSceneOverrideCaptionFontSizeTarget) {
      const val = parseInt(this.sceneOverrideCaptionFontSizeTarget.value)
      if (val !== this._targetIntVal("captionFontSize", 32)) {
        overrides.caption_font_size = val
      } else {
        delete overrides.caption_font_size
      }
    }
    if (this.hasSceneOverrideSubtitleColorTarget) {
      const val = this.sceneOverrideSubtitleColorTarget.value
      if (val !== this._targetVal("subtitleColor", "#CCCCCC")) {
        overrides.subtitle_color = val
      } else {
        delete overrides.subtitle_color
      }
    }
    if (this.hasSceneOverrideSubtitleFontSizeTarget) {
      const val = parseInt(this.sceneOverrideSubtitleFontSizeTarget.value)
      if (val !== this._targetIntVal("subtitleFontSize", 20)) {
        overrides.subtitle_font_size = val
      } else {
        delete overrides.subtitle_font_size
      }
    }

    return overrides
  }

  findSceneData(sceneId) {
    return this.sceneDataTargets.find(el => String(el.dataset.sceneId) === String(sceneId))
  }

  _getCurrentSceneIndex() {
    if (!this.currentSceneId) return 0
    const scenes = this.sceneDataTargets
    const idx = scenes.findIndex(el => String(el.dataset.sceneId) === String(this.currentSceneId))
    return idx >= 0 ? idx : 0
  }

  _getTotalScenes() {
    return Math.max(this.sceneDataTargets.length, 1)
  }

  // --- Image & frame loading ---

  loadImage(url) {
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.crossOrigin = "anonymous"
      img.onload = () => resolve(img)
      img.onerror = () => reject(new Error(`Failed to load: ${url}`))
      img.src = url
    })
  }

  async ensureFrameLoaded(frameKey) {
    if (frameKey === "none" || this.frameImageCache.has(frameKey)) return
    const frameInfo = this.framesValue?.[frameKey]
    if (!frameInfo?.image_url) return
    try {
      const img = await this.loadImage(frameInfo.image_url)
      this.frameImageCache.set(frameKey, img)
    } catch (e) {
      console.warn(`Failed to load frame: ${frameKey}`, e)
    }
  }

  _cacheSceneImage(sceneId, image) {
    if (!sceneId || !image) return
    if (this.imageCache.has(sceneId)) this.imageCache.delete(sceneId)
    this.imageCache.set(sceneId, image)
    this._pruneSceneImageCache(sceneId)
  }

  _pruneSceneImageCache(pinnedSceneId = null) {
    const maxEntries = this.constructor.MAX_SCENE_IMAGE_CACHE
    while (this.imageCache.size > maxEntries) {
      const oldestKey = this.imageCache.keys().next().value
      if (oldestKey == null) break
      if (String(oldestKey) === String(this.currentSceneId) || String(oldestKey) === String(pinnedSceneId)) {
        const value = this.imageCache.get(oldestKey)
        this.imageCache.delete(oldestKey)
        this.imageCache.set(oldestKey, value)
        continue
      }
      this.imageCache.delete(oldestKey)
    }
  }

  async loadAndRender(sceneId) {
    const sceneData = this.findSceneData(sceneId)
    if (!sceneData) return

    this._invalidateStaticLayer()
    const imageUrl = sceneData.dataset.sceneImageUrl
    const myVersion = ++this._renderVersion

    // If image is cached, render immediately (no async wait)
    if (this.imageCache.has(sceneId)) {
      const image = this.imageCache.get(sceneId)
      const frameKey = this._buildCurrentSceneSettings().device_frame || "none"
      if (frameKey !== "none") await this.ensureFrameLoaded(frameKey)
      this._invalidateStaticLayer()
      if (this._renderVersion !== myVersion) return
      this._lastRenderedImage = image
      this.renderPreview(image)
      return
    }

    // Not cached — render with last image as placeholder (avoids black flash)
    if (this._lastRenderedImage) {
      this.renderPreview(this._lastRenderedImage)
    }

    // Load image in background
    let image
    try {
      image = await this.loadImage(imageUrl)
      this._cacheSceneImage(sceneId, image)
    } catch (e) {
      console.warn(`Failed to load scene image: ${sceneId}`, e)
      image = null
    }

    const frameKey = this._buildCurrentSceneSettings().device_frame || "none"
    if (frameKey !== "none") {
      await this.ensureFrameLoaded(frameKey)
      this._invalidateStaticLayer()
    }

    // Only render if this is still the latest render request
    if (this._renderVersion !== myVersion) return
    if (String(this.currentSceneId) !== String(sceneId)) return

    if (image) this._lastRenderedImage = image
    this.renderPreview(image || this._lastRenderedImage)
  }

  _preloadAdjacentSceneImages() {
    const scenes = this.sceneDataTargets
    if (!scenes || scenes.length <= 1 || !this.currentSceneId) return

    const currentIdx = this._getCurrentSceneIndex()
    const candidateIndexes = []
    const maxDistance = 2

    for (let offset = 1; offset <= maxDistance; offset++) {
      const nextIdx = currentIdx + offset
      const prevIdx = currentIdx - offset
      if (nextIdx < scenes.length) candidateIndexes.push(nextIdx)
      if (prevIdx >= 0) candidateIndexes.push(prevIdx)
    }

    candidateIndexes.forEach((idx, queueIdx) => {
      const sceneData = scenes[idx]
      if (!sceneData) return
      this._queueScenePreload(sceneData, queueIdx)
    })
  }

  _queueScenePreload(sceneData, queueIdx = 0) {
    const sceneId = sceneData.dataset.sceneId
    const url = sceneData.dataset.sceneImageUrl
    if (!sceneId || !url || this.imageCache.has(sceneId)) return

    // Keep warmup light to avoid overloading image responses behind proxies.
    const delayMs = 200 * (queueIdx + 1)
    setTimeout(() => {
      if (this.imageCache.has(sceneId)) return
      this.loadImage(url)
        .then(img => this._cacheSceneImage(sceneId, img))
        .catch(() => {}) // silently ignore preload failures
    }, delayMs)
  }

  // --- Preview rendering ---

  _getOffscreenCanvas(width, height) {
    if (!this._offscreenCanvas || this._offscreenCanvas.width !== width || this._offscreenCanvas.height !== height) {
      this._offscreenCanvas = document.createElement("canvas")
      this._offscreenCanvas.width = width
      this._offscreenCanvas.height = height
      this._offscreenCtx = this._offscreenCanvas.getContext("2d")
    } else {
      this._offscreenCtx.setTransform(1, 0, 0, 1, 0, 0)
      this._offscreenCtx.globalAlpha = 1
      this._offscreenCtx.filter = "none"
      this._offscreenCtx.clearRect(0, 0, width, height)
    }
    return { canvas: this._offscreenCanvas, ctx: this._offscreenCtx }
  }

  _getStaticLayerCanvas(width, height) {
    if (!this._staticLayerCanvas || this._staticLayerCanvas.width !== width || this._staticLayerCanvas.height !== height) {
      this._staticLayerCanvas = document.createElement("canvas")
      this._staticLayerCanvas.width = width
      this._staticLayerCanvas.height = height
      this._staticLayerCtx = this._staticLayerCanvas.getContext("2d")
      this._staticLayerDirty = true
    }
    return { canvas: this._staticLayerCanvas, ctx: this._staticLayerCtx }
  }

  _invalidateStaticLayer() {
    this._staticLayerDirty = true
  }

  _scheduleRender() {
    if (this._rafPending) return
    this._rafPending = true
    requestAnimationFrame(() => {
      this._rafPending = false
      const image = this.imageCache.get(this.currentSceneId)
      if (image) this.renderPreview(image)
    })
  }

  _beginInteraction() {
    this._isInteracting = true
  }

  _endInteraction() {
    this._isInteracting = false
    // Clear pending RAF so the next _scheduleRender() guarantees a fresh full-quality render
    this._rafPending = false
  }

  renderPreview(sourceImage) {
    if (!this.hasCanvasTarget) return

    const canvas = this.canvasTarget
    if (!this._mainCtx || this._mainCtx.canvas !== canvas) {
      this._mainCtx = canvas.getContext("2d")
    }
    let ctx = this._mainCtx

    const sceneSettings = this._buildCurrentSceneSettings()
    const frameKey = sceneSettings.device_frame || "none"
    const frameInfo = (frameKey !== "none") ? this.framesValue?.[frameKey] : null

    const logicalPreviewWidth = 440
    let logicalPreviewHeight
    if (frameInfo?.vb_width && frameInfo?.vb_height) {
      logicalPreviewHeight = Math.round(logicalPreviewWidth * (frameInfo.vb_height / frameInfo.vb_width))
    } else {
      logicalPreviewHeight = Math.round(logicalPreviewWidth * (19.5 / 9))
    }

    const pOpts = this._getPerspectiveOptsFromSettings(sceneSettings)

    // Supersample preview, but adapt quality for long interactive sessions.
    const dpr = window.devicePixelRatio || 1
    const cores = navigator.hardwareConcurrency || 8
    const deviceMemory = navigator.deviceMemory || 8
    const lowPowerDevice = cores <= 4 || deviceMemory <= 4

    let renderScale
    if (pOpts) {
      // Keep internal scale stable while interacting so drag does not appear to
      // shift padding/background alignment.
      renderScale = Math.max(1.15, Math.min(lowPowerDevice ? 1.8 : 2.4, dpr * 1.2))
    } else {
      renderScale = Math.max(1, Math.min(lowPowerDevice ? 1.5 : 2.0, dpr * 1.05))
    }
    const renderWidth = Math.round(logicalPreviewWidth * renderScale)
    const renderHeight = Math.round(logicalPreviewHeight * renderScale)

    if (canvas.width !== renderWidth || canvas.height !== renderHeight) {
      canvas.width = renderWidth
      canvas.height = renderHeight
      this._mainCtx = canvas.getContext("2d")
      ctx = this._mainCtx
      this._invalidateStaticLayer()
    }
    const logicalWidthCss = `${logicalPreviewWidth}px`
    const logicalHeightCss = `${logicalPreviewHeight}px`
    if (canvas.style.width !== logicalWidthCss) canvas.style.width = logicalWidthCss
    if (canvas.style.height !== logicalHeightCss) canvas.style.height = logicalHeightCss

    const captionOpts = this._collectCaptionOptsFromSettings(sceneSettings)
    captionOpts.dragPositionX = this._liveDragPosition ? this._liveDragPosition.x : captionOpts.dragPositionX
    captionOpts.dragPositionY = this._liveDragPosition ? this._liveDragPosition.y : captionOpts.dragPositionY
    captionOpts.rotation = this._liveRotation != null ? this._liveRotation : captionOpts.rotation
    captionOpts.showHandles = sceneSettings.layout_mode === "freeform" && this._handlesVisible !== false

    this._ensureStickerMediaLoaded()
    const showStickerHandles = !!this._selectedStickerId

    const { canvas: staticLayerCanvas, ctx: staticCtx } = this._getStaticLayerCanvas(renderWidth, renderHeight)
    if (this._staticLayerDirty) {
      staticCtx.setTransform(1, 0, 0, 1, 0, 0)
      staticCtx.globalAlpha = 1
      staticCtx.filter = "none"
      staticCtx.clearRect(0, 0, renderWidth, renderHeight)
      // Keep background separate in perspective mode so only the composition
      // (screenshot + text + stickers) is warped, matching prior behavior.
      if (!pOpts) {
        this.drawBackgroundOn(staticCtx, renderWidth, renderHeight, sceneSettings)
      }
      this.drawScreenshotOn(staticCtx, sourceImage, renderWidth, renderHeight, sceneSettings, captionOpts)
      this._renderCaptionGroup(staticCtx, renderWidth, renderHeight, captionOpts)
      this._staticLayerDirty = false
    }

    ctx.setTransform(1, 0, 0, 1, 0, 0)
    ctx.globalAlpha = 1
    ctx.filter = "none"
    ctx.clearRect(0, 0, renderWidth, renderHeight)

    if (pOpts) {
      this.drawBackgroundOn(ctx, renderWidth, renderHeight, sceneSettings)
      // Warp full composition (screenshot + captions + stickers) for Appscreens-style output.
      const { canvas: off, ctx: offCtx } = this._getOffscreenCanvas(renderWidth, renderHeight)
      offCtx.drawImage(staticLayerCanvas, 0, 0)
      this._stickerBounds = renderStickers(offCtx, renderWidth, renderHeight, this._stickers, this._selectedStickerId, showStickerHandles)
      const quality = this._isInteracting ? "draft" : "full"
      this._perspectiveQuad = renderWithPerspective(ctx, off, renderWidth, renderHeight, { ...pOpts, quality })
    } else {
      this._perspectiveQuad = null
      ctx.drawImage(staticLayerCanvas, 0, 0)
      this._stickerBounds = renderStickers(ctx, renderWidth, renderHeight, this._stickers, this._selectedStickerId, showStickerHandles)
    }

    if (this.hasPreviewSizeTarget) {
      this.previewSizeTarget.textContent = `${logicalPreviewWidth}x${logicalPreviewHeight}`
    }

    // Google Play text compliance check (runs on every render)
    this._checkGooglePlayTextCompliance(renderWidth, renderHeight, captionOpts)
  }

  _buildCurrentSceneSettings() {
    const settings = this.getCurrentSettings()
    const sceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null

    if (sceneData) {
      Object.assign(settings, this._getSceneOverrides())
    }

    this._normalizeCaptionLayoutSettings(settings)

    settings.caption_text = this.hasCaptionTextTarget ? this.captionTextTarget.value : ""
    settings.subtitle_text = this.hasSubtitleTextTarget ? this.subtitleTextTarget.value : ""

    if (settings.background_type === "panoramic") {
      settings.panoramic_scene_index = this._getCurrentSceneIndex()
      settings.panoramic_total_scenes = this._getTotalScenes()
    }

    return settings
  }

  _collectCaptionOpts() {
    const sceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null
    let overrides = {}
    if (sceneData) {
      try { overrides = JSON.parse(sceneData.dataset.sceneOverrides || "{}") } catch {}
    }
    // Scene style overrides should only apply when the scene override toggle is on.
    const styleOverrideKeys = this.constructor.SCENE_STYLE_OVERRIDE_KEYS
    if (this._targetChecked("sceneOverrideEnabled")) {
      Object.assign(overrides, this._getSceneOverrides())
    } else {
      styleOverrideKeys.forEach((key) => delete overrides[key])
    }

    return {
      text: this.hasCaptionTextTarget ? this.captionTextTarget.value : "",
      subtitleText: this.hasSubtitleTextTarget ? this.subtitleTextTarget.value : "",
      position: "top",
      fontSize: overrides.caption_font_size || this._targetIntVal("captionFontSize", 32),
      color: overrides.caption_color || this._targetVal("captionColor", "#FFFFFF"),
      fontFamily: this._targetVal("captionFontFamily", "Inter"),
      fontWeight: this._targetIntVal("captionFontWeight", 700),
      textAlign: this._targetVal("captionTextAlign", "center"),
      mode: "zone",
      zoneSize: this._targetIntVal("captionZoneSize", 12),
      letterSpacing: this._targetFloatVal("captionLetterSpacing", 0),
      lineHeight: this._targetFloatVal("captionLineHeight", 1.3),
      verticalPosition: this._targetVal("captionVerticalPosition", ""),
      subtitleFontSize: overrides.subtitle_font_size || this._targetIntVal("subtitleFontSize", 20),
      subtitleColor: overrides.subtitle_color || this._targetVal("subtitleColor", "#CCCCCC"),
      subtitleFontFamily: this._targetVal("subtitleFontFamily", "Inter"),
      subtitleFontWeight: this._targetIntVal("subtitleFontWeight", 400),
      subtitleLetterSpacing: this._targetFloatVal("subtitleLetterSpacing", 0),
      subtitleLineHeight: this._targetFloatVal("subtitleLineHeight", 1.3),
      textBgEnabled: this._targetChecked("textBgEnabled"),
      textBgColor: this._targetVal("textBgColor", "#000000"),
      textBgOpacity: this._targetIntVal("textBgOpacity", 50),
      textBgRadius: this._targetIntVal("textBgRadius", 12),
      textBgPaddingX: parseInt(this.settingsValue?.text_bg_padding_x) || 24,
      textBgPaddingY: parseInt(this.settingsValue?.text_bg_padding_y) || 12,
      strokeEnabled: this._targetChecked("captionStrokeEnabled"),
      strokeColor: this._targetVal("captionStrokeColor", "#000000"),
      strokeWidth: this._targetIntVal("captionStrokeWidth", 2),
      gradientEnabled: this._targetChecked("captionGradientEnabled"),
      gradientStart: this._targetVal("captionGradientStart", "#FF6B6B"),
      gradientEnd: this._targetVal("captionGradientEnd", "#4ECDC4"),
      dragPositionX: this._liveDragPosition ? this._liveDragPosition.x : (overrides.text_position_x != null ? parseFloat(overrides.text_position_x) : null),
      dragPositionY: this._liveDragPosition ? this._liveDragPosition.y : (overrides.text_position_y != null ? parseFloat(overrides.text_position_y) : null),
      rotation: this._liveRotation != null ? this._liveRotation : (overrides.text_rotation != null ? parseFloat(overrides.text_rotation) : 0),
      showHandles: this.hasLayoutModeTarget && this.layoutModeTarget.value === "freeform" && this._handlesVisible !== false
    }
  }

  _collectCaptionOptsFromSettings(settings) {
    const normalizedSettings = this._normalizeCaptionLayoutSettings({ ...(settings || {}) })
    return {
      text: normalizedSettings.caption_text || "",
      subtitleText: normalizedSettings.subtitle_text || "",
      position: normalizedSettings.caption_position || "top",
      fontSize: normalizedSettings.caption_font_size || 32,
      color: normalizedSettings.caption_color || "#FFFFFF",
      fontFamily: normalizedSettings.caption_font_family || "Inter",
      fontWeight: normalizedSettings.caption_font_weight || 700,
      textAlign: normalizedSettings.caption_text_align || "center",
      mode: normalizedSettings.caption_mode || "zone",
      zoneSize: normalizedSettings.caption_zone_size || 12,
      letterSpacing: normalizedSettings.caption_letter_spacing || 0,
      lineHeight: normalizedSettings.caption_line_height || 1.3,
      verticalPosition: normalizedSettings.caption_vertical_position || "",
      subtitleFontSize: normalizedSettings.subtitle_font_size || 20,
      subtitleColor: normalizedSettings.subtitle_color || "#CCCCCC",
      subtitleFontFamily: normalizedSettings.subtitle_font_family || "Inter",
      subtitleFontWeight: normalizedSettings.subtitle_font_weight || 400,
      subtitleLetterSpacing: normalizedSettings.subtitle_letter_spacing || 0,
      subtitleLineHeight: normalizedSettings.subtitle_line_height || 1.3,
      textBgEnabled: normalizedSettings.text_bg_enabled || false,
      textBgColor: normalizedSettings.text_bg_color || "#000000",
      textBgOpacity: normalizedSettings.text_bg_opacity != null ? normalizedSettings.text_bg_opacity : 50,
      textBgRadius: normalizedSettings.text_bg_radius != null ? normalizedSettings.text_bg_radius : 12,
      textBgPaddingX: normalizedSettings.text_bg_padding_x || 24,
      textBgPaddingY: normalizedSettings.text_bg_padding_y || 12,
      strokeEnabled: normalizedSettings.caption_stroke_enabled || false,
      strokeColor: normalizedSettings.caption_stroke_color || "#000000",
      strokeWidth: normalizedSettings.caption_stroke_width || 2,
      gradientEnabled: normalizedSettings.caption_gradient_enabled || false,
      gradientStart: normalizedSettings.caption_gradient_start || "#FF6B6B",
      gradientEnd: normalizedSettings.caption_gradient_end || "#4ECDC4",
      dragPositionX: normalizedSettings.text_position_x != null ? parseFloat(normalizedSettings.text_position_x) : null,
      dragPositionY: normalizedSettings.text_position_y != null ? parseFloat(normalizedSettings.text_position_y) : null,
      rotation: normalizedSettings.text_rotation != null ? parseFloat(normalizedSettings.text_rotation) : 0,
      showHandles: false
    }
  }

  drawBackground(ctx, width, height) {
    const bgType = this.hasBackgroundTypeTarget ? this.backgroundTypeTarget.value : "solid"

    if (bgType === "none") {
      ctx.clearRect(0, 0, width, height)
      return
    }

    if (bgType === "mesh") {
      const presetKey = this.hasMeshPresetTarget ? this.meshPresetTarget.value : "sunset"
      const overrides = {
        mesh_color_1: this.hasMeshColor1Target ? this.meshColor1Target.value : null,
        mesh_color_2: this.hasMeshColor2Target ? this.meshColor2Target.value : null,
        mesh_color_3: this.hasMeshColor3Target ? this.meshColor3Target.value : null
      }
      renderMeshGradient(ctx, width, height, presetKey, overrides)
      return
    }

    if (bgType === "pattern") {
      const patternId = this.hasPatternIdTarget ? this.patternIdTarget.value : "dots"
      const color = this.hasPatternColorTarget ? this.patternColorTarget.value : "#FFFFFF"
      const bgColor = this.hasPatternBgColorTarget ? this.patternBgColorTarget.value : "#000000"
      const scale = this.hasPatternScaleTarget ? parseInt(this.patternScaleTarget.value) : 100
      renderPattern(ctx, width, height, patternId, {
        color, bgColor, scale, patternLibrary: this.patternLibraryValue,
        onLoaded: () => {
          this._invalidateStaticLayer()
          this._scheduleRender()
        }
      })
      return
    }

    if (bgType === "panoramic") {
      ctx.fillStyle = "#000000"
      ctx.fillRect(0, 0, width, height)
      if (this._backgroundImage && this._backgroundImageLoaded) {
        const blur = this.hasPanoramicBlurTarget ? parseInt(this.panoramicBlurTarget.value) : 0
        const brightness = this.hasPanoramicBrightnessTarget ? parseInt(this.panoramicBrightnessTarget.value) : 100
        const sceneIndex = this._getCurrentSceneIndex()
        const totalScenes = this._getTotalScenes()

        ctx.save()
        if (blur > 0 || brightness !== 100) {
          const filters = []
          if (blur > 0) filters.push(`blur(${blur}px)`)
          if (brightness !== 100) filters.push(`brightness(${brightness / 100})`)
          ctx.filter = filters.join(" ")
        }
        this._drawPanoramicSlice(ctx, this._backgroundImage, 0, 0, width, height, sceneIndex, totalScenes)
        ctx.restore()
      }
      return
    }

    if (bgType === "image") {
      ctx.fillStyle = "#000000"
      ctx.fillRect(0, 0, width, height)
      if (this._backgroundImage && this._backgroundImageLoaded) {
        const fit = this.hasBackgroundImageFitTarget ? this.backgroundImageFitTarget.value : "cover"
        const blur = this.hasBackgroundImageBlurTarget ? parseInt(this.backgroundImageBlurTarget.value) : 0
        const brightness = this.hasBackgroundImageBrightnessTarget ? parseInt(this.backgroundImageBrightnessTarget.value) : 100

        ctx.save()
        if (blur > 0 || brightness !== 100) {
          const filters = []
          if (blur > 0) filters.push(`blur(${blur}px)`)
          if (brightness !== 100) filters.push(`brightness(${brightness / 100})`)
          ctx.filter = filters.join(" ")
        }
        if (fit === "contain") {
          this._drawImageContain(ctx, this._backgroundImage, 0, 0, width, height)
        } else {
          this._drawImageCover(ctx, this._backgroundImage, 0, 0, width, height)
        }
        ctx.restore()
      }
      return
    }

    if (bgType === "gradient") {
      const start = this.hasGradientStartTarget ? this.gradientStartTarget.value : "#000000"
      const end = this.hasGradientEndTarget ? this.gradientEndTarget.value : "#764BA2"
      const direction = this.hasGradientDirectionTarget ? this.gradientDirectionTarget.value : "to-bottom"

      let gradient
      if (direction === "to-right") {
        gradient = ctx.createLinearGradient(0, 0, width, 0)
      } else {
        gradient = ctx.createLinearGradient(0, 0, 0, height)
      }
      gradient.addColorStop(0, start)
      gradient.addColorStop(1, end)
      ctx.fillStyle = gradient
    } else {
      ctx.fillStyle = this.hasBackgroundColorTarget ? this.backgroundColorTarget.value : "#000000"
    }
    ctx.fillRect(0, 0, width, height)
  }

  drawScreenshot(ctx, image, canvasWidth, canvasHeight, frameKey, captionOpts) {
    if (!image) return

    renderScreenshotOnCanvas(ctx, image, canvasWidth, canvasHeight, {
      bgType: this.hasBackgroundTypeTarget ? this.backgroundTypeTarget.value : "solid",
      paddingPct: this.hasScreenshotPaddingTarget ? parseInt(this.screenshotPaddingTarget.value) : 8,
      captionText: captionOpts.text,
      captionPosition: captionOpts.position,
      captionMode: captionOpts.mode,
      captionZoneSize: captionOpts.zoneSize,
      screenshotOffsetY: this._targetIntVal("screenshotOffsetY", 0),
      frameKey
    }, this.framesValue, this.frameImageCache)
  }

  // --- Export rendering ---

  async renderAtSize(sourceImage, width, height, settings = {}) {
    settings = this._normalizeCaptionLayoutSettings({ ...settings })
    const frameKey = settings.device_frame || "none"
    if (frameKey !== "none") {
      await this.ensureFrameLoaded(frameKey)
    }

    // Load fonts needed for export
    const fontFamily = settings.caption_font_family || "Inter"
    const subtitleFamily = settings.subtitle_font_family || "Inter"
    await Promise.all([
      loadFontForCanvas(fontFamily, settings.caption_font_weight || 700),
      loadFontForCanvas(subtitleFamily, settings.subtitle_font_weight || 400)
    ])

    const canvas = document.createElement("canvas")
    canvas.width = width
    canvas.height = height
    const ctx = canvas.getContext("2d")

    // Preload pattern tiles for export if needed
    if (settings.background_type === "pattern" && !isProceduralPattern(settings.pattern_id)) {
      await ensurePatternLoaded(ctx, settings.pattern_id || "dots", settings.pattern_color || "#FFFFFF", settings.pattern_scale || 100, this.patternLibraryValue)
    }

    // Ensure background image is loaded for export
    if ((settings.background_type === "image" || settings.background_type === "panoramic") && this.backgroundImageUrlValue && !this._backgroundImageLoaded) {
      await this._loadBackgroundImage(this.backgroundImageUrlValue)
    }

    const captionOpts = this._collectCaptionOptsFromSettings(settings)

    this.drawBackgroundOn(ctx, width, height, settings)

    // Render stickers for export (preload asset and custom images first)
    const exportStickers = settings.stickers || []
    if (exportStickers.length > 0 && exportStickers.some(s => (s.type || "emoji") === "asset")) {
      await preloadStickerImages(exportStickers, this.stickerLibraryValue)
    }
    if (exportStickers.length > 0 && exportStickers.some(s => s.type === "custom_image")) {
      await preloadCustomImages(exportStickers)
    }

    const pOpts = this._getPerspectiveOptsFromSettings(settings)
    if (pOpts) {
      // Warp full composition for export so preview/export match.
      const off = document.createElement("canvas")
      off.width = width; off.height = height
      const offCtx = off.getContext("2d")
      this.drawScreenshotOn(offCtx, sourceImage, width, height, settings, captionOpts)
      this._renderCaptionGroup(offCtx, width, height, captionOpts)
      if (exportStickers.length > 0) {
        renderStickers(offCtx, width, height, exportStickers, null, false)
      }
      renderWithPerspective(ctx, off, width, height, pOpts)
    } else {
      this.drawScreenshotOn(ctx, sourceImage, width, height, settings, captionOpts)
      this._renderCaptionGroup(ctx, width, height, captionOpts)
      if (exportStickers.length > 0) {
        renderStickers(ctx, width, height, exportStickers, null, false)
      }
    }

    return canvas
  }

  drawBackgroundOn(ctx, width, height, settings) {
    const bgType = settings.background_type || "solid"

    if (bgType === "none") {
      ctx.clearRect(0, 0, width, height)
      return
    }

    if (bgType === "mesh") {
      renderMeshGradient(ctx, width, height, settings.mesh_preset || "sunset", {
        mesh_color_1: settings.mesh_color_1,
        mesh_color_2: settings.mesh_color_2,
        mesh_color_3: settings.mesh_color_3
      })
      return
    }

    if (bgType === "pattern") {
      renderPattern(ctx, width, height, settings.pattern_id || "dots", {
        color: settings.pattern_color || "#FFFFFF",
        bgColor: settings.pattern_bg_color || "#000000",
        scale: settings.pattern_scale || 100,
        patternLibrary: this.patternLibraryValue,
        onLoaded: () => {
          this._invalidateStaticLayer()
          this._scheduleRender()
        }
      })
      return
    }

    if (bgType === "panoramic") {
      ctx.fillStyle = "#000000"
      ctx.fillRect(0, 0, width, height)
      if (this._backgroundImage && this._backgroundImageLoaded) {
        const blur = parseInt(settings.background_image_blur) || 0
        const brightness = parseInt(settings.background_image_brightness) || 100
        const sceneIndex = settings.panoramic_scene_index || 0
        const totalScenes = settings.panoramic_total_scenes || 1

        ctx.save()
        if (blur > 0 || brightness !== 100) {
          const filters = []
          if (blur > 0) filters.push(`blur(${blur}px)`)
          if (brightness !== 100) filters.push(`brightness(${brightness / 100})`)
          ctx.filter = filters.join(" ")
        }
        this._drawPanoramicSlice(ctx, this._backgroundImage, 0, 0, width, height, sceneIndex, totalScenes)
        ctx.restore()
      }
      return
    }

    if (bgType === "image") {
      ctx.fillStyle = "#000000"
      ctx.fillRect(0, 0, width, height)
      if (this._backgroundImage && this._backgroundImageLoaded) {
        const fit = settings.background_image_fit || "cover"
        const blur = parseInt(settings.background_image_blur) || 0
        const brightness = parseInt(settings.background_image_brightness) || 100

        ctx.save()
        if (blur > 0 || brightness !== 100) {
          const filters = []
          if (blur > 0) filters.push(`blur(${blur}px)`)
          if (brightness !== 100) filters.push(`brightness(${brightness / 100})`)
          ctx.filter = filters.join(" ")
        }
        if (fit === "contain") {
          this._drawImageContain(ctx, this._backgroundImage, 0, 0, width, height)
        } else {
          this._drawImageCover(ctx, this._backgroundImage, 0, 0, width, height)
        }
        ctx.restore()
      }
      return
    }

    if (bgType === "gradient") {
      const direction = settings.gradient_direction || "to-bottom"
      let gradient
      if (direction === "to-right") {
        gradient = ctx.createLinearGradient(0, 0, width, 0)
      } else {
        gradient = ctx.createLinearGradient(0, 0, 0, height)
      }
      gradient.addColorStop(0, settings.gradient_start || "#000000")
      gradient.addColorStop(1, settings.gradient_end || "#764BA2")
      ctx.fillStyle = gradient
    } else {
      ctx.fillStyle = settings.background_color || "#000000"
    }
    ctx.fillRect(0, 0, width, height)
  }

  drawScreenshotOn(ctx, image, canvasWidth, canvasHeight, settings, captionOpts) {
    if (!image) return
    settings = this._normalizeCaptionLayoutSettings({ ...(settings || {}) })

    renderScreenshotOnCanvas(ctx, image, canvasWidth, canvasHeight, {
      bgType: settings.background_type || "solid",
      paddingPct: settings.screenshot_padding != null ? settings.screenshot_padding : 8,
      captionText: settings.caption_text || "",
      captionPosition: settings.caption_position || "top",
      captionMode: settings.caption_mode || "zone",
      captionZoneSize: settings.caption_zone_size || 12,
      screenshotOffsetY: settings.screenshot_offset_y || 0,
      frameKey: settings.device_frame || "none"
    }, this.framesValue, this.frameImageCache)
  }

  // --- Caption rendering (delegates to lib/screenshot/caption_renderer) ---

  _renderCaptionGroup(ctx, canvasWidth, canvasHeight, opts) {
    const result = renderCaptionGroup(ctx, canvasWidth, canvasHeight, opts, roundRect)
    this._lastTextBounds = result.textBounds || null
    this._lastResizeHandles = result.resizeHandles || null
    this._lastRotationHandle = result.rotationHandle || null
  }

  // --- Google Play text compliance check ---

  _checkGooglePlayTextCompliance(canvasWidth, canvasHeight, captionOpts) {
    if (!this.hasGooglePlayTextWarningTarget) return
    if (!isGooglePlayPlatform(this.platformValue)) return

    const result = calculateTextOverlayPercentage(
      canvasWidth, canvasHeight, captionOpts, this._stickers
    )
    const percentDisplay = Math.round(result.percentage * 100)

    if (result.exceeds) {
      this.googlePlayTextWarningTarget.classList.remove("hidden")
      if (this.hasGooglePlayTextPercentTarget) {
        this.googlePlayTextPercentTarget.textContent = percentDisplay
      }
    } else {
      this.googlePlayTextWarningTarget.classList.add("hidden")
    }
  }

  // --- UI event handlers ---

  updatePreview() {
    if (this._suppressPreview) return
    this._invalidateStaticLayer()
    if (this.hasBackgroundTypeTarget) {
      const bgType = this.backgroundTypeTarget.value
      const isNone = bgType === "none"

      if (this.hasPaddingControlsTarget) {
        this.paddingControlsTarget.classList.toggle("hidden", isNone)
      }
      if (this.hasSolidControlsTarget) {
        this.solidControlsTarget.classList.toggle("hidden", bgType !== "solid")
      }
      if (this.hasGradientControlsTarget) {
        this.gradientControlsTarget.classList.toggle("hidden", bgType !== "gradient")
      }
      if (this.hasMeshControlsTarget) {
        this.meshControlsTarget.classList.toggle("hidden", bgType !== "mesh")
      }
      if (this.hasPatternControlsTarget) {
        this.patternControlsTarget.classList.toggle("hidden", bgType !== "pattern")
      }
      if (this.hasImageControlsTarget) {
        this.imageControlsTarget.classList.toggle("hidden", bgType !== "image")
      }
      if (this.hasPanoramicControlsTarget) {
        this.panoramicControlsTarget.classList.toggle("hidden", bgType !== "panoramic")
      }
      if (this.hasPanoramicHintTarget) {
        this.panoramicHintTarget.classList.toggle("hidden", bgType !== "panoramic")
      }
      if (bgType === "panoramic") {
        this._updatePanoramicSliceOverlay()
      }
      if (bgType === "image" || bgType === "panoramic") {
        this._ensureBackgroundImageLoaded()
      }

      // Sync visual bg-type-btn active states
      this.element.querySelectorAll(".bg-type-btn").forEach(btn => {
        btn.classList.toggle("active", btn.dataset.bgType === bgType)
      })
    }

    if (this.hasScreenshotPaddingTarget && this.hasPaddingLabelTarget) {
      this.paddingLabelTarget.textContent = `${this.screenshotPaddingTarget.value}%`
    }
    if (this.hasScreenshotOffsetYTarget && this.hasScreenshotOffsetYLabelTarget) {
      this.screenshotOffsetYLabelTarget.textContent = `${this.screenshotOffsetYTarget.value}%`
    }

    // Update slider labels
    if (this.hasCaptionZoneSizeTarget && this.hasCaptionZoneSizeLabelTarget) {
      this.captionZoneSizeLabelTarget.textContent = `${this.captionZoneSizeTarget.value}%`
    }
    if (this.hasCaptionLetterSpacingTarget && this.hasCaptionLetterSpacingLabelTarget) {
      this.captionLetterSpacingLabelTarget.textContent = `${this.captionLetterSpacingTarget.value}px`
    }
    if (this.hasCaptionLineHeightTarget && this.hasCaptionLineHeightLabelTarget) {
      this.captionLineHeightLabelTarget.textContent = this.captionLineHeightTarget.value
    }
    if (this.hasCaptionVerticalPositionTarget && this.hasCaptionVerticalPositionLabelTarget) {
      this.captionVerticalPositionLabelTarget.textContent = `${this.captionVerticalPositionTarget.value}%`
    }
    if (this.hasTextBgOpacityTarget && this.hasTextBgOpacityLabelTarget) {
      this.textBgOpacityLabelTarget.textContent = `${this.textBgOpacityTarget.value}%`
    }
    if (this.hasTextBgRadiusTarget && this.hasTextBgRadiusLabelTarget) {
      this.textBgRadiusLabelTarget.textContent = `${this.textBgRadiusTarget.value}px`
    }
    if (this.hasCaptionStrokeWidthTarget && this.hasCaptionStrokeWidthLabelTarget) {
      this.captionStrokeWidthLabelTarget.textContent = `${this.captionStrokeWidthTarget.value}px`
    }
    if (this.hasPatternScaleTarget && this.hasPatternScaleLabelTarget) {
      this.patternScaleLabelTarget.textContent = `${this.patternScaleTarget.value}%`
    }
    if (this.hasBackgroundImageBlurTarget && this.hasBackgroundImageBlurLabelTarget) {
      this.backgroundImageBlurLabelTarget.textContent = `${this.backgroundImageBlurTarget.value}px`
    }
    if (this.hasBackgroundImageBrightnessTarget && this.hasBackgroundImageBrightnessLabelTarget) {
      this.backgroundImageBrightnessLabelTarget.textContent = `${this.backgroundImageBrightnessTarget.value}%`
    }
    if (this.hasPanoramicBlurTarget && this.hasPanoramicBlurLabelTarget) {
      this.panoramicBlurLabelTarget.textContent = `${this.panoramicBlurTarget.value}px`
    }
    if (this.hasPanoramicBrightnessTarget && this.hasPanoramicBrightnessLabelTarget) {
      this.panoramicBrightnessLabelTarget.textContent = `${this.panoramicBrightnessTarget.value}%`
    }

    this._syncModeVisibility()

    if (this.currentSceneId) {
      const cached = this.imageCache.get(this.currentSceneId)
      if (cached) {
        const frameKey = this._buildCurrentSceneSettings().device_frame || "none"
        if (frameKey !== "none" && !this.frameImageCache.has(frameKey)) {
          this.ensureFrameLoaded(frameKey).then(() => {
            this._invalidateStaticLayer()
            this.renderPreview(cached)
          })
        } else {
          this.renderPreview(cached)
        }
      } else {
        this.loadAndRender(this.currentSceneId)
      }
    }

    this._syncCurrentSceneDraftToDOM()
    this._syncSectionBadges()
    this._pushHistoryDebounced()
  }

  _syncModeVisibility() {
    const mode = this._targetVal("captionMode", "zone")
    if (this.hasModeZoneControlsTarget) {
      this.modeZoneControlsTarget.classList.toggle("hidden", mode !== "zone")
    }
    if (this.hasModeOverlayControlsTarget) {
      this.modeOverlayControlsTarget.classList.toggle("hidden", mode !== "overlay")
    }
  }

  _syncEffectToggles() {
    if (this.hasTextBgControlsTarget) {
      this.textBgControlsTarget.classList.toggle("hidden", !this._targetChecked("textBgEnabled"))
    }
    if (this.hasCaptionStrokeControlsTarget) {
      this.captionStrokeControlsTarget.classList.toggle("hidden", !this._targetChecked("captionStrokeEnabled"))
    }
    if (this.hasCaptionGradientControlsTarget) {
      this.captionGradientControlsTarget.classList.toggle("hidden", !this._targetChecked("captionGradientEnabled"))
    }
  }

  // --- Perspective helpers & actions ---

  _getPerspectiveOpts() {
    const preset = this.hasPerspectivePresetTarget ? this.perspectivePresetTarget.value : "none"
    if (preset === "none") return null

    const rotateX = this.hasPerspectiveRotateXTarget ? parseFloat(this.perspectiveRotateXTarget.value) : 0
    const rotateY = this.hasPerspectiveRotateYTarget ? parseFloat(this.perspectiveRotateYTarget.value) : 0
    const distance = this.hasPerspectiveDistTarget ? parseInt(this.perspectiveDistTarget.value) : 2000
    if (rotateX === 0 && rotateY === 0) return null

    return {
      rotateX, rotateY, distance,
      shadow: this._targetChecked("perspectiveShadow"),
      reflection: this._targetChecked("perspectiveReflection")
    }
  }

  _getPerspectiveOptsFromSettings(settings) {
    const preset = settings.perspective_preset || "none"
    if (preset === "none") return null

    const rotateX = parseFloat(settings.perspective_rotate_x) || 0
    const rotateY = parseFloat(settings.perspective_rotate_y) || 0
    if (rotateX === 0 && rotateY === 0) return null

    return {
      rotateX, rotateY,
      distance: parseInt(settings.perspective_distance) || 2000,
      shadow: !!settings.perspective_shadow,
      reflection: !!settings.perspective_reflection
    }
  }

  _syncPerspectivePresetButtons(activeKey) {
    this.element.querySelectorAll(".perspective-preset-btn").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.preset === activeKey)
    })
  }

  updatePerspectivePreset(event) {
    const btn = event.currentTarget
    const preset = btn.dataset.preset

    if (this.hasPerspectivePresetTarget) this.perspectivePresetTarget.value = preset
    this._syncPerspectivePresetButtons(preset)

    if (preset === "none") {
      if (this.hasPerspectiveRotateXTarget) this.perspectiveRotateXTarget.value = 0
      if (this.hasPerspectiveRotateYTarget) this.perspectiveRotateYTarget.value = 0
      if (this.hasPerspectiveDistTarget) this.perspectiveDistTarget.value = 2000
      if (this.hasPerspectiveRotateXLabelTarget) this.perspectiveRotateXLabelTarget.textContent = "0\u00B0"
      if (this.hasPerspectiveRotateYLabelTarget) this.perspectiveRotateYLabelTarget.textContent = "0\u00B0"
      if (this.hasPerspectiveDistLabelTarget) this.perspectiveDistLabelTarget.textContent = "2000"
    } else {
      const rx = parseFloat(btn.dataset.rotateX) || 0
      const ry = parseFloat(btn.dataset.rotateY) || 0
      const dist = parseInt(btn.dataset.distance) || 2000
      if (this.hasPerspectiveRotateXTarget) this.perspectiveRotateXTarget.value = rx
      if (this.hasPerspectiveRotateYTarget) this.perspectiveRotateYTarget.value = ry
      if (this.hasPerspectiveDistTarget) this.perspectiveDistTarget.value = dist
      if (this.hasPerspectiveRotateXLabelTarget) this.perspectiveRotateXLabelTarget.textContent = `${rx}\u00B0`
      if (this.hasPerspectiveRotateYLabelTarget) this.perspectiveRotateYLabelTarget.textContent = `${ry}\u00B0`
      if (this.hasPerspectiveDistLabelTarget) this.perspectiveDistLabelTarget.textContent = dist
    }

    if (this.hasPerspectiveControlsTarget) {
      this.perspectiveControlsTarget.classList.toggle("hidden", preset === "none")
    }

    this.updatePreview()
    this._pushHistoryDebounced()
  }

  updatePerspective() {
    // Sync slider labels
    if (this.hasPerspectiveRotateXTarget && this.hasPerspectiveRotateXLabelTarget) {
      this.perspectiveRotateXLabelTarget.textContent = `${this.perspectiveRotateXTarget.value}\u00B0`
    }
    if (this.hasPerspectiveRotateYTarget && this.hasPerspectiveRotateYLabelTarget) {
      this.perspectiveRotateYLabelTarget.textContent = `${this.perspectiveRotateYTarget.value}\u00B0`
    }
    if (this.hasPerspectiveDistTarget && this.hasPerspectiveDistLabelTarget) {
      this.perspectiveDistLabelTarget.textContent = this.perspectiveDistTarget.value
    }

    // When sliders are manually changed, switch preset to "custom" if it was a named preset
    const currentPreset = this.hasPerspectivePresetTarget ? this.perspectivePresetTarget.value : "none"
    if (currentPreset !== "none" && currentPreset !== "custom") {
      const p = PERSPECTIVE_PRESETS[currentPreset]
      if (p) {
        const rx = this.hasPerspectiveRotateXTarget ? parseFloat(this.perspectiveRotateXTarget.value) : 0
        const ry = this.hasPerspectiveRotateYTarget ? parseFloat(this.perspectiveRotateYTarget.value) : 0
        const dist = this.hasPerspectiveDistTarget ? parseInt(this.perspectiveDistTarget.value) : 2000
        if (rx !== p.rotateX || ry !== p.rotateY || dist !== p.distance) {
          this.perspectivePresetTarget.value = "custom"
          this._syncPerspectivePresetButtons("custom")
        }
      }
    }

    this.updatePreview()
    this._pushHistoryDebounced()
  }

  toggleTextBg() {
    if (this.hasTextBgControlsTarget) {
      this.textBgControlsTarget.classList.toggle("hidden", !this._targetChecked("textBgEnabled"))
    }
    this.updatePreview()
  }

  toggleStroke() {
    if (this.hasCaptionStrokeControlsTarget) {
      this.captionStrokeControlsTarget.classList.toggle("hidden", !this._targetChecked("captionStrokeEnabled"))
    }
    this.updatePreview()
  }

  toggleGradient() {
    if (this.hasCaptionGradientControlsTarget) {
      this.captionGradientControlsTarget.classList.toggle("hidden", !this._targetChecked("captionGradientEnabled"))
    }
    this.updatePreview()
  }

  toggleSceneOverride() {
    const isEnabled = this._targetChecked("sceneOverrideEnabled")
    if (this.hasSceneOverrideControlsTarget) {
      this.sceneOverrideControlsTarget.classList.toggle("hidden", !isEnabled)
    }
    this._syncOverrideVisualState(isEnabled)
    this.updatePreview()
  }

  _syncOverrideVisualState(isEnabled) {
    if (this.hasOverridableControlsTarget) {
      this.overridableControlsTarget.classList.toggle("override-active", isEnabled)
    }
    if (this.hasOverrideActiveIndicatorTarget) {
      this.overrideActiveIndicatorTarget.classList.toggle("hidden", !isEnabled)
    }
  }

  _syncSectionBadges() {
    if (this.hasEffectsActiveBadgeTarget) {
      const anyEffectOn = this._targetChecked("captionGradientEnabled")
                       || this._targetChecked("textBgEnabled")
                       || this._targetChecked("captionStrokeEnabled")
      this.effectsActiveBadgeTarget.classList.toggle("hidden", !anyEffectOn)
    }
    if (this.hasOverrideBadgeTarget) {
      this.overrideBadgeTarget.classList.toggle("hidden", !this._targetChecked("sceneOverrideEnabled"))
    }
  }

  setAlignment(event) {
    const align = event.currentTarget.dataset.align
    if (this.hasCaptionTextAlignTarget) {
      this.captionTextAlignTarget.value = align
    }

    // Update button states
    if (this.hasAlignLeftTarget) this.alignLeftTarget.classList.toggle("btn-active", align === "left")
    if (this.hasAlignCenterTarget) this.alignCenterTarget.classList.toggle("btn-active", align === "center")
    if (this.hasAlignRightTarget) this.alignRightTarget.classList.toggle("btn-active", align === "right")

    this.updatePreview()
  }

  async fontChanged() {
    const family = this._targetVal("captionFontFamily", "Inter")
    const weight = this._targetIntVal("captionFontWeight", 700)
    await loadFontForCanvas(family, weight)
    this.updatePreview()
  }

  async subtitleFontChanged() {
    const family = this._targetVal("subtitleFontFamily", "Inter")
    const weight = this._targetIntVal("subtitleFontWeight", 400)
    await loadFontForCanvas(family, weight)
    this.updatePreview()
  }

  clearVerticalPosition() {
    if (this.hasCaptionVerticalPositionTarget) {
      this.captionVerticalPositionTarget.value = ""
    }
    if (this.hasCaptionVerticalPositionLabelTarget) {
      this.captionVerticalPositionLabelTarget.textContent = "Auto"
    }
    this.updatePreview()
  }

  // --- Drag-and-drop text positioning ---

  _isAnyInteractionActive() {
    return this._isDragging || this._isResizing || this._isRotating || !!this._stickerInteraction?.active
  }

  _cacheCanvasPointerMetrics() {
    if (!this.hasCanvasTarget) return
    const canvas = this.canvasTarget
    const rect = canvas.getBoundingClientRect()
    if (!rect.width || !rect.height) {
      this._canvasRectCache = null
      this._canvasScaleX = 1
      this._canvasScaleY = 1
      return
    }
    this._canvasRectCache = rect
    this._canvasScaleX = canvas.width / rect.width
    this._canvasScaleY = canvas.height / rect.height
  }

  _canvasCoords(event) {
    const canvas = this.canvasTarget
    const rect = this._canvasRectCache || canvas.getBoundingClientRect()
    const scaleX = this._canvasRectCache ? this._canvasScaleX : (canvas.width / rect.width)
    const scaleY = this._canvasRectCache ? this._canvasScaleY : (canvas.height / rect.height)
    const clientX = event.touches ? event.touches[0].clientX : event.clientX
    const clientY = event.touches ? event.touches[0].clientY : event.clientY
    const pos = {
      x: (clientX - rect.left) * scaleX,
      y: (clientY - rect.top) * scaleY
    }

    // When perspective is active, map pointer from transformed canvas back to source space.
    if (this._perspectiveQuad) {
      const mapped = inversePerspectivePoint(pos.x, pos.y, this._perspectiveQuad, canvas.width, canvas.height)
      if (mapped) return mapped

      // Avoid dead drag zones outside the transformed quad by falling back
      // to clamped canvas coordinates while interacting.
      if (this._isAnyInteractionActive()) {
        return {
          x: Math.max(0, Math.min(canvas.width, pos.x)),
          y: Math.max(0, Math.min(canvas.height, pos.y))
        }
      }

      return null
    }

    return pos
  }

  _hitTestText(pos) {
    if (!this._lastTextBounds) return false
    const b = this._lastTextBounds
    const margin = 10

    // Un-rotate test point when text is rotated
    let testX = pos.x
    let testY = pos.y
    if (b.rotation && b.rotation !== 0) {
      const rad = -b.rotation * Math.PI / 180
      const cos = Math.cos(rad)
      const sin = Math.sin(rad)
      const dx = pos.x - b.centerX
      const dy = pos.y - b.centerY
      testX = b.centerX + dx * cos - dy * sin
      testY = b.centerY + dx * sin + dy * cos
    }

    return testX >= b.x - margin && testX <= b.x + b.width + margin &&
           testY >= b.y - margin && testY <= b.y + b.height + margin
  }

  _onCanvasHover(event) {
    if (this._isAnyInteractionActive()) return

    const mode = this.hasLayoutModeTarget ? this.layoutModeTarget.value : "auto"
    const pos = this._canvasCoords(event)

    if (!pos) {
      this.canvasTarget.style.cursor = "default"
      return
    }

    // Fast path: no stickers and auto mode — only need text hit-test
    if (this._stickers.length === 0 && mode !== "freeform") {
      this.canvasTarget.style.cursor = this._hitTestText(pos) ? "pointer" : "default"
      return
    }

    // Check sticker hit areas first (stickers render on top)
    if (this._selectedStickerId) {
      if (hitTestStickerDelete(pos, this._stickerBounds, this._selectedStickerId)) {
        this.canvasTarget.style.cursor = "pointer"
        return
      }
      if (hitTestStickerRotation(pos, this._stickerBounds, this._selectedStickerId)) {
        this.canvasTarget.style.cursor = "crosshair"
        return
      }
      const stickerResizeIdx = hitTestStickerResize(pos, this._stickerBounds, this._selectedStickerId)
      if (stickerResizeIdx >= 0) {
        const cursors = ["nw-resize", "ne-resize", "sw-resize", "se-resize"]
        this.canvasTarget.style.cursor = cursors[stickerResizeIdx]
        return
      }
    }
    const stickerHit = hitTestSticker(pos, this._stickerBounds)
    if (stickerHit) {
      this.canvasTarget.style.cursor = this._selectedStickerId === stickerHit ? "grab" : "pointer"
      return
    }

    // In auto mode, show pointer when hovering over text (click to enter freeform)
    if (mode !== "freeform") {
      this.canvasTarget.style.cursor = this._hitTestText(pos) ? "pointer" : "default"
      return
    }

    // In freeform with visible handles, check handle hit areas
    if (this._handlesVisible) {
      if (this._hitTestRotationHandle(pos)) {
        this.canvasTarget.style.cursor = "crosshair"
        return
      }
      const handleIdx = this._hitTestResizeHandle(pos)
      if (handleIdx >= 0) {
        const cursors = ["nw-resize", "ne-resize", "sw-resize", "se-resize"]
        this.canvasTarget.style.cursor = cursors[handleIdx]
        return
      }
    }

    this.canvasTarget.style.cursor = this._hitTestText(pos) ? "grab" : "default"
  }

  onCanvasMouseDown(event) {
    this._handlePointerDown(event, false)
  }

  onCanvasTouchStart(event) {
    this._handlePointerDown(event, true)
  }

  _handlePointerDown(event, isTouch) {
    if (!this.hasCanvasTarget) return

    const mode = this.hasLayoutModeTarget ? this.layoutModeTarget.value : "auto"
    const pos = this._canvasCoords(event)

    if (!pos) return

    // Check sticker interactions FIRST (stickers render on top)
    if (this._selectedStickerId) {
      // Delete button
      if (hitTestStickerDelete(pos, this._stickerBounds, this._selectedStickerId)) {
        event.preventDefault()
        this.deleteSelectedSticker()
        return
      }
      // Rotation handle
      if (hitTestStickerRotation(pos, this._stickerBounds, this._selectedStickerId)) {
        event.preventDefault()
        this._startStickerRotate(pos)
        this._bindDragListeners(isTouch,
          (e) => { const p = this._canvasCoords(e); if (p) this._duringStickerRotate(p) },
          () => this._endStickerRotate()
        )
        return
      }
      // Resize corner handles
      const stickerResizeIdx = hitTestStickerResize(pos, this._stickerBounds, this._selectedStickerId)
      if (stickerResizeIdx >= 0) {
        event.preventDefault()
        this._startStickerResize(pos, stickerResizeIdx)
        this._bindDragListeners(isTouch,
          (e) => { const p = this._canvasCoords(e); if (p) this._duringStickerResize(p) },
          () => this._endStickerResize()
        )
        return
      }
    }

    // Check sticker body hit
    const stickerHit = hitTestSticker(pos, this._stickerBounds)
    if (stickerHit) {
      event.preventDefault()
      if (this._selectedStickerId !== stickerHit) {
        this._selectedStickerId = stickerHit
        this._syncStickerControlsVisibility()
        this.updatePreview()
        return
      }
      // Start dragging selected sticker
      this._startStickerDrag(pos)
      this._bindDragListeners(isTouch,
        (e) => { const p = this._canvasCoords(e); if (p) this._duringStickerDrag(p) },
        () => this._endStickerDrag()
      )
      return
    }

    // Deselect sticker if clicking elsewhere
    if (this._selectedStickerId) {
      this._selectedStickerId = null
      this._syncStickerControlsVisibility()
      this.updatePreview()
    }

    if (!this._lastTextBounds) return

    // In auto mode, clicking/tapping on text switches to freeform
    if (mode !== "freeform") {
      if (this._hitTestText(pos)) {
        event.preventDefault()
        this._switchToFreeformWithCurrentPosition()
        this._startDrag(pos)
        this._bindDragListeners(isTouch,
          (e) => { const p = this._canvasCoords(e); if (p) this._duringDrag(p) },
          () => this._endDrag()
        )
      }
      return
    }

    // Check rotation handle first (farthest from text body)
    if (this._hitTestRotationHandle(pos)) {
      event.preventDefault()
      this._startRotate(pos)
      this._bindDragListeners(isTouch,
        (e) => { const p = this._canvasCoords(e); if (p) this._duringRotate(p) },
        () => this._endRotate()
      )
      return
    }

    // Check resize handles
    const handleIdx = this._hitTestResizeHandle(pos)
    if (handleIdx >= 0) {
      event.preventDefault()
      this._startResize(pos, handleIdx)
      this._bindDragListeners(isTouch,
        (e) => { const p = this._canvasCoords(e); if (p) this._duringResize(p) },
        () => this._endResize()
      )
      return
    }

    if (this._hitTestText(pos)) {
      // Show handles if hidden, then start drag
      if (!this._handlesVisible) {
        this._handlesVisible = true
        this.updatePreview()
        return
      }
      event.preventDefault()
      this._startDrag(pos)
      this._bindDragListeners(isTouch,
        (e) => { const p = this._canvasCoords(e); if (p) this._duringDrag(p) },
        () => this._endDrag()
      )
      return
    }

    // Clicked/tapped outside text — hide handles
    if (this._handlesVisible) {
      this._handlesVisible = false
      this.updatePreview()
    }
  }

  _bindDragListeners(isTouch, moveFn, endFn) {
    this._cacheCanvasPointerMetrics()
    if (isTouch) {
      this._boundDragMove = (e) => { e.preventDefault(); moveFn(e) }
      this._boundDragEnd = endFn
      document.addEventListener("touchmove", this._boundDragMove, { passive: false })
      document.addEventListener("touchend", this._boundDragEnd)
    } else {
      this._boundDragMove = moveFn
      this._boundDragEnd = endFn
      document.addEventListener("mousemove", this._boundDragMove)
      document.addEventListener("mouseup", this._boundDragEnd)
    }
  }

  _clampTextCenterToCanvas(centerX, centerY, bounds = this._lastTextBounds) {
    if (!bounds) return { x: centerX, y: centerY }

    const edgePadX = Math.max(6, bounds.canvasWidth * 0.01, bounds.width * 0.05)
    const edgePadY = Math.max(6, bounds.canvasHeight * 0.01, bounds.height * 0.08)

    const clampAxis = (value, halfSize, totalSize, edgePad = 0) => {
      if (!Number.isFinite(totalSize) || totalSize <= 0) return 0
      if (!Number.isFinite(value)) return totalSize / 2
      if (!Number.isFinite(halfSize)) return totalSize / 2
      const min = halfSize + edgePad
      const max = totalSize - halfSize - edgePad
      if (min >= max) return totalSize / 2
      return Math.max(min, Math.min(max, value))
    }

    return {
      x: clampAxis(centerX, bounds.width / 2, bounds.canvasWidth, edgePadX),
      y: clampAxis(centerY, bounds.height / 2, bounds.canvasHeight, edgePadY)
    }
  }

  _startDrag(pos) {
    this._beginInteraction()
    this._isDragging = true
    this._dragStartPos = pos
    const b = this._lastTextBounds
    this._dragPointerOffset = b
      ? { x: pos.x - b.centerX, y: pos.y - b.centerY }
      : { x: 0, y: 0 }
    this.canvasTarget.style.cursor = "grabbing"
  }

  _duringDrag(pos) {
    if (!this._isDragging || !this._lastTextBounds) return

    const b = this._lastTextBounds
    const offset = this._dragPointerOffset || { x: 0, y: 0 }
    const targetCenterX = pos.x - offset.x
    const targetCenterY = pos.y - offset.y
    const clampedCenter = this._clampTextCenterToCanvas(targetCenterX, targetCenterY, b)
    const centerX = (clampedCenter.x / b.canvasWidth) * 100
    const centerY = (clampedCenter.y / b.canvasHeight) * 100

    this._liveDragPosition = {
      x: Math.round(centerX * 10) / 10,
      y: Math.round(centerY * 10) / 10
    }

    this._invalidateStaticLayer()
    this._scheduleRender()
  }

  _endDrag() {
    this._isDragging = false
    this._endInteraction()
    this._dragStartPos = null
    this._dragPointerOffset = null
    this.canvasTarget.style.cursor = "default"
    if (this._liveDragPosition) {
      this._setDragPosition(this._liveDragPosition.x, this._liveDragPosition.y)
      this._liveDragPosition = null
    }
    this._removeDragListeners()
    this._scheduleRender()
    this._pushHistoryImmediate()
  }

  _setDragPosition(x, y) {
    const sceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null
    if (!sceneData) return

    let overrides = {}
    try { overrides = JSON.parse(sceneData.dataset.sceneOverrides || "{}") } catch {}

    overrides.text_position_x = Math.round(x * 10) / 10
    overrides.text_position_y = Math.round(y * 10) / 10
    sceneData.dataset.sceneOverrides = JSON.stringify(overrides)
    this._updateSceneDirtyState(sceneData.dataset.sceneId)

    if (this.hasDragPositionLabelTarget) {
      this.dragPositionLabelTarget.textContent = `${overrides.text_position_x}%, ${overrides.text_position_y}%`
    }
    if (this.hasResetDragButtonTarget) {
      this.resetDragButtonTarget.classList.remove("hidden")
    }
  }

  resetDragPosition() {
    const sceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null
    if (!sceneData) return

    let overrides = {}
    try { overrides = JSON.parse(sceneData.dataset.sceneOverrides || "{}") } catch {}

    delete overrides.text_position_x
    delete overrides.text_position_y
    delete overrides.text_rotation
    sceneData.dataset.sceneOverrides = JSON.stringify(overrides)
    this._updateSceneDirtyState(sceneData.dataset.sceneId)

    if (this.hasDragPositionLabelTarget) {
      this.dragPositionLabelTarget.textContent = "Auto"
    }
    if (this.hasResetDragButtonTarget) {
      this.resetDragButtonTarget.classList.add("hidden")
    }
    if (this.hasRotationLabelTarget) {
      this.rotationLabelTarget.textContent = "0°"
    }
    if (this.hasResetRotationButtonTarget) {
      this.resetRotationButtonTarget.classList.add("hidden")
    }

    this._lastTextBounds = null
    this._lastResizeHandles = null
    this._lastRotationHandle = null

    // Switch back to auto mode
    this._syncPositioningModeUI("auto")
    this.updatePreview()
  }

  // --- Positioning mode (Auto / Freeform) ---

  setPositioningMode(event) {
    const mode = event.currentTarget.dataset.mode
    if (mode === "auto") {
      // Switching to auto clears any drag position
      this._clearDragPositionSilently()
    } else {
      this._handlesVisible = true
    }
    this._syncPositioningModeUI(mode)
    this.updatePreview()
  }

  _syncPositioningModeUI(mode) {
    if (this.hasLayoutModeTarget) this.layoutModeTarget.value = mode
    if (this.hasAutoLayoutPanelTarget) this.autoLayoutPanelTarget.classList.toggle("hidden", mode !== "auto")
    if (this.hasFreeformPanelTarget) this.freeformPanelTarget.classList.toggle("hidden", mode !== "freeform")
    if (this.hasPosModeBtnAutoTarget) {
      this.posModeBtnAutoTarget.classList.toggle("btn-active", mode === "auto")
      this.posModeBtnAutoTarget.classList.toggle("btn-ghost", mode !== "auto")
    }
    if (this.hasPosModeBtnFreeformTarget) {
      this.posModeBtnFreeformTarget.classList.toggle("btn-active", mode === "freeform")
      this.posModeBtnFreeformTarget.classList.toggle("btn-ghost", mode !== "freeform")
    }
    if (this.hasAlignmentControlsTarget) {
      this.alignmentControlsTarget.classList.toggle("hidden", mode !== "auto")
    }
  }

  _switchToFreeformWithCurrentPosition() {
    // Capture current text position from bounds before switching
    const b = this._lastTextBounds
    if (b) {
      const center = this._clampTextCenterToCanvas(b.x + b.width / 2, b.y + b.height / 2, b)
      this._setDragPosition(
        (center.x / b.canvasWidth) * 100,
        (center.y / b.canvasHeight) * 100
      )
    }
    this._handlesVisible = true
    this._syncPositioningModeUI("freeform")
    this.updatePreview()
    this._pushHistoryImmediate()
  }

  _clearDragPositionSilently() {
    const sceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null
    if (!sceneData) return

    let overrides = {}
    try { overrides = JSON.parse(sceneData.dataset.sceneOverrides || "{}") } catch {}

    if (overrides.text_position_x == null && overrides.text_position_y == null && overrides.text_rotation == null) return

    delete overrides.text_position_x
    delete overrides.text_position_y
    delete overrides.text_rotation
    sceneData.dataset.sceneOverrides = JSON.stringify(overrides)
    this._updateSceneDirtyState(sceneData.dataset.sceneId)

    if (this.hasDragPositionLabelTarget) {
      this.dragPositionLabelTarget.textContent = "Auto"
    }
    if (this.hasResetDragButtonTarget) {
      this.resetDragButtonTarget.classList.add("hidden")
    }
    if (this.hasRotationLabelTarget) {
      this.rotationLabelTarget.textContent = "0°"
    }
    if (this.hasResetRotationButtonTarget) {
      this.resetRotationButtonTarget.classList.add("hidden")
    }

    this._lastTextBounds = null
    this._lastResizeHandles = null
    this._lastRotationHandle = null
  }

  // --- Rotation ---

  _hitTestRotationHandle(pos) {
    if (!this._lastRotationHandle) return false
    const h = this._lastRotationHandle
    const dx = pos.x - h.x
    const dy = pos.y - h.y
    return Math.sqrt(dx * dx + dy * dy) < 14
  }

  _startRotate(pos) {
    this._beginInteraction()
    this._isRotating = true
    const b = this._lastTextBounds
    this._rotateStartAngle = Math.atan2(pos.y - b.centerY, pos.x - b.centerX)
    this._rotateStartRotation = b.rotation || 0
    this.canvasTarget.style.cursor = "crosshair"
  }

  _duringRotate(pos) {
    if (!this._isRotating || !this._lastTextBounds) return

    const b = this._lastTextBounds
    const currentAngle = Math.atan2(pos.y - b.centerY, pos.x - b.centerX)
    const deltaAngle = (currentAngle - this._rotateStartAngle) * 180 / Math.PI
    let newRotation = this._rotateStartRotation + deltaAngle

    // Normalize to -180..180
    while (newRotation > 180) newRotation -= 360
    while (newRotation < -180) newRotation += 360

    // Snap to 0/45/90/135/180 when within 3 degrees
    const snapAngles = [0, 45, 90, 135, 180, -45, -90, -135, -180]
    for (const snap of snapAngles) {
      if (Math.abs(newRotation - snap) < 3) {
        newRotation = snap
        break
      }
    }

    this._liveRotation = Math.round(newRotation * 10) / 10

    this._invalidateStaticLayer()
    this._scheduleRender()
  }

  _endRotate() {
    this._isRotating = false
    this._endInteraction()
    this.canvasTarget.style.cursor = "default"
    if (this._liveRotation != null) {
      this._setRotation(this._liveRotation)
      this._liveRotation = null
    }
    this._removeDragListeners()
    this._scheduleRender()
    this._pushHistoryImmediate()
  }

  _setRotation(degrees) {
    const sceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null
    if (!sceneData) return

    let overrides = {}
    try { overrides = JSON.parse(sceneData.dataset.sceneOverrides || "{}") } catch {}

    if (degrees === 0) {
      delete overrides.text_rotation
    } else {
      overrides.text_rotation = degrees
    }
    sceneData.dataset.sceneOverrides = JSON.stringify(overrides)
    this._updateSceneDirtyState(sceneData.dataset.sceneId)

    if (this.hasRotationLabelTarget) {
      this.rotationLabelTarget.textContent = `${degrees}°`
    }
    if (this.hasResetRotationButtonTarget) {
      this.resetRotationButtonTarget.classList.toggle("hidden", degrees === 0)
    }
  }

  resetRotation() {
    this._setRotation(0)
    this.updatePreview()
  }

  // --- Resize handles ---

  _hitTestResizeHandle(pos) {
    if (!this._lastResizeHandles) return -1
    const hitRadius = 12
    for (let i = 0; i < this._lastResizeHandles.length; i++) {
      const [hx, hy] = this._lastResizeHandles[i]
      const dx = pos.x - hx
      const dy = pos.y - hy
      if (Math.sqrt(dx * dx + dy * dy) < hitRadius) {
        return i
      }
    }
    return -1
  }

  _startResize(pos, handleIdx) {
    this._beginInteraction()
    this._isResizing = true
    this._resizeHandleIndex = handleIdx
    this._resizeStartY = pos.y

    // Read effective title size (considering scene override)
    if (this._targetChecked("sceneOverrideEnabled") && this.hasSceneOverrideCaptionFontSizeTarget) {
      this._resizeStartTitleSize = parseInt(this.sceneOverrideCaptionFontSizeTarget.value) || 32
    } else {
      this._resizeStartTitleSize = this._targetIntVal("captionFontSize", 32)
    }
    // Read effective subtitle size (considering scene override)
    if (this._targetChecked("sceneOverrideEnabled") && this.hasSceneOverrideSubtitleFontSizeTarget) {
      this._resizeStartSubtitleSize = parseInt(this.sceneOverrideSubtitleFontSizeTarget.value) || 20
    } else {
      this._resizeStartSubtitleSize = this._targetIntVal("subtitleFontSize", 20)
    }

    this.canvasTarget.style.cursor = "grabbing"
  }

  _duringResize(pos) {
    if (!this._isResizing) return

    const deltaY = pos.y - this._resizeStartY
    // Bottom handles (2,3): drag down = bigger. Top handles (0,1): drag up = bigger.
    const sign = (this._resizeHandleIndex >= 2) ? 1 : -1
    const rawDelta = deltaY * sign
    const scale = this.canvasTarget.width / 1080
    const fontDelta = rawDelta / scale * 0.12

    const newTitleSize = Math.round(Math.max(16, Math.min(144, this._resizeStartTitleSize + fontDelta)))
    const ratio = this._resizeStartSubtitleSize / Math.max(1, this._resizeStartTitleSize)
    const newSubtitleSize = Math.round(Math.max(10, Math.min(96, this._resizeStartSubtitleSize + fontDelta * ratio)))

    // Update main sliders
    if (this.hasCaptionFontSizeTarget) this.captionFontSizeTarget.value = newTitleSize
    if (this.hasSubtitleFontSizeTarget) this.subtitleFontSizeTarget.value = newSubtitleSize

    // Also update scene override if active
    if (this._targetChecked("sceneOverrideEnabled")) {
      if (this.hasSceneOverrideCaptionFontSizeTarget) {
        this.sceneOverrideCaptionFontSizeTarget.value = newTitleSize
      }
      if (this.hasSceneOverrideSubtitleFontSizeTarget) {
        this.sceneOverrideSubtitleFontSizeTarget.value = newSubtitleSize
      }
    }

    this._invalidateStaticLayer()
    this._scheduleRender()
  }

  _endResize() {
    this._isResizing = false
    this._endInteraction()
    this._resizeHandleIndex = -1
    this.canvasTarget.style.cursor = "default"
    this._removeDragListeners()
    this._scheduleRender()
    this._pushHistoryImmediate()
  }

  syncCaptionColor() {
    if (this.hasCaptionColorTextTarget && this.hasCaptionColorTarget) {
      const val = this.captionColorTextTarget.value
      if (/^#[0-9a-fA-F]{6}$/.test(val)) {
        this.captionColorTarget.value = val
        this.updatePreview()
      }
    }
  }

  syncSubtitleColor() {
    if (this.hasSubtitleColorTextTarget && this.hasSubtitleColorTarget) {
      const val = this.subtitleColorTextTarget.value
      if (/^#[0-9a-fA-F]{6}$/.test(val)) {
        this.subtitleColorTarget.value = val
        this.updatePreview()
      }
    }
  }

  syncBackgroundColor() {
    if (this.hasBackgroundColorTextTarget && this.hasBackgroundColorTarget) {
      const val = this.backgroundColorTextTarget.value
      if (/^#[0-9a-fA-F]{6}$/.test(val)) {
        this.backgroundColorTarget.value = val
        this.updatePreview()
      }
    }
  }

  // --- Mesh gradient preset selection ---

  selectBgType(event) {
    const bgType = event.currentTarget.dataset.bgType
    if (!bgType || !this.hasBackgroundTypeTarget) return

    // Sync blur/brightness values between image and panoramic controls
    // so switching modes preserves the current values.
    const prevBgType = this.backgroundTypeTarget.value
    if (bgType === "panoramic" && prevBgType === "image") {
      if (this.hasPanoramicBlurTarget && this.hasBackgroundImageBlurTarget) {
        this.panoramicBlurTarget.value = this.backgroundImageBlurTarget.value
      }
      if (this.hasPanoramicBrightnessTarget && this.hasBackgroundImageBrightnessTarget) {
        this.panoramicBrightnessTarget.value = this.backgroundImageBrightnessTarget.value
      }
    } else if (bgType === "image" && prevBgType === "panoramic") {
      if (this.hasBackgroundImageBlurTarget && this.hasPanoramicBlurTarget) {
        this.backgroundImageBlurTarget.value = this.panoramicBlurTarget.value
      }
      if (this.hasBackgroundImageBrightnessTarget && this.hasPanoramicBrightnessTarget) {
        this.backgroundImageBrightnessTarget.value = this.panoramicBrightnessTarget.value
      }
    }

    this.backgroundTypeTarget.value = bgType

    // Update active state on visual grid buttons
    const container = event.currentTarget.closest(".grid")
    if (container) {
      container.querySelectorAll(".bg-type-btn").forEach(btn => {
        btn.classList.toggle("active", btn.dataset.bgType === bgType)
      })
    }

    this.updatePreview()
    this._pushHistoryDebounced()
  }

  // --- Dark mode variant toggle ---

  toggleDarkMode() {
    this._pushHistoryImmediate()

    if (this._darkModeActive) {
      // Revert to original (light) settings
      if (this._darkModePreToggleSettings) {
        this._applySettingsToUI(this._darkModePreToggleSettings)
        this._darkModePreToggleSettings = null
      }
      this._darkModeActive = false
    } else {
      // Save current settings before transforming
      this._darkModePreToggleSettings = this.getCurrentSettings()
      const darkSettings = generateDarkVariant(this._darkModePreToggleSettings)
      this._applySettingsToUI(darkSettings)
      this._darkModeActive = true
    }

    // Update the toggle button visual state
    this._syncDarkModeToggleUI()

    this.updatePreview()
    this._pushHistoryImmediate()
  }

  _syncDarkModeToggleUI() {
    if (this.hasDarkModeToggleTarget) {
      this.darkModeToggleTarget.classList.toggle("btn-active", this._darkModeActive)
      this.darkModeToggleTarget.title = this._darkModeActive
        ? "Switch back to light variant"
        : "Generate dark variant"
    }
    if (this.hasDarkModeIconTarget) {
      this.darkModeIconTarget.classList.toggle("fa-moon", !this._darkModeActive)
      this.darkModeIconTarget.classList.toggle("fa-sun", this._darkModeActive)
    }
  }

  selectMeshPreset(event) {
    const presetKey = event.currentTarget.dataset.preset
    if (!presetKey || !MESH_PRESETS[presetKey]) return

    if (this.hasMeshPresetTarget) this.meshPresetTarget.value = presetKey

    // Update color pickers to preset defaults
    const preset = MESH_PRESETS[presetKey]
    const blobs = preset.blobs
    if (this.hasMeshColor1Target && blobs[0]) this.meshColor1Target.value = blobs[0].color
    if (this.hasMeshColor2Target && blobs[1]) this.meshColor2Target.value = blobs[1].color
    if (this.hasMeshColor3Target && blobs[2]) this.meshColor3Target.value = blobs[2].color

    // Highlight selected preset
    const container = event.currentTarget.closest("[data-mesh-grid]")
    if (container) {
      container.querySelectorAll("[data-preset]").forEach(btn => {
        btn.classList.toggle("ring-2", btn.dataset.preset === presetKey)
        btn.classList.toggle("ring-primary", btn.dataset.preset === presetKey)
      })
    }

    this.updatePreview()
  }

  // --- Background image helpers ---

  _ensureBackgroundImageLoaded() {
    if (!this.backgroundImageUrlValue) return
    if (this._backgroundImageLoaded || this._backgroundImageLoading) return
    this._loadBackgroundImage(this.backgroundImageUrlValue).then((ok) => {
      if (!ok) this.backgroundImageUrlValue = ""
    })
  }

  _loadBackgroundImage(url) {
    this._backgroundImageLoading = true
    return new Promise((resolve) => {
      const img = new Image()
      img.crossOrigin = "anonymous"
      img.onload = () => {
        this._backgroundImageLoading = false
        this._backgroundImage = img
        this._backgroundImageLoaded = true
        // Update preview thumbnail if visible
        if (this.hasBackgroundImagePreviewTarget) {
          this.backgroundImagePreviewTarget.src = url
          this.backgroundImagePreviewTarget.classList.remove("hidden")
        }
        if (this.hasBackgroundImageRemoveBtnTarget) {
          this.backgroundImageRemoveBtnTarget.classList.remove("hidden")
        }
        if (this.hasPanoramicPreviewTarget) {
          this.panoramicPreviewTarget.src = url
          this.panoramicPreviewTarget.classList.remove("hidden")
        }
        if (this.hasPanoramicRemoveBtnTarget) {
          this.panoramicRemoveBtnTarget.classList.remove("hidden")
        }
        this.updatePreview()
        resolve(true)
      }
      img.onerror = () => {
        this._backgroundImageLoading = false
        console.warn("Failed to load background image (missing/expired URL or blob):", url)
        this._backgroundImage = null
        this._backgroundImageLoaded = false
        if (this.hasBackgroundImagePreviewTarget) {
          this.backgroundImagePreviewTarget.classList.add("hidden")
          this.backgroundImagePreviewTarget.src = ""
        }
        if (this.hasPanoramicPreviewTarget) {
          this.panoramicPreviewTarget.classList.add("hidden")
          this.panoramicPreviewTarget.src = ""
        }
        if (this.hasBackgroundImageRemoveBtnTarget) {
          this.backgroundImageRemoveBtnTarget.classList.add("hidden")
        }
        if (this.hasPanoramicRemoveBtnTarget) {
          this.panoramicRemoveBtnTarget.classList.add("hidden")
        }
        this.updatePreview()
        resolve(false)
      }
      img.src = url
    })
  }

  async uploadBackgroundImage(event) {
    const file = event.target.files[0]
    if (!file) return

    const formData = new FormData()
    formData.append("file", file)

    const projectUrl = this.projectUrlValue
    try {
      const response = await fetch(`${projectUrl}/upload_background_image`, {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        }
      })
      const data = await response.json()
      if (response.ok && data.url) {
        this.backgroundImageUrlValue = data.url
        const ok = await this._loadBackgroundImage(data.url)
        if (!ok) {
          this.backgroundImageUrlValue = ""
          alert("Image uploaded but could not be loaded. Please try again.")
        }
      } else {
        console.error("Upload failed:", data.message)
      }
    } catch (e) {
      console.error("Upload failed:", e)
    }

    // Reset file input
    event.target.value = ""
  }

  async removeBackgroundImage() {
    const projectUrl = this.projectUrlValue
    try {
      await fetch(`${projectUrl}/remove_background_image`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
          "Accept": "application/json"
        }
      })
    } catch (e) {
      console.error("Remove failed:", e)
    }

    this._backgroundImage = null
    this._backgroundImageLoaded = false
    this.backgroundImageUrlValue = ""

    if (this.hasBackgroundImagePreviewTarget) {
      this.backgroundImagePreviewTarget.classList.add("hidden")
      this.backgroundImagePreviewTarget.src = ""
    }
    if (this.hasBackgroundImageRemoveBtnTarget) {
      this.backgroundImageRemoveBtnTarget.classList.add("hidden")
    }
    if (this.hasPanoramicPreviewTarget) {
      this.panoramicPreviewTarget.classList.add("hidden")
      this.panoramicPreviewTarget.src = ""
    }
    if (this.hasPanoramicRemoveBtnTarget) {
      this.panoramicRemoveBtnTarget.classList.add("hidden")
    }

    this.updatePreview()
  }

  _drawPanoramicSlice(ctx, img, x, y, w, h, sceneIndex, totalScenes) {
    totalScenes = Math.max(totalScenes, 1)
    sceneIndex = Math.max(0, Math.min(sceneIndex, totalScenes - 1))

    const sliceWidth = img.width / totalScenes
    const sx = sceneIndex * sliceWidth

    const sliceRatio = sliceWidth / img.height
    const canvasRatio = w / h

    let srcX = sx, srcY = 0, srcW = sliceWidth, srcH = img.height

    if (sliceRatio > canvasRatio) {
      const neededWidth = img.height * canvasRatio
      srcX = sx + (sliceWidth - neededWidth) / 2
      srcW = neededWidth
    } else {
      const neededHeight = sliceWidth / canvasRatio
      srcY = (img.height - neededHeight) / 2
      srcH = neededHeight
    }

    ctx.drawImage(img, srcX, srcY, srcW, srcH, x, y, w, h)
  }

  _drawImageCover(ctx, img, x, y, w, h) {
    const imgRatio = img.width / img.height
    const areaRatio = w / h
    let sw, sh, sx, sy

    if (imgRatio > areaRatio) {
      sh = img.height
      sw = img.height * areaRatio
      sx = (img.width - sw) / 2
      sy = 0
    } else {
      sw = img.width
      sh = img.width / areaRatio
      sx = 0
      sy = (img.height - sh) / 2
    }
    ctx.drawImage(img, sx, sy, sw, sh, x, y, w, h)
  }

  _drawImageContain(ctx, img, x, y, w, h) {
    const imgRatio = img.width / img.height
    const areaRatio = w / h
    let dw, dh, dx, dy

    if (imgRatio > areaRatio) {
      dw = w
      dh = w / imgRatio
      dx = x
      dy = y + (h - dh) / 2
    } else {
      dh = h
      dw = h * imgRatio
      dx = x + (w - dw) / 2
      dy = y
    }
    ctx.drawImage(img, dx, dy, dw, dh)
  }

  _updatePanoramicSliceOverlay() {
    if (!this.hasPanoramicSliceOverlayTarget) return
    const total = this._getTotalScenes()
    const currentIdx = this._getCurrentSceneIndex()
    const overlay = this.panoramicSliceOverlayTarget

    while (overlay.firstChild) overlay.removeChild(overlay.firstChild)

    for (let i = 0; i < total; i++) {
      const slice = document.createElement("div")
      slice.style.width = `${100 / total}%`
      slice.style.height = "100%"
      if (i < total - 1) {
        slice.classList.add("border-r", "border-white/50", "border-dashed")
      }
      if (i === currentIdx) {
        slice.classList.add("bg-primary/20")
      }
      overlay.appendChild(slice)
    }
  }

  // --- Pattern selection ---

  selectPattern(event) {
    const patternId = event.currentTarget.dataset.patternId
    if (!patternId) return

    if (this.hasPatternIdTarget) this.patternIdTarget.value = patternId

    // Highlight selected pattern
    const container = event.currentTarget.closest("[data-pattern-grid]")
    if (container) {
      container.querySelectorAll("[data-pattern-id]").forEach(btn => {
        btn.classList.toggle("ring-2", btn.dataset.patternId === patternId)
        btn.classList.toggle("ring-primary", btn.dataset.patternId === patternId)
      })
    }

    this.updatePreview()
  }

  syncPatternColor() {
    if (this.hasPatternColorTextTarget && this.hasPatternColorTarget) {
      const val = this.patternColorTextTarget.value
      if (/^#[0-9a-fA-F]{6}$/.test(val)) {
        this.patternColorTarget.value = val
        this.updatePreview()
      }
    }
  }

  syncPatternBgColor() {
    if (this.hasPatternBgColorTextTarget && this.hasPatternBgColorTarget) {
      const val = this.patternBgColorTextTarget.value
      if (/^#[0-9a-fA-F]{6}$/.test(val)) {
        this.patternBgColorTarget.value = val
        this.updatePreview()
      }
    }
  }

  // --- Template & Brand application ---

  _updateCustomSelectLabel(inputTarget, newValue) {
    const details = inputTarget.closest("details[data-controller='custom-select']")
    if (!details) return

    const label = details.querySelector("[data-custom-select-target='label']")
    const items = details.querySelectorAll("a[data-value]")

    items.forEach(item => {
      if (item.dataset.value === String(newValue)) {
        item.classList.add("active")
        if (label) {
          label.textContent = item.dataset.label || item.textContent
          // Copy font-family style if present
          if (item.style.fontFamily) label.style.fontFamily = item.style.fontFamily
        }
      } else {
        item.classList.remove("active")
      }
    })
  }

  _applySettingsToUI(settings) {
    const normalizedSettings = this._normalizeCaptionLayoutSettings({ ...(settings || {}) })

    const mapping = {
      caption_text: "captionText",
      subtitle_text: "subtitleText",
      background_type: "backgroundType",
      background_color: "backgroundColor",
      gradient_start: "gradientStart",
      gradient_end: "gradientEnd",
      gradient_direction: "gradientDirection",
      screenshot_padding: "screenshotPadding",
      screenshot_offset_y: "screenshotOffsetY",
      caption_font_size: "captionFontSize",
      caption_color: "captionColor",
      caption_position: "captionPosition",
      caption_font_family: "captionFontFamily",
      caption_font_weight: "captionFontWeight",
      caption_text_align: "captionTextAlign",
      caption_mode: "captionMode",
      caption_zone_size: "captionZoneSize",
      caption_letter_spacing: "captionLetterSpacing",
      caption_line_height: "captionLineHeight",
      caption_vertical_position: "captionVerticalPosition",
      subtitle_font_size: "subtitleFontSize",
      subtitle_color: "subtitleColor",
      subtitle_font_family: "subtitleFontFamily",
      subtitle_font_weight: "subtitleFontWeight",
      subtitle_letter_spacing: "subtitleLetterSpacing",
      subtitle_line_height: "subtitleLineHeight",
      text_bg_enabled: "textBgEnabled",
      text_bg_color: "textBgColor",
      text_bg_opacity: "textBgOpacity",
      text_bg_radius: "textBgRadius",
      caption_stroke_enabled: "captionStrokeEnabled",
      caption_stroke_color: "captionStrokeColor",
      caption_stroke_width: "captionStrokeWidth",
      caption_gradient_enabled: "captionGradientEnabled",
      caption_gradient_start: "captionGradientStart",
      caption_gradient_end: "captionGradientEnd",
      device_frame: "deviceFrame",
      mesh_preset: "meshPreset",
      mesh_color_1: "meshColor1",
      mesh_color_2: "meshColor2",
      mesh_color_3: "meshColor3",
      pattern_id: "patternId",
      pattern_color: "patternColor",
      pattern_bg_color: "patternBgColor",
      pattern_scale: "patternScale",
      background_image_fit: "backgroundImageFit",
      background_image_blur: "backgroundImageBlur",
      background_image_brightness: "backgroundImageBrightness",
      perspective_rotate_x: "perspectiveRotateX",
      perspective_rotate_y: "perspectiveRotateY",
      perspective_distance: "perspectiveDist",
      perspective_shadow: "perspectiveShadow",
      perspective_reflection: "perspectiveReflection"
    }

    const checkboxKeys = new Set([
      "textBgEnabled", "captionStrokeEnabled", "captionGradientEnabled",
      "perspectiveShadow", "perspectiveReflection"
    ])

    const colorTextPairs = {
      captionColor: "captionColorText",
      subtitleColor: "subtitleColorText",
      backgroundColor: "backgroundColorText",
      patternColor: "patternColorText",
      patternBgColor: "patternBgColorText"
    }

    for (const [settingKey, targetName] of Object.entries(mapping)) {
      if (normalizedSettings[settingKey] === undefined) continue

      const cap = targetName.charAt(0).toUpperCase() + targetName.slice(1)
      if (!this[`has${cap}Target`]) continue

      const target = this[`${targetName}Target`]
      const value = normalizedSettings[settingKey]

      if (checkboxKeys.has(targetName)) {
        target.checked = !!value
      } else if (target.type === "hidden") {
        target.value = value
        this._updateCustomSelectLabel(target, value)
        target.dispatchEvent(new Event("change", { bubbles: true }))
      } else {
        target.value = value
      }

      // Sync color text inputs
      if (colorTextPairs[targetName]) {
        const textTargetName = colorTextPairs[targetName]
        const textCap = textTargetName.charAt(0).toUpperCase() + textTargetName.slice(1)
        if (this[`has${textCap}Target`]) {
          this[`${textTargetName}Target`].value = value
        }
      }
    }

    // Update alignment buttons
    const align = normalizedSettings.caption_text_align
    if (align) {
      if (this.hasAlignLeftTarget) this.alignLeftTarget.classList.toggle("btn-active", align === "left")
      if (this.hasAlignCenterTarget) this.alignCenterTarget.classList.toggle("btn-active", align === "center")
      if (this.hasAlignRightTarget) this.alignRightTarget.classList.toggle("btn-active", align === "right")
    }

    // Sync perspective preset + labels
    if (normalizedSettings.perspective_preset !== undefined) {
      if (this.hasPerspectivePresetTarget) this.perspectivePresetTarget.value = normalizedSettings.perspective_preset
      this._syncPerspectivePresetButtons(normalizedSettings.perspective_preset)
      if (this.hasPerspectiveControlsTarget) {
        this.perspectiveControlsTarget.classList.toggle("hidden", normalizedSettings.perspective_preset === "none")
      }
    }
    if (normalizedSettings.perspective_rotate_x !== undefined && this.hasPerspectiveRotateXLabelTarget) {
      this.perspectiveRotateXLabelTarget.textContent = `${normalizedSettings.perspective_rotate_x}\u00B0`
    }
    if (normalizedSettings.perspective_rotate_y !== undefined && this.hasPerspectiveRotateYLabelTarget) {
      this.perspectiveRotateYLabelTarget.textContent = `${normalizedSettings.perspective_rotate_y}\u00B0`
    }
    if (normalizedSettings.perspective_distance !== undefined && this.hasPerspectiveDistLabelTarget) {
      this.perspectiveDistLabelTarget.textContent = normalizedSettings.perspective_distance
    }

    // Sync panoramic blur/brightness targets from the shared setting keys
    const bgType = normalizedSettings.background_type
    if (bgType === "panoramic") {
      if (normalizedSettings.background_image_blur !== undefined && this.hasPanoramicBlurTarget) {
        this.panoramicBlurTarget.value = normalizedSettings.background_image_blur
      }
      if (normalizedSettings.background_image_brightness !== undefined && this.hasPanoramicBrightnessTarget) {
        this.panoramicBrightnessTarget.value = normalizedSettings.background_image_brightness
      }
      // Update panoramic labels to reflect the new values (they are not
      // covered by the generic label sync which runs before these targets
      // are updated).
      if (this.hasPanoramicBlurTarget && this.hasPanoramicBlurLabelTarget) {
        this.panoramicBlurLabelTarget.textContent = `${this.panoramicBlurTarget.value}px`
      }
      if (this.hasPanoramicBrightnessTarget && this.hasPanoramicBrightnessLabelTarget) {
        this.panoramicBrightnessLabelTarget.textContent = `${this.panoramicBrightnessTarget.value}%`
      }
    }

    // Sync toggles
    this._syncEffectToggles()
    this._syncModeVisibility()

    // Sync background type visibility
    if (normalizedSettings.background_type !== undefined) {
      const bgType = normalizedSettings.background_type
      if (this.hasPaddingControlsTarget) this.paddingControlsTarget.classList.toggle("hidden", bgType === "none")
      if (this.hasSolidControlsTarget) this.solidControlsTarget.classList.toggle("hidden", bgType !== "solid")
      if (this.hasGradientControlsTarget) this.gradientControlsTarget.classList.toggle("hidden", bgType !== "gradient")
      if (this.hasMeshControlsTarget) this.meshControlsTarget.classList.toggle("hidden", bgType !== "mesh")
      if (this.hasPatternControlsTarget) this.patternControlsTarget.classList.toggle("hidden", bgType !== "pattern")
      if (this.hasImageControlsTarget) this.imageControlsTarget.classList.toggle("hidden", bgType !== "image")
      if (this.hasPanoramicControlsTarget) this.panoramicControlsTarget.classList.toggle("hidden", bgType !== "panoramic")
      if (this.hasPanoramicHintTarget) this.panoramicHintTarget.classList.toggle("hidden", bgType !== "panoramic")

      // Sync visual bg-type-btn active states
      this.element.querySelectorAll(".bg-type-btn").forEach(btn => {
        btn.classList.toggle("active", btn.dataset.bgType === bgType)
      })
    }
  }

  static SCENE_STYLE_OVERRIDE_KEYS = ["caption_color", "caption_font_size", "subtitle_color", "subtitle_font_size"]
  static SCENE_SETTING_OVERRIDE_KEYS = [
    "background_type", "background_color", "gradient_start", "gradient_end", "gradient_direction",
    "screenshot_padding", "screenshot_offset_y", "caption_font_size", "caption_color", "caption_position",
    "device_frame", "caption_font_family", "caption_font_weight", "caption_text_align", "caption_mode",
    "caption_zone_size", "caption_letter_spacing", "caption_line_height", "caption_vertical_position",
    "subtitle_font_size", "subtitle_color", "subtitle_font_family", "subtitle_font_weight",
    "subtitle_letter_spacing", "subtitle_line_height", "text_bg_enabled", "text_bg_color",
    "text_bg_opacity", "text_bg_radius", "text_bg_padding_x", "text_bg_padding_y",
    "caption_stroke_enabled", "caption_stroke_color", "caption_stroke_width",
    "caption_gradient_enabled", "caption_gradient_start", "caption_gradient_end",
    "mesh_preset", "mesh_color_1", "mesh_color_2", "mesh_color_3",
    "pattern_id", "pattern_color", "pattern_bg_color", "pattern_scale",
    "background_image_fit", "background_image_blur", "background_image_brightness",
    "perspective_preset", "perspective_rotate_x", "perspective_rotate_y", "perspective_distance",
    "perspective_shadow", "perspective_reflection", "layout_mode"
  ]
  static MAX_SCENE_IMAGE_CACHE = 60

  // Full set of defaults so switching templates always starts from a clean slate
  static TEMPLATE_DEFAULTS = {
    caption_text: "",
    caption_font_family: "Inter", caption_font_weight: 700, caption_font_size: 32,
    caption_color: "#FFFFFF", caption_text_align: "center", caption_mode: "zone",
    caption_position: "top", caption_zone_size: 12, caption_letter_spacing: 0,
    caption_line_height: 1.3, caption_vertical_position: "",
    subtitle_text: "", subtitle_font_family: "Inter", subtitle_font_weight: 400,
    subtitle_font_size: 20, subtitle_color: "#CCCCCC", subtitle_letter_spacing: 0,
    subtitle_line_height: 1.3,
    text_bg_enabled: false, text_bg_color: "#000000", text_bg_opacity: 50, text_bg_radius: 12,
    caption_stroke_enabled: false, caption_stroke_color: "#000000", caption_stroke_width: 2,
    caption_gradient_enabled: false, caption_gradient_start: "#FF6B6B", caption_gradient_end: "#4ECDC4",
    background_type: "solid", background_color: "#000000",
    gradient_start: "#000000", gradient_end: "#764BA2", gradient_direction: "to-bottom",
    mesh_preset: "sunset", pattern_id: "dots", pattern_color: "#FFFFFF",
    pattern_bg_color: "#000000", pattern_scale: 100,
    device_frame: "none", screenshot_padding: 8, screenshot_offset_y: 0,
    perspective_preset: "none", perspective_rotate_x: 0, perspective_rotate_y: 0,
    perspective_distance: 2000, perspective_shadow: false, perspective_reflection: false
  }

  async applyTemplate(event) {
    const button = event.currentTarget
    let templateSettings
    try {
      templateSettings = JSON.parse(button.dataset.templateSettings)
    } catch { return }

    const activeSceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null
    if (!activeSceneData) return

    // Merge defaults with template settings so every field is explicitly set.
    // For dropdown templates, these are applied as scene-level overrides only.
    const settings = { ...this.constructor.TEMPLATE_DEFAULTS, ...templateSettings }

    // Auto-swap device frame if it doesn't match the project platform
    if (settings.device_frame && settings.device_frame !== "none" && this.platformValue && this.platformValue !== "both") {
      const frameInfo = this.framesValue[settings.device_frame]
      if (frameInfo && frameInfo.platform !== "both" && frameInfo.platform !== this.platformValue) {
        settings.device_frame = this._swapFrameForPlatform(settings.device_frame, this.platformValue)
      }
    }

    const newOverrides = this._parseJSON(activeSceneData.dataset.sceneOverrides || "{}", {})

    // Reset previous scene-level visual overrides so this template fully defines this scene.
    this.constructor.SCENE_SETTING_OVERRIDE_KEYS.forEach((key) => delete newOverrides[key])
    delete newOverrides.text_position_x
    delete newOverrides.text_position_y
    delete newOverrides.text_rotation
    delete newOverrides.stickers

    // Apply full template settings as scene overrides (excluding scene text).
    this.constructor.SCENE_SETTING_OVERRIDE_KEYS.forEach((key) => {
      if (settings[key] !== undefined) newOverrides[key] = settings[key]
    })

    // Optional template drag position remains scene-level.
    if (templateSettings.text_position_x != null) newOverrides.text_position_x = templateSettings.text_position_x
    if (templateSettings.text_position_y != null) newOverrides.text_position_y = templateSettings.text_position_y

    activeSceneData.dataset.sceneOverrides = JSON.stringify(newOverrides)
    this._liveDragPosition = null
    this._liveRotation = null

    // Sync positioning mode based on whether template has a drag position.
    const hasTplDragPos = templateSettings.text_position_x != null && templateSettings.text_position_y != null
    this._syncPositioningModeUI(hasTplDragPos ? "freeform" : "auto")

    // Apply template default text to the active scene.
    // This intentionally overwrites the current scene's title/subtitle text.
    if (this.hasCaptionTextTarget) this.captionTextTarget.value = settings.caption_text || ""
    if (this.hasSubtitleTextTarget) this.subtitleTextTarget.value = settings.subtitle_text || ""
    this._saveCurrentLocaleTextToDOM()
    this._updateThumbnailLabelsForLocale()

    // Apply stickers from template (or clear)
    if (Array.isArray(templateSettings.default_stickers)) {
      this._stickers = templateSettings.default_stickers.map(s => ({
        ...s,
        id: `s_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
      }))
    } else {
      this._stickers = []
    }
    this._selectedStickerId = null
    this._stickerBounds = []
    this._saveStickersToOverrides()
    this._syncStickerControlsVisibility()

    this._loadSceneOverrides(activeSceneData)
    this._updateSceneDirtyState(activeSceneData.dataset.sceneId)
    this._updateDirtyCountBadge()

    // Close dropdown and render immediately for responsive switching.
    const dropdown = button.closest("details")
    if (dropdown) dropdown.removeAttribute("open")
    this.updatePreview()
    this._pushHistoryImmediate()

    // Warm resources in parallel and refresh when ready.
    const backgroundTasks = []

    if (this._stickers.some(s => (s.type || "emoji") === "asset")) {
      backgroundTasks.push(
        preloadStickerImages(this._stickers, this.stickerLibraryValue).then(() => {
          this._invalidateStaticLayer()
          this._scheduleRender()
        })
      )
    }

    const frameKey = settings.device_frame || "none"
    if (frameKey !== "none") {
      backgroundTasks.push(
        this.ensureFrameLoaded(frameKey).then(() => {
          this._invalidateStaticLayer()
          this._scheduleRender()
        })
      )
    }

    const fontTasks = []
    if (settings.caption_font_family) {
      fontTasks.push(loadFontForCanvas(settings.caption_font_family, settings.caption_font_weight || 700))
    }
    if (settings.subtitle_font_family) {
      fontTasks.push(loadFontForCanvas(settings.subtitle_font_family, settings.subtitle_font_weight || 400))
    }
    if (fontTasks.length > 0) {
      backgroundTasks.push(
        Promise.allSettled(fontTasks).then(() => {
          this._invalidateStaticLayer()
          this._scheduleRender()
        })
      )
    }

    // Keep method async for call-site compatibility, but don't block UX.
    await Promise.allSettled(backgroundTasks)
  }

  async applyBrand() {
    const brand = this.brandValue || {}
    if (!brand || Object.keys(brand).length === 0) return

    const settings = {}
    if (brand.primary_color) settings.caption_color = brand.primary_color
    if (brand.secondary_color) settings.subtitle_color = brand.secondary_color
    if (brand.background_color) {
      settings.background_color = brand.background_color
      settings.background_type = "solid"
    }
    if (brand.heading_font) settings.caption_font_family = brand.heading_font
    if (brand.body_font) settings.subtitle_font_family = brand.body_font
    if (brand.text_color) settings.caption_color = brand.text_color

    this._applySettingsToUI(settings)

    // Load fonts
    const families = new Set()
    if (settings.caption_font_family) families.add(settings.caption_font_family)
    if (settings.subtitle_font_family) families.add(settings.subtitle_font_family)
    for (const family of families) {
      await loadFontForCanvas(family)
    }

    this.updatePreview()
    this._pushHistoryImmediate()
  }

  applyBrandColor(event) {
    const color = event.currentTarget.dataset.color
    const targetInput = event.currentTarget.dataset.targetInput

    if (!color || !targetInput) return

    const cap = targetInput.charAt(0).toUpperCase() + targetInput.slice(1)
    if (!this[`has${cap}Target`]) return

    this[`${targetInput}Target`].value = color

    // Sync text input if it exists
    const textTargetName = targetInput + "Text"
    const textCap = textTargetName.charAt(0).toUpperCase() + textTargetName.slice(1)
    if (this[`has${textCap}Target`]) {
      this[`${textTargetName}Target`].value = color
    }

    this.updatePreview()
  }

  // Save current scene only (default action)
  async saveCurrentScene() {
    this._closeSaveDropdown()
    await this._performSave({ allScenes: false })
  }

  // Save all dirty scenes
  async saveAllScenes() {
    this._closeSaveDropdown()
    await this._performSave({ allScenes: true })
  }

  // Legacy alias — keep for backwards compat
  async save() {
    await this._performSave({ allScenes: true })
  }

  async _performSave({ allScenes = true } = {}) {
    const csrfToken = document.querySelector("meta[name=csrf-token]")?.content

    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.disabled = true
    }
    if (this.hasSaveLabelTarget) {
      this.saveLabelTarget.textContent = "Saving..."
    }

    let allOk = true

    // Persist current scene draft into DOM before collecting dirty scenes
    this._syncCurrentSceneDraftToDOM()
    this._updateAllSceneDirtyStates()

    // 1. Save scenes (caption + subtitle + overrides + locale_variants)
    let sceneIdsToSave
    if (allScenes) {
      sceneIdsToSave = this._dirtySceneIds ? Array.from(this._dirtySceneIds) : []
    } else {
      // Only save the current scene if it's dirty
      const currentId = String(this.currentSceneId)
      sceneIdsToSave = this._dirtySceneIds?.has(currentId) ? [currentId] : []
    }

    for (const sceneId of sceneIdsToSave) {
      const sceneData = this.findSceneData(sceneId)
      if (!sceneData) continue

      const sceneBody = this._buildSceneBodyFromData(sceneData)
      try {
        const resp = await fetch(sceneData.dataset.sceneUpdateUrl, {
          method: "PATCH",
          headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken, "Accept": "application/json" },
          body: JSON.stringify({ screenshot_scene: sceneBody })
        })
        if (resp.ok) {
          this._markSceneAsPersisted(sceneId)
        } else {
          allOk = false
        }
      } catch {
        allOk = false
      }
    }
    this._updateThumbnailLabelsForLocale()

    // 2. Save project settings
    if (this.projectUrlValue) {
      // When dark mode preview is active, the UI reflects the dark variant.
      // We must save the original (light) settings so the canonical project
      // settings are not overwritten with the transient dark transform.
      const settings = this._darkModePreToggleSettings
        ? { ...this._darkModePreToggleSettings }
        : this.getCurrentSettings()
      const sceneSettingsKeys = new Set(this.constructor.SCENE_SETTING_OVERRIDE_KEYS)

      // Do not leak current-scene override values into project-level settings.
      const activeSceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null
      if (activeSceneData) {
        let activeSceneOverrides = {}
        try { activeSceneOverrides = JSON.parse(activeSceneData.dataset.sceneOverrides || "{}") } catch {}
        Object.keys(activeSceneOverrides).forEach((key) => {
          if (!sceneSettingsKeys.has(key)) return
          if (!Object.prototype.hasOwnProperty.call(settings, key)) return
          if (this.settingsValue && this.settingsValue[key] !== undefined) {
            settings[key] = this.settingsValue[key]
          }
        })
      }

      // Determine if the current template still applies
      let templateToSave = this.templateValue || ""
      if (templateToSave) {
        const templateBtn = this.element.querySelector(`[data-template-key="${templateToSave}"]`)
        if (templateBtn) {
          try {
            const templateSettings = JSON.parse(templateBtn.dataset.templateSettings)
            const comparableSettingsKeys = new Set(Object.keys(settings))
            for (const key of Object.keys(templateSettings)) {
              // Template fields like default_stickers/text_position are scene-level,
              // so they are intentionally excluded from project-settings comparison.
              if (!comparableSettingsKeys.has(key)) continue
              if (String(settings[key] ?? "") !== String(templateSettings[key] ?? "")) {
                templateToSave = ""
                break
              }
            }
          } catch { templateToSave = "" }
        }
      }

      this.templateValue = templateToSave

      try {
        const resp = await fetch(this.projectUrlValue, {
          method: "PATCH",
          headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken, "Accept": "application/json" },
          body: JSON.stringify({ screenshot_project: { settings, template: templateToSave } })
        })
        if (!resp.ok) {
          allOk = false
        } else {
          this.settingsValue = { ...settings }
        }
      } catch { allOk = false }
    }

    // 3. Show result
    if (allOk) {
      if (this.hasSaveIconTarget) this.saveIconTarget.className = "fa-solid fa-check"
      if (this.hasSaveLabelTarget) this.saveLabelTarget.textContent = "Saved"
    } else {
      if (this.hasSaveLabelTarget) this.saveLabelTarget.textContent = "Failed to save"
    }

    setTimeout(() => {
      if (this.hasSaveIconTarget) this.saveIconTarget.className = "fa-solid fa-floppy-disk"
      if (this.hasSaveLabelTarget) this.saveLabelTarget.textContent = "Save"
    }, 1500)

    this._updateAllSceneDirtyStates()
    this._updateDirtyCountBadge()
    if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = false
  }

  _closeSaveDropdown() {
    if (this.hasSaveDropdownTarget) {
      this.saveDropdownTarget.removeAttribute("open")
    }
  }

  _updateDirtyCountBadge() {
    if (!this.hasDirtyCountBadgeTarget) return
    const count = this._dirtySceneIds ? this._dirtySceneIds.size : 0
    this.dirtyCountBadgeTarget.textContent = count
    this.dirtyCountBadgeTarget.classList.toggle("hidden", count === 0)
  }

  confirmDeleteScene(event) {
    event.preventDefault()
    event.stopPropagation()

    const btn = event.currentTarget
    const deleteUrl = btn.dataset.deleteUrl
    const sceneName = btn.dataset.sceneName || "this scene"

    const modal = document.getElementById("delete_scene_modal")
    const form = document.getElementById("delete_scene_form")
    const nameSpan = document.getElementById("delete_scene_name")

    if (form) form.action = deleteUrl
    if (nameSpan) nameSpan.textContent = sceneName
    if (modal) modal.showModal()
  }

  // --- Public API (used by export controller) ---

  getCurrentSettings() {
    return {
      background_type: this.hasBackgroundTypeTarget ? this.backgroundTypeTarget.value : "solid",
      background_color: this.hasBackgroundColorTarget ? this.backgroundColorTarget.value : "#000000",
      gradient_start: this.hasGradientStartTarget ? this.gradientStartTarget.value : "#000000",
      gradient_end: this.hasGradientEndTarget ? this.gradientEndTarget.value : "#764BA2",
      gradient_direction: this.hasGradientDirectionTarget ? this.gradientDirectionTarget.value : "to-bottom",
      screenshot_padding: this.hasScreenshotPaddingTarget ? parseInt(this.screenshotPaddingTarget.value) : 8,
      screenshot_offset_y: this._targetIntVal("screenshotOffsetY", 0),
      caption_font_size: this._targetIntVal("captionFontSize", 32),
      caption_color: this._targetVal("captionColor", "#FFFFFF"),
      caption_position: "top",
      device_frame: this.hasDeviceFrameTarget ? this.deviceFrameTarget.value : "none",
      caption_font_family: this._targetVal("captionFontFamily", "Inter"),
      caption_font_weight: this._targetIntVal("captionFontWeight", 700),
      caption_text_align: this._targetVal("captionTextAlign", "center"),
      caption_mode: "zone",
      caption_zone_size: this._targetIntVal("captionZoneSize", 12),
      caption_letter_spacing: this._targetFloatVal("captionLetterSpacing", 0),
      caption_line_height: this._targetFloatVal("captionLineHeight", 1.3),
      caption_vertical_position: this._targetVal("captionVerticalPosition", ""),
      subtitle_font_size: this._targetIntVal("subtitleFontSize", 20),
      subtitle_color: this._targetVal("subtitleColor", "#CCCCCC"),
      subtitle_font_family: this._targetVal("subtitleFontFamily", "Inter"),
      subtitle_font_weight: this._targetIntVal("subtitleFontWeight", 400),
      subtitle_letter_spacing: this._targetFloatVal("subtitleLetterSpacing", 0),
      subtitle_line_height: this._targetFloatVal("subtitleLineHeight", 1.3),
      text_bg_enabled: this._targetChecked("textBgEnabled"),
      text_bg_color: this._targetVal("textBgColor", "#000000"),
      text_bg_opacity: this._targetIntVal("textBgOpacity", 50),
      text_bg_radius: this._targetIntVal("textBgRadius", 12),
      text_bg_padding_x: parseInt(this.settingsValue?.text_bg_padding_x) || 24,
      text_bg_padding_y: parseInt(this.settingsValue?.text_bg_padding_y) || 12,
      caption_stroke_enabled: this._targetChecked("captionStrokeEnabled"),
      caption_stroke_color: this._targetVal("captionStrokeColor", "#000000"),
      caption_stroke_width: this._targetIntVal("captionStrokeWidth", 2),
      caption_gradient_enabled: this._targetChecked("captionGradientEnabled"),
      caption_gradient_start: this._targetVal("captionGradientStart", "#FF6B6B"),
      caption_gradient_end: this._targetVal("captionGradientEnd", "#4ECDC4"),
      mesh_preset: this._targetVal("meshPreset", "sunset"),
      mesh_color_1: this._targetVal("meshColor1", ""),
      mesh_color_2: this._targetVal("meshColor2", ""),
      mesh_color_3: this._targetVal("meshColor3", ""),
      pattern_id: this._targetVal("patternId", "dots"),
      pattern_color: this._targetVal("patternColor", "#FFFFFF"),
      pattern_bg_color: this._targetVal("patternBgColor", "#000000"),
      pattern_scale: this._targetIntVal("patternScale", 100),
      background_image_fit: this._targetVal("backgroundImageFit", "cover"),
      background_image_blur: (this.hasBackgroundTypeTarget && this.backgroundTypeTarget.value === "panoramic")
        ? this._targetIntVal("panoramicBlur", 0)
        : this._targetIntVal("backgroundImageBlur", 0),
      background_image_brightness: (this.hasBackgroundTypeTarget && this.backgroundTypeTarget.value === "panoramic")
        ? this._targetIntVal("panoramicBrightness", 100)
        : this._targetIntVal("backgroundImageBrightness", 100),
      perspective_preset: this._targetVal("perspectivePreset", "none"),
      perspective_rotate_x: this._targetFloatVal("perspectiveRotateX", 0),
      perspective_rotate_y: this._targetFloatVal("perspectiveRotateY", 0),
      perspective_distance: this._targetIntVal("perspectiveDist", 2000),
      perspective_shadow: this._targetChecked("perspectiveShadow"),
      perspective_reflection: this._targetChecked("perspectiveReflection"),
      layout_mode: this._targetVal("layoutMode", "auto")
    }
  }

  getImageCache() {
    return this.imageCache
  }

  getSceneDataTargets() {
    return this.sceneDataTargets
  }

  // --- Undo / Redo ---

  _captureState() {
    const sceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null
    return {
      settings: this.getCurrentSettings(),
      sceneId: this.currentSceneId,
      captionText: this.hasCaptionTextTarget ? this.captionTextTarget.value : "",
      subtitleText: this.hasSubtitleTextTarget ? this.subtitleTextTarget.value : "",
      overrides: sceneData ? sceneData.dataset.sceneOverrides : "{}"
    }
  }

  _restoreState(snapshot) {
    if (!snapshot) return

    this._applySettingsToUI(snapshot.settings)

    if (this.hasCaptionTextTarget) this.captionTextTarget.value = snapshot.captionText || ""
    if (this.hasSubtitleTextTarget) this.subtitleTextTarget.value = snapshot.subtitleText || ""

    if (snapshot.sceneId && snapshot.sceneId !== this.currentSceneId) {
      this.selectSceneById(snapshot.sceneId)
    }

    const sceneData = snapshot.sceneId ? this.findSceneData(snapshot.sceneId) : null
    if (sceneData && snapshot.overrides) {
      sceneData.dataset.sceneOverrides = snapshot.overrides
      this._loadSceneOverrides(sceneData)
    }

    // Sticker controls visibility after restore
    this._syncStickerControlsVisibility()

    this.updatePreview()
  }

  _pushHistoryImmediate() {
    this._history.push(this._captureState())
    this._updateUndoRedoButtons()
  }

  _pushHistoryDebounced() {
    clearTimeout(this._historyDebounceTimer)
    this._historyDebounceTimer = setTimeout(() => {
      this._pushHistoryImmediate()
    }, 500)
  }

  undo() {
    const state = this._history.undo()
    if (state) {
      this._restoreState(state)
      this._updateUndoRedoButtons()
    }
  }

  redo() {
    const state = this._history.redo()
    if (state) {
      this._restoreState(state)
      this._updateUndoRedoButtons()
    }
  }

  _updateUndoRedoButtons() {
    if (this.hasUndoButtonTarget) {
      this.undoButtonTarget.disabled = !this._history.canUndo
    }
    if (this.hasRedoButtonTarget) {
      this.redoButtonTarget.disabled = !this._history.canRedo
    }
  }

  // --- Keyboard shortcuts ---

  _handleKeyDown(event) {
    const tag = event.target.tagName
    const isEditable = event.target.isContentEditable
    const isTextInput = tag === "INPUT" || tag === "TEXTAREA" || isEditable
    const mod = event.metaKey || event.ctrlKey

    // Ctrl/Cmd+Shift+S — save all scenes (always)
    if (mod && event.shiftKey && event.key.toLowerCase() === "s") {
      event.preventDefault()
      this.saveAllScenes()
      return
    }

    // Ctrl/Cmd+S — save current scene (always)
    if (mod && event.key === "s") {
      event.preventDefault()
      this.saveCurrentScene()
      return
    }

    // Ctrl/Cmd+Shift+Z — redo (always)
    if (mod && event.shiftKey && event.key.toLowerCase() === "z") {
      event.preventDefault()
      this.redo()
      return
    }

    // Ctrl/Cmd+Z — undo (always)
    if (mod && event.key.toLowerCase() === "z") {
      event.preventDefault()
      this.undo()
      return
    }

    // Ctrl/Cmd+E — export modal (always)
    if (mod && event.key.toLowerCase() === "e") {
      event.preventDefault()
      const modal = document.getElementById("export_modal")
      if (modal) modal.showModal()
      return
    }

    // Skip remaining shortcuts when in text fields
    if (isTextInput) return

    // Delete/Backspace — delete selected sticker
    if ((event.key === "Delete" || event.key === "Backspace") && this._selectedStickerId) {
      event.preventDefault()
      this.deleteSelectedSticker()
      return
    }

    // Escape — deselect sticker
    if (event.key === "Escape" && this._selectedStickerId) {
      event.preventDefault()
      this._selectedStickerId = null
      this._syncStickerControlsVisibility()
      this.updatePreview()
      return
    }

    // Arrow keys for scene navigation
    if (event.key === "ArrowLeft") {
      event.preventDefault()
      this._navigateScene(-1)
      return
    }
    if (event.key === "ArrowRight") {
      event.preventDefault()
      this._navigateScene(1)
      return
    }

    // ? — toggle shortcuts help
    if (event.key === "?") {
      event.preventDefault()
      this._toggleShortcutsHelp()
      return
    }
  }

  _navigateScene(direction) {
    if (!this.hasSceneDataTarget) return
    const scenes = this.sceneDataTargets
    const currentIdx = scenes.findIndex(el => String(el.dataset.sceneId) === String(this.currentSceneId))
    const nextIdx = currentIdx + direction
    if (nextIdx >= 0 && nextIdx < scenes.length) {
      this.selectSceneById(scenes[nextIdx].dataset.sceneId)
    }
  }

  _toggleShortcutsHelp() {
    const dialog = document.getElementById("shortcuts_help_modal")
    if (!dialog) return
    if (dialog.open) {
      dialog.close()
    } else {
      dialog.showModal()
    }
  }

  // --- Locale switching ---

  switchLocale(event) {
    const locale = event.currentTarget.dataset.locale
    if (!locale || locale === this.currentLocaleValue) return

    // Persist current scene draft before switching locale
    this._syncCurrentSceneDraftToDOM()

    this.currentLocaleValue = locale

    // Update tab bar active state
    if (this.hasLocaleBarTarget) {
      this.localeBarTarget.querySelectorAll("button").forEach(btn => {
        if (btn.dataset.locale === locale) {
          btn.classList.add("btn-primary")
          btn.classList.remove("btn-ghost")
        } else {
          btn.classList.remove("btn-primary")
          btn.classList.add("btn-ghost")
        }
      })
    }

    // Load locale-specific text for current scene
    this._loadLocaleText()

    // Update all scene thumbnail labels for the new locale
    this._updateThumbnailLabelsForLocale()

    this.updatePreview()
  }

  _saveCurrentLocaleTextToDOM() {
    if (!this.currentSceneId) return

    const sceneData = this.findSceneData(this.currentSceneId)
    if (!sceneData) return

    const caption = this.hasCaptionTextTarget ? this.captionTextTarget.value : ""
    const subtitle = this.hasSubtitleTextTarget ? this.subtitleTextTarget.value : ""

    // Always sync current text to the main data attributes
    if (!this.localesValue || this.localesValue.length === 0 || this.localesValue[0] === this.currentLocaleValue) {
      sceneData.dataset.sceneCaption = caption
      sceneData.dataset.sceneSubtitle = subtitle
    } else {
      // Non-default locale text lives in locale_variants
      const locale = this.currentLocaleValue
      let variants = {}
      try { variants = JSON.parse(sceneData.dataset.sceneLocaleVariants || "{}") } catch {}
      variants[locale] = variants[locale] || {}
      variants[locale].caption_text = caption
      variants[locale].subtitle_text = subtitle
      sceneData.dataset.sceneLocaleVariants = JSON.stringify(variants)
    }
    this._updateSceneDirtyState(sceneData.dataset.sceneId)
  }

  _loadLocaleText() {
    if (!this.currentSceneId) return

    const sceneData = this.findSceneData(this.currentSceneId)
    if (!sceneData) return

    const locale = this.currentLocaleValue
    const isDefault = !this.localesValue || this.localesValue.length === 0 || this.localesValue[0] === locale

    if (isDefault) {
      if (this.hasCaptionTextTarget) this.captionTextTarget.value = sceneData.dataset.sceneCaption || ""
      if (this.hasSubtitleTextTarget) this.subtitleTextTarget.value = sceneData.dataset.sceneSubtitle || ""
    } else {
      let variants = {}
      try { variants = JSON.parse(sceneData.dataset.sceneLocaleVariants || "{}") } catch {}
      const localeData = variants[locale] || {}
      if (this.hasCaptionTextTarget) this.captionTextTarget.value = localeData.caption_text || sceneData.dataset.sceneCaption || ""
      if (this.hasSubtitleTextTarget) this.subtitleTextTarget.value = localeData.subtitle_text || sceneData.dataset.sceneSubtitle || ""
    }
  }

  _updateThumbnailLabelsForLocale() {
    const locale = this.currentLocaleValue
    const isDefault = !this.localesValue || this.localesValue.length === 0 || this.localesValue[0] === locale

    this.sceneDataTargets.forEach(sceneData => {
      const sceneId = sceneData.dataset.sceneId
      let captionText

      if (isDefault) {
        captionText = sceneData.dataset.sceneCaption || ""
      } else {
        let variants = {}
        try { variants = JSON.parse(sceneData.dataset.sceneLocaleVariants || "{}") } catch {}
        captionText = variants[locale]?.caption_text || sceneData.dataset.sceneCaption || ""
      }

      this.thumbnailTargets.forEach(thumb => {
        const sid = thumb.dataset.screenshotEditorSceneIdParam
        if (String(sid) === String(sceneId)) {
          const label = thumb.querySelector("p")
          if (label) label.textContent = captionText || `Scene ${sceneData.dataset.scenePosition}`
        }
      })
    })
  }

  // --- Sticker methods ---

  static MAX_STICKERS_PER_SCENE = 20

  addSticker(event) {
    const emoji = event.currentTarget.dataset.emoji
    if (!emoji) return

    if (this._stickers.length >= this.constructor.MAX_STICKERS_PER_SCENE) return

    const id = `s_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
    const sticker = { id, type: "emoji", emoji, x: 50, y: 50, size: 64, rotation: 0 }
    this._stickers.push(sticker)
    this._selectedStickerId = id
    this._saveStickersToOverrides()
    this._syncStickerControlsVisibility()
    this.updatePreview()
    this._pushHistoryImmediate()
  }

  addTextSticker(event) {
    if (this._stickers.length >= this.constructor.MAX_STICKERS_PER_SCENE) return

    // Text can come from a preset button's data-text, or from the input field
    let text = event.currentTarget.dataset.text || ""
    if (!text && this.hasNewTextStickerInputTarget) {
      text = this.newTextStickerInputTarget.value.trim()
    }
    if (!text) text = "Text"

    const fontWeight = event.currentTarget.dataset.fontWeight || "700"
    const bgColor = event.currentTarget.dataset.bgColor || "rgba(0,0,0,0.7)"

    const id = `s_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
    const sticker = {
      id, type: "text", text, x: 50, y: 50, size: 64, rotation: 0,
      color: "#FFFFFF", fontWeight, bgColor, bgEnabled: true
    }
    this._stickers.push(sticker)
    this._selectedStickerId = id
    this._saveStickersToOverrides()
    this._syncStickerControlsVisibility()
    this.updatePreview()
    this._pushHistoryImmediate()

    // Clear the input after adding
    if (this.hasNewTextStickerInputTarget) {
      this.newTextStickerInputTarget.value = ""
    }
  }

  async addLibrarySticker(event) {
    const assetKey = event.currentTarget.dataset.assetKey
    const imageUrl = event.currentTarget.dataset.imageUrl
    if (!assetKey || !imageUrl) return

    if (this._stickers.length >= this.constructor.MAX_STICKERS_PER_SCENE) return

    // Smart default color: contrasting against current background
    const defaultColor = this._getContrastingColor()
    let loaded = null
    try {
      loaded = await loadStickerImage(assetKey, imageUrl, defaultColor)
    } catch (error) {
      console.warn(`[sticker] Failed to load sticker asset '${assetKey}' from ${imageUrl}:`, error)
    }
    if (!loaded) return

    // Smart default size by category
    const category = event.currentTarget.dataset.category || "icons"
    const sizeDefaults = { annotations: 80, icons: 64, badges: 96, ui_elements: 80 }
    const defaultSize = sizeDefaults[category] || 64

    const id = `s_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
    const sticker = { id, type: "asset", asset_key: assetKey, x: 50, y: 50, size: defaultSize, rotation: 0, color: defaultColor }
    this._stickers.push(sticker)
    this._selectedStickerId = id
    this._saveStickersToOverrides()
    this._syncStickerControlsVisibility()
    this.updatePreview()
    this._pushHistoryImmediate()
  }

  switchTab(event) {
    const tabName = event.currentTarget.dataset.tab
    if (!tabName) return

    this.editorTabBtnTargets.forEach(btn => btn.classList.remove("active"))
    this.editorTabContentTargets.forEach(panel => panel.classList.remove("active"))

    event.currentTarget.classList.add("active")
    const content = this.editorTabContentTargets.find(el => el.dataset.tab === tabName)
    if (content) content.classList.add("active")
  }

  switchStickerSection(event) {
    const section = event.currentTarget.dataset.section
    const sections = {
      emoji: { btn: "stickerSectionBtnEmoji", panel: "stickerEmojiSection" },
      library: { btn: "stickerSectionBtnLibrary", panel: "stickerLibrarySection" },
      images: { btn: "stickerSectionBtnImages", panel: "stickerImagesSection" },
      text: { btn: "stickerSectionBtnText", panel: "stickerTextSection" }
    }

    for (const [key, { btn, panel }] of Object.entries(sections)) {
      const btnTarget = this[`has${btn.charAt(0).toUpperCase() + btn.slice(1)}Target`] ? this[`${btn}Target`] : null
      const panelTarget = this[`has${panel.charAt(0).toUpperCase() + panel.slice(1)}Target`] ? this[`${panel}Target`] : null

      if (btnTarget) {
        btnTarget.classList.toggle("btn-active", key === section)
        btnTarget.classList.toggle("btn-ghost", key !== section)
      }
      if (panelTarget) {
        panelTarget.classList.toggle("hidden", key !== section)
      }
    }

    // Preload library on first switch to library tab
    if (section === "library") {
      this._preloadLibrary()
    }
  }

  filterLibraryStickers() {
    if (!this.hasStickerLibrarySearchTarget || !this.hasStickerLibrarySectionTarget) return
    const query = this.stickerLibrarySearchTarget.value.toLowerCase().trim()

    // Search all sticker buttons across all categories
    const buttons = this.stickerLibrarySectionTarget.querySelectorAll(".sticker-lib-item")
    const categoryHits = new Map()

    buttons.forEach(btn => {
      const tags = (btn.dataset.tags || "").toLowerCase()
      const label = (btn.getAttribute("title") || "").toLowerCase()
      const matches = !query || tags.includes(query) || label.includes(query)
      btn.classList.toggle("hidden", !matches)

      // Track which categories have visible items
      const category = btn.closest(".sticker-lib-category")
      if (category) {
        if (!categoryHits.has(category)) categoryHits.set(category, false)
        if (matches) categoryHits.set(category, true)
      }
    })

    // Show/hide categories and auto-expand matching ones
    categoryHits.forEach((hasHits, category) => {
      category.classList.toggle("hidden", !hasHits && !!query)
      if (query && hasHits) {
        category.setAttribute("open", "")
      }
    })
  }

  async updateStickerColor() {
    if (!this._selectedStickerId || !this.hasStickerColorTarget) return
    const color = this.stickerColorTarget.value
    const sticker = this._stickers.find(s => s.id === this._selectedStickerId)
    if (!sticker) return

    const previousColor = sticker.color || "#FFFFFF"
    sticker.color = color
    if (this.hasStickerColorTextTarget) {
      this.stickerColorTextTarget.value = color
    }

    // Reload cached image with new color for asset stickers
    const sType = sticker.type || "emoji"
    if (sType === "asset" && sticker.asset_key) {
      const imageUrl = this._findAssetImageUrl(sticker.asset_key)
      if (imageUrl) {
        let loaded = null
        try {
          loaded = await loadStickerImage(sticker.asset_key, imageUrl, color)
        } catch {}
        if (!loaded) {
          sticker.color = previousColor
          if (this.hasStickerColorTarget) this.stickerColorTarget.value = previousColor
          if (this.hasStickerColorTextTarget) this.stickerColorTextTarget.value = previousColor
          this.updatePreview()
          return
        }
      }
    }

    this._saveStickersToOverrides()
    this.updatePreview()
    this._pushHistoryDebounced()
  }

  async updateStickerColorFromText() {
    if (!this._selectedStickerId || !this.hasStickerColorTextTarget) return
    const color = this.stickerColorTextTarget.value
    if (!/^#[0-9A-Fa-f]{6}$/.test(color)) return

    if (this.hasStickerColorTarget) {
      this.stickerColorTarget.value = color
    }
    await this.updateStickerColor()
  }

  updateStickerText() {
    if (!this._selectedStickerId || !this.hasStickerTextTarget) return
    const text = this.stickerTextTarget.value
    const sticker = this._stickers.find(s => s.id === this._selectedStickerId)
    if (!sticker) return

    sticker.text = text
    this._saveStickersToOverrides()
    this.updatePreview()
    this._pushHistoryDebounced()
  }

  updateStickerBgColor() {
    if (!this._selectedStickerId || !this.hasStickerBgColorTarget) return
    const sticker = this._stickers.find(s => s.id === this._selectedStickerId)
    if (!sticker || (sticker.type || "emoji") !== "text") return

    const hex = this.stickerBgColorTarget.value
    // Store as rgba with 0.85 opacity for a nice overlay look
    sticker.bgColor = this._hexToRgba(hex, 0.85)
    this._saveStickersToOverrides()
    this.updatePreview()
    this._pushHistoryDebounced()
  }

  updateStickerBgEnabled() {
    if (!this._selectedStickerId || !this.hasStickerBgEnabledTarget) return
    const sticker = this._stickers.find(s => s.id === this._selectedStickerId)
    if (!sticker || (sticker.type || "emoji") !== "text") return

    sticker.bgEnabled = this.stickerBgEnabledTarget.checked
    this._saveStickersToOverrides()
    this.updatePreview()
    this._pushHistoryDebounced()
  }

  _hexToRgba(hex, alpha) {
    const r = parseInt(hex.slice(1, 3), 16)
    const g = parseInt(hex.slice(3, 5), 16)
    const b = parseInt(hex.slice(5, 7), 16)
    return `rgba(${r},${g},${b},${alpha})`
  }

  _rgbaToHex(rgba) {
    const match = rgba.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/)
    if (!match) return "#000000"
    const r = parseInt(match[1]).toString(16).padStart(2, "0")
    const g = parseInt(match[2]).toString(16).padStart(2, "0")
    const b = parseInt(match[3]).toString(16).padStart(2, "0")
    return `#${r}${g}${b}`
  }

  deleteSelectedSticker() {
    if (!this._selectedStickerId) return
    this._stickers = this._stickers.filter(s => s.id !== this._selectedStickerId)
    this._selectedStickerId = null
    this._saveStickersToOverrides()
    this._syncStickerControlsVisibility()
    this.updatePreview()
    this._pushHistoryImmediate()
  }

  updateStickerSize() {
    if (!this._selectedStickerId || !this.hasStickerSizeTarget) return
    const size = parseInt(this.stickerSizeTarget.value) || 64
    const sticker = this._stickers.find(s => s.id === this._selectedStickerId)
    if (sticker) {
      sticker.size = size
      if (this.hasStickerSizeLabelTarget) {
        this.stickerSizeLabelTarget.textContent = `${size}px`
      }
      this._saveStickersToOverrides()
      this.updatePreview()
      this._pushHistoryDebounced()
    }
  }

  _loadStickersFromOverrides(overrides) {
    const original = Array.isArray(overrides.stickers) ? overrides.stickers : []
    const hydrated = original.map(s => this._hydrateCustomSticker(s))
    const nextStickers = hydrated
      .filter(s => {
        const type = s.type || "emoji"
        if (type === "custom_image") return !!s.image_url && !s.__missingCustomImage
        if (type === "asset") return !!this._findAssetImageUrl(s.asset_key)
        return true
      })
      .map(s => this._sanitizeStickerForPersistence(s))

    this._stickers = nextStickers
    this._selectedStickerId = null
    this._stickerBounds = []
    this._syncStickerControlsVisibility()

    // Persist cleanup when stale stickers were dropped from overrides.
    if (nextStickers.length !== original.length) {
      this._saveStickersToOverrides()
    }

    // Preload SVG images for asset stickers
    const needsPreload = this._stickers.some(s => {
      const t = s.type || "emoji"
      return t === "asset"
    })
    if (needsPreload) {
      preloadStickerImages(this._stickers, this.stickerLibraryValue).then(() => this.updatePreview())
    }

    // Preload custom images
    const needsCustomPreload = this._stickers.some(s => s.type === "custom_image")
    if (needsCustomPreload) {
      preloadCustomImages(this._stickers).then(() => this.updatePreview())
    }
  }

  _saveStickersToOverrides() {
    const sceneData = this.currentSceneId ? this.findSceneData(this.currentSceneId) : null
    if (!sceneData) return

    let overrides = {}
    try { overrides = JSON.parse(sceneData.dataset.sceneOverrides || "{}") } catch {}

    if (this._stickers.length > 0) {
      overrides.stickers = this._stickers.map(s => this._sanitizeStickerForPersistence(s))
    } else {
      delete overrides.stickers
    }
    sceneData.dataset.sceneOverrides = JSON.stringify(overrides)
    this._updateSceneDirtyState(sceneData.dataset.sceneId)
  }

  _sanitizeStickerForPersistence(sticker) {
    const clean = { ...sticker }
    delete clean.__missingCustomImage
    return clean
  }

  _syncStickerControlsVisibility() {
    if (this.hasStickerControlsTarget) {
      this.stickerControlsTarget.classList.toggle("hidden", !this._selectedStickerId)
    }

    const sticker = this._selectedStickerId
      ? this._stickers.find(s => s.id === this._selectedStickerId)
      : null
    const stickerType = sticker ? (sticker.type || "emoji") : "emoji"

    if (sticker && this.hasStickerSizeTarget) {
      this.stickerSizeTarget.value = sticker.size
      if (this.hasStickerSizeLabelTarget) {
        this.stickerSizeLabelTarget.textContent = `${sticker.size}px`
      }
    }

    // Color picker: visible for asset type and text type
    if (this.hasStickerColorControlsTarget) {
      const showColor = sticker && (stickerType === "asset" || stickerType === "text")
      this.stickerColorControlsTarget.classList.toggle("hidden", !showColor)
      if (showColor) {
        const color = sticker.color || "#FFFFFF"
        if (this.hasStickerColorTarget) this.stickerColorTarget.value = color
        if (this.hasStickerColorTextTarget) this.stickerColorTextTarget.value = color
      }
    }

    // Text input: visible for speech/thought/callout asset stickers AND text type stickers
    if (this.hasStickerTextControlsTarget) {
      const isAssetWithText = sticker && stickerType === "asset" &&
        (sticker.asset_key === "anno_speech_bubble" || sticker.asset_key === "anno_thought_bubble" || sticker.asset_key === "anno_callout_box")
      const isTextSticker = sticker && stickerType === "text"
      const showText = isAssetWithText || isTextSticker
      this.stickerTextControlsTarget.classList.toggle("hidden", !showText)
      if (showText && this.hasStickerTextTarget) {
        this.stickerTextTarget.value = sticker.text || ""
      }
    }

    // Background color controls: visible only for text type stickers
    if (this.hasStickerBgColorControlsTarget) {
      const showBg = sticker && stickerType === "text"
      this.stickerBgColorControlsTarget.classList.toggle("hidden", !showBg)
      if (showBg) {
        if (this.hasStickerBgColorTarget) {
          // Convert rgba to hex for the color picker (best effort)
          this.stickerBgColorTarget.value = this._rgbaToHex(sticker.bgColor || "rgba(0,0,0,0.7)")
        }
        if (this.hasStickerBgEnabledTarget) {
          this.stickerBgEnabledTarget.checked = sticker.bgEnabled !== false
        }
      }
    }
  }

  // --- Sticker drag / resize / rotate (delegated to StickerInteraction) ---

  _startStickerDrag(pos) {
    this._beginInteraction()
    const sticker = this._stickers.find(s => s.id === this._selectedStickerId)
    this._stickerInteraction.startDrag(sticker, pos)
    this.canvasTarget.style.cursor = "grabbing"
  }

  _duringStickerDrag(pos) {
    const canvas = this.canvasTarget
    if (this._stickerInteraction.duringDrag(pos, canvas.width, canvas.height)) {
      this._scheduleRender()
    }
  }

  _endStickerDrag() {
    this._stickerInteraction.end()
    this._endInteraction()
    this.canvasTarget.style.cursor = "default"
    this._saveStickersToOverrides()
    this._removeDragListeners()
    this._scheduleRender()
    this._pushHistoryImmediate()
  }

  _startStickerResize(pos, handleIdx) {
    this._beginInteraction()
    const sticker = this._stickers.find(s => s.id === this._selectedStickerId)
    this._stickerInteraction.startResize(sticker, pos, handleIdx)
    this.canvasTarget.style.cursor = "grabbing"
  }

  _duringStickerResize(pos) {
    if (this._stickerInteraction.duringResize(pos, this.canvasTarget.width)) {
      this._syncStickerControlsVisibility()
      this._scheduleRender()
    }
  }

  _endStickerResize() {
    this._stickerInteraction.end()
    this._endInteraction()
    this.canvasTarget.style.cursor = "default"
    this._saveStickersToOverrides()
    this._removeDragListeners()
    this._scheduleRender()
    this._pushHistoryImmediate()
  }

  _startStickerRotate(pos) {
    this._beginInteraction()
    const sticker = this._stickers.find(s => s.id === this._selectedStickerId)
    const canvas = this.canvasTarget
    this._stickerInteraction.startRotate(sticker, pos, canvas.width, canvas.height)
    this.canvasTarget.style.cursor = "crosshair"
  }

  _duringStickerRotate(pos) {
    const canvas = this.canvasTarget
    if (this._stickerInteraction.duringRotate(pos, canvas.width, canvas.height)) {
      this._scheduleRender()
    }
  }

  _endStickerRotate() {
    this._stickerInteraction.end()
    this._endInteraction()
    this.canvasTarget.style.cursor = "default"
    this._saveStickersToOverrides()
    this._removeDragListeners()
    this._scheduleRender()
    this._pushHistoryImmediate()
  }

  _removeDragListeners() {
    if (this._boundDragMove) {
      document.removeEventListener("mousemove", this._boundDragMove)
      document.removeEventListener("touchmove", this._boundDragMove)
    }
    if (this._boundDragEnd) {
      document.removeEventListener("mouseup", this._boundDragEnd)
      document.removeEventListener("touchend", this._boundDragEnd)
    }
    this._boundDragMove = null
    this._boundDragEnd = null
    this._canvasRectCache = null
    this._canvasScaleX = 1
    this._canvasScaleY = 1
  }

  // --- Contrasting color helper ---

  _getContrastingColor() {
    const bgType = this.hasBackgroundTypeTarget ? this.backgroundTypeTarget.value : "solid"
    let bgHex = "#000000"
    if (bgType === "gradient") {
      bgHex = this.hasGradientStartTarget ? this.gradientStartTarget.value : "#000000"
    } else if (bgType === "solid") {
      bgHex = this.hasBackgroundColorTarget ? this.backgroundColorTarget.value : "#000000"
    }
    // Calculate luminance and return contrasting color
    const hex = bgHex.replace("#", "")
    const r = parseInt(hex.substring(0, 2), 16) || 0
    const g = parseInt(hex.substring(2, 4), 16) || 0
    const b = parseInt(hex.substring(4, 6), 16) || 0
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    return luminance > 0.5 ? "#1A1A1A" : "#FFFFFF"
  }

  _findAssetImageUrl(assetKey) {
    if (!this._stickerAssetUrlMap) {
      this._stickerAssetUrlMap = new Map()
      const library = this.stickerLibraryValue || {}
      for (const category of Object.values(library)) {
        if (!Array.isArray(category.items)) continue
        for (const item of category.items) {
          if (!item?.key || !item?.image_url) continue
          this._stickerAssetUrlMap.set(item.key, item.image_url)
        }
      }
    }
    return this._stickerAssetUrlMap.get(assetKey) || null
  }

  _ensureStickerMediaLoaded() {
    if (!Array.isArray(this._stickers) || this._stickers.length === 0) return

    const seen = new Set()
    for (const sticker of this._stickers) {
      const type = sticker.type || "emoji"

      if (type === "asset" && sticker.asset_key) {
        const color = sticker.color || "#FFFFFF"
        const cacheKey = `${sticker.asset_key}_${color}`
        if (seen.has(cacheKey)) continue
        seen.add(cacheKey)

        if (getStickerImage(sticker.asset_key, color)) continue
        const imageUrl = this._findAssetImageUrl(sticker.asset_key)
        if (!imageUrl) continue

        loadStickerImage(sticker.asset_key, imageUrl, color)
          .then((img) => { if (img) this._scheduleRender() })
          .catch(() => {})
      }

      if (type === "custom_image" && sticker.image_url) {
        const cacheKey = `custom_${sticker.image_url}`
        if (seen.has(cacheKey)) continue
        seen.add(cacheKey)

        if (getCustomImage(sticker.image_url)) continue
        loadCustomImage(sticker.image_url)
          .then(() => this._scheduleRender())
          .catch(() => {})
      }
    }
  }

  // --- Library preload ---

  _preloadLibrary() {
    const color = this._getContrastingColor()
    preloadEntireLibrary(this.stickerLibraryValue, color)
  }

  _resolveCustomImageRecord({ attachmentId = null, signedId = null, url = null } = {}) {
    const images = Array.isArray(this.customStickerImagesValue) ? this.customStickerImagesValue : []

    if (attachmentId != null && attachmentId !== "") {
      const byAttachment = images.find(i => String(i.attachment_id) === String(attachmentId))
      if (byAttachment) return byAttachment
    }

    if (signedId) {
      const bySigned = images.find(i => String(i.signed_id) === String(signedId))
      if (bySigned) return bySigned
    }

    if (url) {
      const byUrl = images.find(i => i.url === url)
      if (byUrl) return byUrl
      try {
        const raw = (url.split("?")[0] || "").split("/").pop() || ""
        const filename = decodeURIComponent(raw)
        if (filename) {
          const matches = images.filter(i => i.filename === filename)
          if (matches.length === 1) return matches[0]
        }
      } catch {}
    }

    return null
  }

  _hydrateCustomSticker(sticker) {
    const hydrated = { ...sticker }
    if ((hydrated.type || "emoji") !== "custom_image") return hydrated

    const rawAttachmentId = hydrated.image_attachment_id || hydrated.attachment_id
    const rawSignedId = hydrated.image_signed_id || hydrated.signed_id
    const record = this._resolveCustomImageRecord({
      attachmentId: rawAttachmentId,
      signedId: rawSignedId,
      url: hydrated.image_url
    })

    if (record) {
      hydrated.image_url = record.url
      if (record.attachment_id != null) hydrated.image_attachment_id = record.attachment_id
      if (record.signed_id) hydrated.image_signed_id = record.signed_id
      hydrated.__missingCustomImage = false
      return hydrated
    }

    const hasProjectIdentity = (rawAttachmentId != null && rawAttachmentId !== "") || !!rawSignedId
    const url = hydrated.image_url || ""
    const isLocalStorageUrl =
      url.includes("/rails/active_storage/blobs/") ||
      url.includes("/custom_sticker_images/")

    // Mark missing when we can confidently infer this sticker no longer belongs
    // to an existing project attachment.
    hydrated.__missingCustomImage = hasProjectIdentity || isLocalStorageUrl
    return hydrated
  }

  // --- Custom image stickers ---

  async uploadCustomStickerImage() {
    if (!this.hasCustomImageUploadTarget) return
    const input = this.customImageUploadTarget
    const file = input.files[0]
    if (!file) return

    const formData = new FormData()
    formData.append("file", file)

    const projectUrl = this.projectUrlValue
    try {
      const response = await fetch(`${projectUrl}/upload_custom_sticker_image`, {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        }
      })

      const data = await response.json()
      if (response.ok) {
        const nextImages = (this.customStickerImagesValue || []).filter(img => {
          if (data.attachment_id != null && img.attachment_id != null) {
            return String(img.attachment_id) !== String(data.attachment_id)
          }
          return img.signed_id !== data.id
        })
        nextImages.push({
          signed_id: data.id,
          attachment_id: data.attachment_id,
          url: data.url,
          filename: data.filename
        })
        this.customStickerImagesValue = nextImages
        this._renderCustomImageGallery()
      } else {
        alert(data.message || "Upload failed")
      }
    } catch (e) {
      console.warn("[custom_image] Upload error:", e)
      alert("Upload failed")
    }

    // Reset file input
    input.value = ""
  }

  async addCustomImageSticker(event) {
    const inputUrl = event.currentTarget.dataset.imageUrl
    const signedId = event.currentTarget.dataset.signedId
    const attachmentId = event.currentTarget.dataset.attachmentId
    if (!inputUrl && !signedId && !attachmentId) return

    if (this._stickers.length >= this.constructor.MAX_STICKERS_PER_SCENE) return

    const record = this._resolveCustomImageRecord({
      attachmentId,
      signedId,
      url: inputUrl
    })
    const url = record?.url || inputUrl
    if (!url) return

    try {
      await loadCustomImage(url)
    } catch (e) {
      console.warn("[custom_image] Failed to load custom sticker image:", e)
      alert("This image is unavailable. Try re-uploading it.")
      return
    }

    const id = `s_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
    const sticker = {
      id,
      type: "custom_image",
      image_url: url,
      image_attachment_id: record?.attachment_id || attachmentId || null,
      image_signed_id: record?.signed_id || signedId || null,
      x: 50,
      y: 50,
      size: 96,
      rotation: 0
    }
    this._stickers.push(sticker)
    this._selectedStickerId = id
    this._saveStickersToOverrides()
    this._syncStickerControlsVisibility()
    this.updatePreview()
    this._pushHistoryImmediate()
  }

  async deleteCustomStickerImage(event) {
    event.preventDefault()
    event.stopPropagation()

    const signedId = event.currentTarget.dataset.signedId
    const attachmentId = event.currentTarget.dataset.attachmentId
    if (!signedId && !attachmentId) return

    const currentImages = this.customStickerImagesValue || []
    const deletedImage = this._resolveCustomImageRecord({ attachmentId, signedId })
    const deletedUrl = deletedImage?.url
    const deletedAttachmentId = deletedImage?.attachment_id || attachmentId
    const deletedSignedId = deletedImage?.signed_id || signedId

    const projectUrl = this.projectUrlValue
    try {
      const response = await fetch(`${projectUrl}/delete_custom_sticker_image`, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({ signed_id: signedId, attachment_id: attachmentId })
      })

      if (response.ok) {
        this.customStickerImagesValue = currentImages.filter(i => {
          if (deletedAttachmentId != null && i.attachment_id != null && String(i.attachment_id) === String(deletedAttachmentId)) {
            return false
          }
          if (deletedSignedId && String(i.signed_id) === String(deletedSignedId)) {
            return false
          }
          return true
        })

        // Also remove any placed stickers that reference the deleted custom image
        if (deletedUrl || deletedAttachmentId || deletedSignedId) {
          const matchesDeletedSticker = (s) => {
            if (s.type !== "custom_image") return false
            if (deletedAttachmentId != null && s.image_attachment_id != null && String(s.image_attachment_id) === String(deletedAttachmentId)) return true
            if (deletedSignedId && s.image_signed_id && String(s.image_signed_id) === String(deletedSignedId)) return true
            return s.image_url === deletedUrl
          }
          const selectedRemoved = this._selectedStickerId && this._stickers.some(s =>
            s.id === this._selectedStickerId && matchesDeletedSticker(s)
          )
          const nextStickers = this._stickers.filter(s => !matchesDeletedSticker(s))
          if (nextStickers.length !== this._stickers.length) {
            this._stickers = nextStickers
            this._stickerBounds = []
            if (selectedRemoved) this._selectedStickerId = null
            this._saveStickersToOverrides()
            this._syncStickerControlsVisibility()
            this.updatePreview()
            this._pushHistoryImmediate()
          }
        }

        this._renderCustomImageGallery()
      }
    } catch (e) {
      console.warn("[custom_image] Delete error:", e)
    }
  }

  _renderCustomImageGallery() {
    if (!this.hasCustomImageGalleryTarget) return
    const images = this.customStickerImagesValue || []
    const gallery = this.customImageGalleryTarget

    // Clear existing children
    while (gallery.firstChild) gallery.removeChild(gallery.firstChild)

    if (images.length === 0) {
      const emptyMsg = document.createElement("p")
      emptyMsg.className = "text-xs text-base-content/40 text-center py-3 col-span-3"
      emptyMsg.textContent = "No images uploaded yet"
      gallery.appendChild(emptyMsg)
      return
    }

    for (const img of images) {
      const wrapper = document.createElement("div")
      wrapper.className = "relative group"

      const addBtn = document.createElement("button")
      addBtn.type = "button"
      addBtn.className = "w-full aspect-square rounded-lg border border-base-200 hover:border-primary/50 overflow-hidden flex items-center justify-center bg-base-200/30 transition-all"
      addBtn.dataset.action = "click->screenshot-editor#addCustomImageSticker"
      addBtn.dataset.imageUrl = img.url
      if (img.signed_id) addBtn.dataset.signedId = img.signed_id
      if (img.attachment_id != null) addBtn.dataset.attachmentId = img.attachment_id
      addBtn.title = img.filename

      const imgEl = document.createElement("img")
      imgEl.src = img.url
      imgEl.className = "max-w-full max-h-full object-contain"
      imgEl.alt = img.filename
      imgEl.loading = "lazy"
      imgEl.onerror = () => {
        while (addBtn.firstChild) addBtn.removeChild(addBtn.firstChild)
        const fallback = document.createElement("span")
        fallback.className = "text-[10px] text-base-content/50 px-1 text-center break-all leading-tight"
        fallback.textContent = img.filename || "Image unavailable"
        addBtn.appendChild(fallback)
        addBtn.classList.add("opacity-60", "cursor-not-allowed")
        addBtn.removeAttribute("data-action")
        addBtn.title = `${img.filename || "Image"} (unavailable)`
      }
      addBtn.appendChild(imgEl)

      const delBtn = document.createElement("button")
      delBtn.type = "button"
      delBtn.className = "absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-error text-error-content flex items-center justify-center text-[10px] opacity-0 group-hover:opacity-100 transition-opacity shadow-sm"
      delBtn.dataset.action = "click->screenshot-editor#deleteCustomStickerImage"
      if (img.signed_id) delBtn.dataset.signedId = img.signed_id
      if (img.attachment_id != null) delBtn.dataset.attachmentId = img.attachment_id
      delBtn.title = "Delete image"

      const delIcon = document.createElement("i")
      delIcon.className = "fa-solid fa-xmark"
      delBtn.appendChild(delIcon)

      wrapper.appendChild(addBtn)
      wrapper.appendChild(delBtn)
      gallery.appendChild(wrapper)
    }
  }

  // --- Copy scene modal ---

  openCopySceneModal(event) {
    event.preventDefault()
    event.stopPropagation()

    const sceneId = event.currentTarget.dataset.sceneId
    const modal = document.getElementById("copy_scene_modal")
    const form = document.getElementById("copy_scene_form")

    if (form && sceneId) {
      // Build the action URL dynamically
      const baseUrl = form.dataset.baseUrl
      form.action = baseUrl.replace("__SCENE_ID__", sceneId)
    }

    if (modal) {
      modal.showModal()
    } else {
      alert("No other projects available. Create another project first to copy scenes.")
    }
  }

  closeCopySceneModal(event) {
    event.preventDefault()
    const modal = document.getElementById("copy_scene_modal")
    if (modal?.open) modal.close()
  }
}
