import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "modal", "tabContent",
    "ascAppSelect", "ascVersionSelect", "ascLocaleInput", "ascPresetCheckbox", "ascAllLocalesCheckbox",
    "gpAppSelect", "gpLanguageInput", "gpPresetCheckbox", "gpAllLocalesCheckbox",
    "cppSelect", "cppLocaleSelect", "cppPresetCheckbox", "cppReplaceExisting",
    "replaceExisting",
    "progressContainer", "progressText", "progressBar",
    "progressSpinner", "successIcon", "errorIcon",
    "uploadButton", "statusText",
    "ascFetchButton", "ascScreenshotPreview", "ascScreenshotLoading", "ascScreenshotGrid",
    "ascScreenshotEmpty", "ascScreenshotImages", "ascScreenshotCount", "ascScreenshotError",
    "gpFetchButton", "gpScreenshotPreview", "gpScreenshotLoading", "gpScreenshotGrid",
    "gpScreenshotEmpty", "gpScreenshotImages", "gpScreenshotCount", "gpScreenshotError"
  ]

  static values = {
    projectId: Number,
    organizationId: Number,
    hasAscCredentials: Boolean,
    hasGpCredentials: Boolean,
    storeUploadsEnabled: Boolean,
    currentPlan: String,
    nextPlan: String,
    dailyUploadsUsed: Number,
    dailyUploadLimit: Number,
    dailyLimitReached: Boolean
  }

  get webBasePath() {
    return `/organizations/${this.organizationIdValue}/screenshot_projects/${this.projectIdValue}`
  }

  connect() {
    this.pollingInterval = null
    this.currentUploadTarget = null
    this._lightbox = null

    // Flush preview data when the modal closes (backdrop click, Cancel, Escape, etc.)
    this._handleModalClose = () => this.flushPreviews()
    const modal = document.getElementById("store_upload_modal")
    if (modal) modal.addEventListener("close", this._handleModalClose)
  }

  disconnect() {
    this.stopPolling()
    this.destroyLightbox()

    const modal = document.getElementById("store_upload_modal")
    if (modal) modal.removeEventListener("close", this._handleModalClose)
  }

  openModal(event) {
    if (event) event.preventDefault()

    if (!this.storeUploadsEnabledValue) {
      this.presentUpgradePrompt({
        current_plan: this.currentPlanValue || "free",
        required_plan: this.nextPlanValue || "pro",
        feature: "direct store uploads",
        message: "Direct store uploads are available on paid plans only.",
        suggestion: this.planUpgradeSuggestion(this.nextPlanValue || "pro", "direct store uploads"),
        source: "Screenshot Studio upload button"
      })
      return
    }

    if (this.dailyLimitReachedValue) {
      this.presentUpgradePrompt({
        current_plan: this.currentPlanValue || "pro",
        required_plan: this.nextPlanValue || "",
        feature: "daily store uploads",
        message: `You've used ${this.dailyUploadsUsedValue} of ${this.dailyUploadLimitValue} store uploads in the last 24 hours.`,
        suggestion: this.quotaUpgradeSuggestion("daily store uploads"),
        source: "Screenshot Studio upload button"
      })
      return
    }

    this.resetProgressState()
    const modal = document.getElementById("store_upload_modal")
    if (modal) modal.showModal()
  }

  toggleAllLocales(event) {
    const checked = event.currentTarget.checked
    // Determine which locale select to toggle based on the checkbox target
    if (event.currentTarget === this.ascAllLocalesCheckboxTarget) {
      if (this.hasAscLocaleInputTarget) this.ascLocaleInputTarget.disabled = checked
    } else if (event.currentTarget === this.gpAllLocalesCheckboxTarget) {
      if (this.hasGpLanguageInputTarget) this.gpLanguageInputTarget.disabled = checked
    }
  }

  switchTab(event) {
    const tab = event.currentTarget.dataset.tab
    this.tabContentTargets.forEach(el => {
      el.classList.toggle("hidden", el.dataset.tabName !== tab)
    })
    event.currentTarget.closest(".tabs").querySelectorAll(".tab").forEach(t => {
      t.classList.toggle("tab-active", t.dataset.tab === tab)
    })

    // Auto-populate CPP locale dropdown when switching to the CPP tab
    if (tab === "cpp" && this.hasCppSelectTarget) {
      this.populateCppLocales()
    }
  }

  onCppSelect() {
    this.populateCppLocales()
  }

  populateCppLocales() {
    if (!this.hasCppSelectTarget || !this.hasCppLocaleSelectTarget) return

    const selected = this.cppSelectTarget.selectedOptions[0]
    if (!selected) return

    let localizations = []
    try {
      localizations = JSON.parse(selected.dataset.localizations || "[]")
    } catch { localizations = [] }

    const localeSelect = this.cppLocaleSelectTarget
    while (localeSelect.firstChild) localeSelect.removeChild(localeSelect.firstChild)

    if (localizations.length === 0) {
      const opt = document.createElement("option")
      opt.value = ""
      opt.textContent = "No localizations available"
      localeSelect.appendChild(opt)
      return
    }

    localizations.forEach(loc => {
      const opt = document.createElement("option")
      opt.value = loc.remote_id || loc.id
      opt.dataset.locale = loc.locale
      opt.textContent = loc.locale
      localeSelect.appendChild(opt)
    })
  }

  async fetchCurrentScreenshots(event) {
    const target = event.currentTarget.dataset.fetchTarget
    const isAsc = target === "app_store_connect"
    const prefix = isAsc ? "asc" : "gp"

    // Get target elements
    const previewEl = this[`${prefix}ScreenshotPreviewTarget`]
    const loadingEl = this[`${prefix}ScreenshotLoadingTarget`]
    const gridEl = this[`${prefix}ScreenshotGridTarget`]
    const emptyEl = this[`${prefix}ScreenshotEmptyTarget`]
    const imagesEl = this[`${prefix}ScreenshotImagesTarget`]
    const countEl = this[`${prefix}ScreenshotCountTarget`]
    const errorEl = this[`${prefix}ScreenshotErrorTarget`]
    const fetchBtn = this[`${prefix}FetchButtonTarget`]

    // Show loading state
    previewEl.classList.remove("hidden")
    loadingEl.classList.remove("hidden")
    gridEl.classList.add("hidden")
    errorEl.classList.add("hidden")
    fetchBtn.disabled = true

    // Build query params
    const params = new URLSearchParams({ target })
    if (isAsc) {
      if (this.hasAscVersionSelectTarget) params.set("version_id", this.ascVersionSelectTarget.value)
      if (this.hasAscLocaleInputTarget) params.set("locale", this.ascLocaleInputTarget.value)
    } else {
      if (this.hasGpAppSelectTarget) params.set("package_name", this.gpAppSelectTarget.value)
      if (this.hasGpLanguageInputTarget) params.set("language", this.gpLanguageInputTarget.value)
    }

    try {
      const response = await fetch(`${this.webBasePath}/current_store_screenshots?${params}`)
      if (!response.ok) {
        const err = await response.json().catch(() => ({}))
        throw new Error(err.message || `HTTP ${response.status}`)
      }

      const result = await response.json()
      const screenshots = result.data?.screenshots || []

      loadingEl.classList.add("hidden")
      gridEl.classList.remove("hidden")

      // Clear previous images
      while (imagesEl.firstChild) imagesEl.removeChild(imagesEl.firstChild)

      if (screenshots.length === 0) {
        emptyEl.classList.remove("hidden")
        countEl.classList.add("hidden")
      } else {
        emptyEl.classList.add("hidden")

        // Group by display_type (ASC) or image_type (GP)
        const groupKey = isAsc ? "display_type" : "image_type"
        const grouped = {}
        screenshots.forEach(ss => {
          const key = ss[groupKey] || "unknown"
          if (!grouped[key]) grouped[key] = []
          grouped[key].push(ss)
        })

        Object.entries(grouped).forEach(([groupName, items]) => {
          const group = document.createElement("div")
          group.className = "rounded-lg bg-base-300/30 border border-base-300/50 overflow-hidden"

          // Header with device icon, name and count
          const header = document.createElement("div")
          header.className = "flex items-center gap-2 px-3 py-2 border-b border-base-300/40"

          const deviceIcon = document.createElement("i")
          deviceIcon.className = `fa-solid ${this.deviceIcon(groupName)} text-xs text-base-content/40`
          header.appendChild(deviceIcon)

          const label = document.createElement("span")
          label.className = "text-xs font-semibold text-base-content/70 flex-1"
          label.textContent = this.formatDisplayType(groupName)
          header.appendChild(label)

          const badge = document.createElement("span")
          badge.className = "text-[10px] font-medium text-base-content/40 bg-base-content/5 px-1.5 py-0.5 rounded-full"
          badge.textContent = items.length
          header.appendChild(badge)

          group.appendChild(header)

          // Scrollable strip of thumbnails
          const strip = document.createElement("div")
          strip.className = "flex gap-2 overflow-x-auto p-2.5 scroll-smooth snap-x"

          items.forEach(ss => {
            const card = document.createElement("div")
            card.className = "shrink-0 snap-start group/thumb"

            if (ss.url) {
              const img = document.createElement("img")
              img.src = ss.url
              img.className = "h-28 w-auto rounded-md border border-base-300/60 bg-base-100 object-contain shadow-sm cursor-pointer transition-transform duration-150 group-hover/thumb:scale-[1.03]"
              img.loading = "lazy"
              img.alt = ss.file_name || "Store screenshot"
              img.title = [
                ss.file_name,
                ss.width && ss.height ? `${ss.width}x${ss.height}` : null
              ].filter(Boolean).join(" \u2014 ")

              // Build the full-res URL for lightbox (remove thumbnail size cap)
              let fullUrl = ss.url
              if (ss.width && ss.height) {
                fullUrl = ss.url.replace(/\/\d+x\d+/, `/${ss.width}x${ss.height}`)
              }
              img.addEventListener("click", () => this.openLightbox(fullUrl, ss.file_name, ss.width, ss.height))
              card.appendChild(img)
            } else {
              const placeholder = document.createElement("div")
              placeholder.className = "h-28 w-16 rounded-md border border-base-300/60 bg-base-200/60 flex items-center justify-center"
              const icon = document.createElement("i")
              icon.className = "fa-regular fa-image text-base-content/20 text-sm"
              placeholder.appendChild(icon)
              card.appendChild(placeholder)
            }

            strip.appendChild(card)
          })

          group.appendChild(strip)
          imagesEl.appendChild(group)
        })

        countEl.textContent = `${screenshots.length} screenshot${screenshots.length === 1 ? "" : "s"} currently live`
        countEl.classList.remove("hidden")
      }

      // Show message if returned
      if (result.data?.message && screenshots.length === 0) {
        errorEl.classList.remove("hidden")
        errorEl.querySelector("p").textContent = result.data.message
      }
    } catch (error) {
      loadingEl.classList.add("hidden")
      gridEl.classList.add("hidden")
      errorEl.classList.remove("hidden")
      errorEl.querySelector("p").textContent = error.message || "Failed to fetch screenshots"
    } finally {
      fetchBtn.disabled = false
    }
  }

  formatDisplayType(type) {
    const map = {
      "APP_IPHONE_67": "iPhone 6.7\"/6.9\"",
      "APP_IPHONE_65": "iPhone 6.5\"",
      "APP_IPHONE_55": "iPhone 5.5\"",
      "APP_IPAD_PRO_3GEN_129": "iPad Pro 12.9\"",
      "APP_IPAD_PRO_3GEN_11": "iPad Pro 11\"",
      "phoneScreenshots": "Phone",
      "sevenInchScreenshots": "7\" Tablet",
      "tenInchScreenshots": "10\" Tablet"
    }
    return map[type] || type.replace(/([A-Z])/g, " $1").replace(/_/g, " ").trim()
  }

  deviceIcon(type) {
    if (type.includes("IPAD") || type.includes("tablet") || type.includes("Inch")) return "fa-tablet-screen-button"
    return "fa-mobile-screen-button"
  }

  async startUpload(event) {
    const target = event.currentTarget.dataset.uploadTarget
    this.currentUploadTarget = target

    if (this.hasUploadButtonTarget) {
      this.uploadButtonTargets.forEach(btn => btn.disabled = true)
    }

    this.showProgress()
    this.updateProgressText("Rendering screenshots...")
    this.updateProgressBar(0)

    try {
      // Step 1: Render all PNGs and upload as single batch
      await this.renderAndUploadBatch(target)

      // Step 2: Trigger store upload
      this.updateProgressText("Starting store upload...")
      const uploadId = await this.triggerStoreUpload(target)

      // Step 3: Poll for progress
      this.pollUploadStatus(uploadId)
    } catch (error) {
      if (this.handleUpgradeError(error)) return

      console.error("Store upload failed:", error)
      this.showError(`Upload failed: ${error.message}`)
      this.resetButtons()
    }
  }

  async renderAndUploadBatch(target) {
    const editorController = this.application.getControllerForElementAndIdentifier(this.element, "screenshot-editor")
    if (!editorController) throw new Error("Editor controller not found")

    const settings = editorController.getCurrentSettings()
    const sceneDataTargets = editorController.getSceneDataTargets()
    const imageCache = editorController.getImageCache()
    const allPresets = JSON.parse(this.element.dataset.screenshotExportPresetsValue || "{}")

    if (sceneDataTargets.length === 0) throw new Error("No scenes to export")

    let selectedPresets = []
    if (target === "app_store_connect") {
      selectedPresets = this.ascPresetCheckboxTargets.filter(cb => cb.checked).map(cb => cb.dataset.preset)
    } else if (target === "custom_product_page") {
      selectedPresets = this.cppPresetCheckboxTargets.filter(cb => cb.checked).map(cb => cb.dataset.preset)
    } else {
      selectedPresets = this.gpPresetCheckboxTargets.filter(cb => cb.checked).map(cb => cb.dataset.preset)
    }

    if (selectedPresets.length === 0) throw new Error("No sizes selected")

    // Determine the locale(s) to render. When "Upload all locales" is checked,
    // collect every locale option from the dropdown and render a full batch per
    // locale so each batch gets the correct locale-specific text overlays.
    const allLocalesChecked = this.isAllLocalesChecked(target)
    const localesToRender = allLocalesChecked
      ? this.collectAllLocaleOptions(target)
      : [this.selectedStoreLocale(target)]

    const sizes = []
    selectedPresets.forEach(key => {
      const preset = allPresets[key]
      if (preset) preset.forEach(size => sizes.push({ ...size, preset: key }))
    })

    const totalWork = sceneDataTargets.length * sizes.length * localesToRender.length
    let completed = 0

    // Render all screenshots and collect blobs, grouped by locale
    const allEntries = []

    for (const locale of localesToRender) {
      for (const sceneData of sceneDataTargets) {
        const sceneId = sceneData.dataset.sceneId
        const defaultCaption = sceneData.dataset.sceneCaption || ""
        const defaultSubtitle = sceneData.dataset.sceneSubtitle || ""
        const position = sceneData.dataset.scenePosition || "1"
        let sceneOverrides = {}
        try { sceneOverrides = JSON.parse(sceneData.dataset.sceneOverrides || "{}") } catch {}

        // Resolve locale-specific caption/subtitle (mirrors ScreenshotScene#caption_for_locale)
        let localeVariants = {}
        try { localeVariants = JSON.parse(sceneData.dataset.sceneLocaleVariants || "{}") } catch {}

        const caption = this.captionForLocale(locale, defaultCaption, localeVariants)
        const subtitle = this.subtitleForLocale(locale, defaultSubtitle, localeVariants)

        let image = imageCache.get(sceneId)
        if (!image) {
          image = await this.loadImage(sceneData.dataset.sceneImageUrl)
          imageCache.set(sceneId, image)
        }

        for (const size of sizes) {
          const sceneSettings = { ...settings, caption_text: caption, subtitle_text: subtitle, ...sceneOverrides }
          // Use the preset's matching device frame for correct dimensions
          if (settings.device_frame && settings.device_frame !== "none" && size.device_frame) {
            sceneSettings.device_frame = size.device_frame
          }
          const canvas = await editorController.renderAtSize(image, size.width, size.height, sceneSettings)

          const blob = await new Promise((resolve, reject) =>
            canvas.toBlob(b => b ? resolve(b) : reject(new Error("Canvas export failed — canvas may be tainted by cross-origin images")), "image/png")
          )

          allEntries.push({
            width: size.width,
            height: size.height,
            scene_position: parseInt(position),
            locale: locale,
            blob: blob
          })

          completed++
          const pct = Math.round((completed / totalWork) * 80) // 0-80% for rendering
          const localeLabel = allLocalesChecked ? ` [${locale}]` : ""
          this.updateProgressText(`Rendering${localeLabel}... ${completed}/${totalWork}`)
          this.updateProgressBar(pct)
        }
      }
    }

    // Send all screenshots as multipart FormData (binary, no base64 overhead)
    this.updateProgressText("Uploading to server...")
    this.updateProgressBar(85)

    const formData = new FormData()
    allEntries.forEach((entry, i) => {
      formData.append(`screenshots[${i}][width]`, entry.width)
      formData.append(`screenshots[${i}][height]`, entry.height)
      formData.append(`screenshots[${i}][scene_position]`, entry.scene_position)
      formData.append(`screenshots[${i}][locale]`, entry.locale)
      formData.append(`screenshots[${i}][file]`, entry.blob, `screenshot_${i}.png`)
    })

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch(this.webBasePath + "/upload_export", {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken
      },
      body: formData
    })

    if (!response.ok) {
      throw await this.buildResponseError(response, "Failed to upload screenshots")
    }

    this.updateProgressBar(90)
  }

  async triggerStoreUpload(target) {
    const config = this.buildConfig(target)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    const response = await fetch(this.webBasePath + "/start_store_upload", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({
        target: target,
        config: config
      })
    })

    if (!response.ok) {
      throw await this.buildResponseError(response, "Failed to start upload")
    }

    const result = await response.json()
    return result.data.id
  }

  buildConfig(target) {
    if (target === "app_store_connect") {
      const presets = this.ascPresetCheckboxTargets.filter(cb => cb.checked).map(cb => cb.dataset.preset)
      const allLocales = this.hasAscAllLocalesCheckboxTarget && this.ascAllLocalesCheckboxTarget.checked
      const config = {
        version_id: this.hasAscVersionSelectTarget ? this.ascVersionSelectTarget.value : "",
        presets: presets,
        replace_existing: this.hasReplaceExistingTarget ? this.replaceExistingTarget.checked : false
      }
      if (allLocales) {
        config.all_locales = true
      } else {
        config.locale = this.hasAscLocaleInputTarget ? this.ascLocaleInputTarget.value : "en-US"
      }
      return config
    } else if (target === "custom_product_page") {
      const presets = this.cppPresetCheckboxTargets.filter(cb => cb.checked).map(cb => cb.dataset.preset)
      const selectedLocaleOpt = this.hasCppLocaleSelectTarget ? this.cppLocaleSelectTarget.selectedOptions[0] : null
      return {
        cpp_id: this.hasCppSelectTarget ? this.cppSelectTarget.value : "",
        cpp_localization_id: this.hasCppLocaleSelectTarget ? this.cppLocaleSelectTarget.value : "",
        presets: presets,
        replace_existing: this.hasCppReplaceExistingTarget ? this.cppReplaceExistingTarget.checked : false,
        locale: selectedLocaleOpt?.dataset?.locale || "en-US"
      }
    } else {
      const presets = this.gpPresetCheckboxTargets.filter(cb => cb.checked).map(cb => cb.dataset.preset)
      const allLocales = this.hasGpAllLocalesCheckboxTarget && this.gpAllLocalesCheckboxTarget.checked
      const config = {
        package_name: this.hasGpAppSelectTarget ? this.gpAppSelectTarget.value : "",
        presets: presets,
        replace_existing: this.hasReplaceExistingTarget ? this.replaceExistingTarget.checked : false
      }
      if (allLocales) {
        config.all_locales = true
      } else {
        config.language = this.hasGpLanguageInputTarget ? this.gpLanguageInputTarget.value : "en-US"
      }
      return config
    }
  }

  pollUploadStatus(uploadId) {
    this.pollingInterval = setInterval(async () => {
      try {
        const response = await fetch(this.webBasePath + `/upload_status?upload_id=${uploadId}`)
        if (!response.ok) return

        const result = await response.json()
        const upload = result.data
        const progress = upload.progress || {}

        if (upload.status === "in_progress") {
          const completed = progress.completed || 0
          const total = progress.total || 1
          const pct = 90 + Math.round((completed / total) * 10) // 90-100%
          const targetLabels = { app_store_connect: "App Store Connect", google_play: "Google Play", custom_product_page: "Custom Product Page" }
          const targetLabel = targetLabels[this.currentUploadTarget] || this.currentUploadTarget
          const localeInfo = progress.current_locale ? ` [${progress.current_locale}]` : ""
          this.updateProgressText(`Uploading to ${targetLabel}${localeInfo}... ${completed}/${total}`)
          this.updateProgressBar(pct)
        } else if (upload.status === "completed") {
          this.stopPolling()
          this.showSuccess("Upload completed successfully!")
          this.resetButtons()
        } else if (upload.status === "failed") {
          this.stopPolling()
          const errors = (progress.errors || []).join(", ")
          this.showError(`Upload failed: ${errors}`)
          this.resetButtons()
        }
      } catch (error) {
        console.error("Polling error:", error)
      }
    }, 3000)
  }

  stopPolling() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
      this.pollingInterval = null
    }
  }

  handleUpgradeError(error) {
    if (!error?.payload) return false

    const { payload } = error
    if (!["plan_upgrade_required", "quota_exhausted"].includes(payload.error)) return false

    this.stopPolling()
    this.resetButtons()
    this.closeModal()

    this.presentUpgradePrompt({
      current_plan: payload.current_plan || this.currentPlanValue || "free",
      required_plan: payload.required_plan || payload.next_plan || this.nextPlanValue || "",
      feature: payload.feature || (payload.error === "plan_upgrade_required" ? "direct store uploads" : "store upload limits"),
      message: payload.message,
      suggestion: payload.suggestion,
      source: "Screenshot Studio upload flow"
    })

    return true
  }

  // --- Progress state helpers ---

  showProgress() {
    if (this.hasProgressContainerTarget) {
      this.progressContainerTarget.classList.remove("hidden")
    }
    if (this.hasProgressSpinnerTarget) this.progressSpinnerTarget.classList.remove("hidden")
    if (this.hasSuccessIconTarget) this.successIconTarget.classList.add("hidden")
    if (this.hasErrorIconTarget) this.errorIconTarget.classList.add("hidden")
  }

  showSuccess(message) {
    if (this.hasProgressSpinnerTarget) this.progressSpinnerTarget.classList.add("hidden")
    if (this.hasSuccessIconTarget) this.successIconTarget.classList.remove("hidden")
    if (this.hasErrorIconTarget) this.errorIconTarget.classList.add("hidden")
    if (this.hasProgressBarTarget) this.progressBarTarget.classList.add("hidden")
    this.updateProgressText(message)
    this.updateProgressBar(100)
  }

  showError(message) {
    if (this.hasProgressSpinnerTarget) this.progressSpinnerTarget.classList.add("hidden")
    if (this.hasSuccessIconTarget) this.successIconTarget.classList.add("hidden")
    if (this.hasErrorIconTarget) this.errorIconTarget.classList.remove("hidden")
    if (this.hasProgressBarTarget) this.progressBarTarget.classList.add("hidden")
    this.updateProgressText(message)
  }

  resetProgressState() {
    if (this.hasProgressContainerTarget) this.progressContainerTarget.classList.add("hidden")
    if (this.hasProgressBarTarget) this.progressBarTarget.classList.remove("hidden")
    if (this.hasProgressSpinnerTarget) this.progressSpinnerTarget.classList.remove("hidden")
    if (this.hasSuccessIconTarget) this.successIconTarget.classList.add("hidden")
    if (this.hasErrorIconTarget) this.errorIconTarget.classList.add("hidden")
    this.updateProgressText("Preparing...")
    this.updateProgressBar(0)
    this.resetButtons()
  }

  updateProgressText(text) {
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = text
    }
  }

  updateProgressBar(pct) {
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.value = pct
    }
  }

  resetButtons() {
    if (this.hasUploadButtonTarget) {
      this.uploadButtonTargets.forEach(btn => btn.disabled = false)
    }
  }

  closeModal() {
    if (this.hasModalTarget && this.modalTarget.open) {
      this.modalTarget.close()
    }
  }

  // --- Lightbox for full-size screenshot preview ---

  openLightbox(url, fileName, width, height) {
    this.destroyLightbox()

    const overlay = document.createElement("div")
    overlay.className = "fixed inset-0 z-[9999] flex items-center justify-center bg-black/80 backdrop-blur-sm"
    overlay.style.animation = "fadeIn 150ms ease-out"

    // Close on backdrop click
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) this.destroyLightbox()
    })

    // Container
    const container = document.createElement("div")
    container.className = "relative max-w-[90vw] max-h-[90vh] flex flex-col items-center gap-3"

    // Close button
    const closeBtn = document.createElement("button")
    closeBtn.className = "absolute -top-3 -right-3 w-8 h-8 rounded-full bg-base-100 border border-base-300 shadow-lg flex items-center justify-center text-base-content/60 hover:text-base-content hover:bg-base-200 transition-colors z-10 cursor-pointer"
    const closeIcon = document.createElement("i")
    closeIcon.className = "fa-solid fa-xmark text-sm"
    closeBtn.appendChild(closeIcon)
    closeBtn.addEventListener("click", () => this.destroyLightbox())
    container.appendChild(closeBtn)

    // Spinner while loading
    const spinner = document.createElement("div")
    spinner.className = "absolute inset-0 flex items-center justify-center"
    const spinnerEl = document.createElement("span")
    spinnerEl.className = "loading loading-spinner loading-md text-base-content/40"
    spinner.appendChild(spinnerEl)
    container.appendChild(spinner)

    // Image
    const img = document.createElement("img")
    img.src = url
    img.alt = fileName || "Screenshot preview"
    img.className = "max-w-[90vw] max-h-[80vh] rounded-lg shadow-2xl object-contain opacity-0 transition-opacity duration-200"
    img.onload = () => {
      spinner.remove()
      img.classList.replace("opacity-0", "opacity-100")
    }
    img.onerror = () => {
      spinner.remove()
      img.classList.replace("opacity-0", "opacity-100")
    }
    container.appendChild(img)

    // Caption bar
    const meta = []
    if (fileName) meta.push(fileName)
    if (width && height) meta.push(`${width}\u00d7${height}`)
    if (meta.length) {
      const caption = document.createElement("div")
      caption.className = "text-xs text-base-content/50 bg-base-100/80 backdrop-blur-sm px-3 py-1.5 rounded-full border border-base-300/40"
      caption.textContent = meta.join(" \u2014 ")
      container.appendChild(caption)
    }

    overlay.appendChild(container)

    // Append inside the <dialog> so the lightbox sits in the same top-layer stacking context
    const dialog = document.getElementById("store_upload_modal")
    ;(dialog || document.body).appendChild(overlay)
    this._lightbox = overlay

    // Close on Escape
    this._lightboxEscHandler = (e) => {
      if (e.key === "Escape") this.destroyLightbox()
    }
    document.addEventListener("keydown", this._lightboxEscHandler)
  }

  destroyLightbox() {
    if (this._lightbox) {
      this._lightbox.remove()
      this._lightbox = null
    }
    if (this._lightboxEscHandler) {
      document.removeEventListener("keydown", this._lightboxEscHandler)
      this._lightboxEscHandler = null
    }
  }

  // --- Flush preview data on modal close ---

  flushPreviews() {
    for (const prefix of ["asc", "gp"]) {
      const capPrefix = prefix.charAt(0).toUpperCase() + prefix.slice(1)

      // Nuke all image elements and device group cards
      if (this[`has${capPrefix}ScreenshotImagesTarget`]) {
        const container = this[`${prefix}ScreenshotImagesTarget`]
        while (container.firstChild) container.removeChild(container.firstChild)
      }

      // Reset visibility to initial hidden states
      if (this[`has${capPrefix}ScreenshotPreviewTarget`]) {
        this[`${prefix}ScreenshotPreviewTarget`].classList.add("hidden")
      }
      if (this[`has${capPrefix}ScreenshotGridTarget`]) {
        this[`${prefix}ScreenshotGridTarget`].classList.add("hidden")
      }
      if (this[`has${capPrefix}ScreenshotCountTarget`]) {
        const countEl = this[`${prefix}ScreenshotCountTarget`]
        countEl.classList.add("hidden")
        countEl.textContent = ""
      }
      if (this[`has${capPrefix}ScreenshotErrorTarget`]) {
        this[`${prefix}ScreenshotErrorTarget`].classList.add("hidden")
      }
      if (this[`has${capPrefix}ScreenshotEmptyTarget`]) {
        this[`${prefix}ScreenshotEmptyTarget`].classList.add("hidden")
      }
    }

    this.destroyLightbox()
  }

  async buildResponseError(response, fallbackMessage) {
    let payload = null

    try {
      payload = await response.json()
    } catch {
      payload = null
    }

    const messageParts = [payload?.message, payload?.suggestion].filter(Boolean)
    const error = new Error(messageParts.join(" ") || fallbackMessage)
    error.code = payload?.error || null
    error.payload = payload
    return error
  }

  presentUpgradePrompt(payload) {
    document.dispatchEvent(new CustomEvent("mysigner:upgrade-prompt", {
      detail: {
        ...(payload || {}),
        sourceElement: this.element
      }
    }))
  }

  planUpgradeSuggestion(requiredPlan, feature) {
    const currentName = this.titleize(this.currentPlanValue || "free")
    const requiredName = this.titleize(requiredPlan || "pro")
    return `Upgrade from ${currentName} to ${requiredName} to use ${feature}.`
  }

  quotaUpgradeSuggestion(feature) {
    const currentName = this.titleize(this.currentPlanValue || "pro")
    if (this.nextPlanValue) {
      return `Upgrade from ${currentName} to ${this.titleize(this.nextPlanValue)} to increase the ${feature} limit.`
    }

    return `Your ${currentName} plan has reached its ${feature} limit. Contact support if you need more capacity.`
  }

  titleize(value) {
    return value.toString().replace(/_/g, " ").replace(/\b\w/g, char => char.toUpperCase())
  }

  // Returns the locale selected in the store upload modal for the given target.
  selectedStoreLocale(target) {
    if (target === "app_store_connect") {
      return this.hasAscLocaleInputTarget ? this.ascLocaleInputTarget.value : ""
    } else if (target === "custom_product_page") {
      const opt = this.hasCppLocaleSelectTarget ? this.cppLocaleSelectTarget.selectedOptions[0] : null
      return opt?.dataset?.locale || "en-US"
    } else {
      return this.hasGpLanguageInputTarget ? this.gpLanguageInputTarget.value : ""
    }
  }

  // Returns true when the "Upload all locales" checkbox is checked for the target.
  isAllLocalesChecked(target) {
    if (target === "app_store_connect") {
      return this.hasAscAllLocalesCheckboxTarget && this.ascAllLocalesCheckboxTarget.checked
    } else if (target === "custom_product_page") {
      return false // CPP uploads one locale at a time
    } else {
      return this.hasGpAllLocalesCheckboxTarget && this.gpAllLocalesCheckboxTarget.checked
    }
  }

  // Collects all locale option values from the locale dropdown for the given target.
  collectAllLocaleOptions(target) {
    let selectEl
    if (target === "app_store_connect") {
      selectEl = this.hasAscLocaleInputTarget ? this.ascLocaleInputTarget : null
    } else {
      selectEl = this.hasGpLanguageInputTarget ? this.gpLanguageInputTarget : null
    }
    if (!selectEl) return []
    return Array.from(selectEl.options).map(opt => opt.value).filter(Boolean)
  }

  // Mirrors ScreenshotScene#caption_for_locale — returns locale-specific text or default
  captionForLocale(locale, defaultCaption, localeVariants) {
    if (!locale) return defaultCaption
    const variant = localeVariants[locale]
    return (variant && variant.caption_text) ? variant.caption_text : defaultCaption
  }

  // Mirrors ScreenshotScene#subtitle_for_locale — returns locale-specific text or default
  subtitleForLocale(locale, defaultSubtitle, localeVariants) {
    if (!locale) return defaultSubtitle
    const variant = localeVariants[locale]
    return (variant && variant.subtitle_text) ? variant.subtitle_text : defaultSubtitle
  }

  loadImage(url) {
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.crossOrigin = "anonymous"
      img.onload = () => resolve(img)
      img.onerror = reject
      img.src = url
    })
  }
}
