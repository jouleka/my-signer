import { Controller } from "@hotwired/stimulus"

// Manages the CPP Screenshots tab: fetches screenshot data from the server,
// renders a side-by-side comparison grid (default vs CPP), and handles uploads
// from Screenshot Studio projects.
export default class extends Controller {
  static targets = [
    "localeSelect", "screenshotGrid", "loadingIndicator", "emptyState",
    "errorState", "errorMessage",
    "projectSelect", "presetCheckbox", "replaceExistingCheckbox",
    "uploadProgress", "uploadSpinner", "uploadStatus", "uploadProgressBar",
    "uploadButton"
  ]

  static values = {
    fetchUrl: String,
    uploadUrl: String,
    uploadStatusUrl: String,
    organizationId: Number,
    cppId: Number
  }

  connect() {
    this.pollingInterval = null
    if (this.fetchUrlValue) {
      this.fetchScreenshots()
    }
  }

  disconnect() {
    this.stopPolling()
  }

  changeLocale() {
    this.fetchScreenshots()
  }

  refreshScreenshots() {
    this.fetchScreenshots()
  }

  async fetchScreenshots() {
    if (!this.fetchUrlValue) return

    // Show loading, hide others
    this.showLoading()

    const locale = this.hasLocaleSelectTarget ? this.localeSelectTarget.value : null
    const params = new URLSearchParams()
    if (locale) params.set("locale", locale)

    try {
      const response = await fetch(`${this.fetchUrlValue}?${params}`, {
        headers: { "Accept": "application/json" }
      })

      if (!response.ok) {
        const err = await response.json().catch(() => ({}))
        throw new Error(err.message || `HTTP ${response.status}`)
      }

      const result = await response.json()
      this.renderComparison(result.data || {})
    } catch (error) {
      this.showError(error.message || "Failed to load screenshots")
    }
  }

  renderComparison(data) {
    const defaultGroups = data.default_screenshots || []
    const cppGroups = data.cpp_screenshots || []

    if (defaultGroups.length === 0 && cppGroups.length === 0) {
      this.showEmpty()
      return
    }

    // Flatten groups into { display_type -> screenshots[] } maps
    const defaultByType = this.flattenGroups(defaultGroups)
    const cppByType = this.flattenGroups(cppGroups)

    const allTypes = new Set()
    Object.keys(defaultByType).forEach(k => allTypes.add(k))
    Object.keys(cppByType).forEach(k => allTypes.add(k))

    const grid = this.screenshotGridTarget
    // Clear previous content
    while (grid.firstChild) grid.removeChild(grid.firstChild)

    const sortedTypes = Array.from(allTypes).sort()

    sortedTypes.forEach(displayType => {
      const defaultItems = defaultByType[displayType] || []
      const cppItems = cppByType[displayType] || []

      const section = document.createElement("div")
      section.className = "border border-base-content/[0.06] rounded-lg overflow-hidden"

      // Header
      const header = document.createElement("div")
      header.className = "flex items-center gap-2 px-4 py-2.5 border-b border-base-content/[0.04] bg-base-content/[0.02]"

      const icon = document.createElement("i")
      icon.className = `fa-solid ${this.deviceIcon(displayType)} text-xs text-base-content/40`
      header.appendChild(icon)

      const label = document.createElement("span")
      label.className = "text-xs font-semibold text-base-content/70 flex-1"
      label.textContent = this.formatDisplayType(displayType)
      header.appendChild(label)

      const counts = document.createElement("span")
      counts.className = "text-[0.625rem] font-medium text-base-content/40 bg-base-content/[0.05] px-1.5 py-0.5 rounded-full"
      counts.textContent = `${defaultItems.length} / ${cppItems.length}`
      header.appendChild(counts)

      section.appendChild(header)

      // Two-column comparison
      const columns = document.createElement("div")
      columns.className = "grid grid-cols-2 gap-px bg-base-content/[0.04]"

      columns.appendChild(this.buildColumn("Default Product Page", defaultItems))
      columns.appendChild(this.buildColumn("Custom Product Page", cppItems))

      section.appendChild(columns)
      grid.appendChild(section)
    })

    this.hideLoading()
    this.screenshotGridTarget.classList.remove("hidden")
  }

  buildColumn(title, screenshots) {
    const col = document.createElement("div")
    col.className = "bg-base-100 p-4"

    const heading = document.createElement("div")
    heading.className = "text-[0.6875rem] font-semibold uppercase tracking-[0.06em] text-base-content/35 mb-3"
    heading.textContent = title
    col.appendChild(heading)

    if (screenshots.length === 0) {
      const empty = document.createElement("div")
      empty.className = "flex items-center gap-1.5 text-[0.8125rem] text-base-content/30 italic py-4"

      const emptyIcon = document.createElement("i")
      emptyIcon.className = "fa-regular fa-image text-xs"
      empty.appendChild(emptyIcon)

      const emptyText = document.createElement("span")
      emptyText.textContent = "No screenshots"
      empty.appendChild(emptyText)

      col.appendChild(empty)
      return col
    }

    const strip = document.createElement("div")
    strip.className = "flex gap-2 overflow-x-auto scroll-smooth snap-x pb-1"

    screenshots.forEach(ss => {
      const card = document.createElement("div")
      card.className = "shrink-0 snap-start group/thumb"

      if (ss.url) {
        const img = document.createElement("img")
        img.src = this.thumbnailUrl(ss.url, 230, ss.width, ss.height)
        img.className = "h-32 w-auto rounded-md border border-base-content/[0.06] bg-base-100 object-contain shadow-sm cursor-pointer transition-transform duration-150 group-hover/thumb:scale-[1.03]"
        img.loading = "lazy"
        img.alt = ss.file_name || "Screenshot"

        const meta = [ss.file_name, ss.width && ss.height ? `${ss.width}x${ss.height}` : null].filter(Boolean)
        img.title = meta.join(" \u2014 ")

        card.appendChild(img)
      } else {
        const placeholder = document.createElement("div")
        placeholder.className = "h-32 w-[4.5rem] rounded-md border border-base-content/[0.06] bg-base-content/[0.03] flex items-center justify-center"
        const phIcon = document.createElement("i")
        phIcon.className = "fa-regular fa-image text-base-content/20 text-sm"
        placeholder.appendChild(phIcon)
        card.appendChild(placeholder)
      }

      strip.appendChild(card)
    })

    col.appendChild(strip)
    return col
  }

  // --- Upload from Screenshot Studio project ---

  async startUpload() {
    if (!this.hasProjectSelectTarget) return

    const projectId = this.projectSelectTarget.value
    if (!projectId) {
      this.showUploadError("Please select a Screenshot Studio project.")
      return
    }

    const locale = this.hasLocaleSelectTarget ? this.localeSelectTarget.value : "en-US"
    const presets = this.presetCheckboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.dataset.preset)

    if (presets.length === 0) {
      this.showUploadError("Please select at least one screenshot size.")
      return
    }

    const replaceExisting = this.hasReplaceExistingCheckboxTarget
      ? this.replaceExistingCheckboxTarget.checked
      : true

    // Show progress
    this.showUploadProgress("Starting upload...")
    if (this.hasUploadButtonTarget) this.uploadButtonTarget.disabled = true

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.uploadUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({
          project_id: projectId,
          locale: locale,
          presets: presets,
          replace_existing: replaceExisting
        })
      })

      if (!response.ok) {
        const err = await response.json().catch(() => ({}))
        throw new Error(err.error || err.message || `Upload failed (HTTP ${response.status})`)
      }

      const result = await response.json()
      const uploadId = result.data?.id

      if (uploadId) {
        this.pollUploadStatus(uploadId)
      } else {
        this.showUploadSuccess("Upload queued successfully.")
      }
    } catch (error) {
      this.showUploadError(error.message || "Upload failed")
      if (this.hasUploadButtonTarget) this.uploadButtonTarget.disabled = false
    }
  }

  pollUploadStatus(uploadId) {
    this.pollingInterval = setInterval(async () => {
      try {
        const params = new URLSearchParams({ upload_id: uploadId })
        const response = await fetch(`${this.uploadStatusUrlValue}?${params}`, {
          headers: { "Accept": "application/json" }
        })
        if (!response.ok) return

        const result = await response.json()
        const upload = result.data || {}
        const progress = upload.progress || {}

        if (upload.status === "in_progress") {
          const completed = progress.completed || 0
          const total = progress.total || 1
          const pct = Math.round((completed / total) * 100)
          this.showUploadProgress(`Uploading... ${completed}/${total}`, pct)
        } else if (upload.status === "completed") {
          this.stopPolling()
          this.showUploadSuccess("Upload completed successfully!")
          if (this.hasUploadButtonTarget) this.uploadButtonTarget.disabled = false
          // Refresh the comparison grid
          this.fetchScreenshots()
        } else if (upload.status === "failed") {
          this.stopPolling()
          const errors = (progress.errors || []).join(", ")
          this.showUploadError(`Upload failed: ${errors}`)
          if (this.hasUploadButtonTarget) this.uploadButtonTarget.disabled = false
        }
      } catch (error) {
        console.error("CPP upload polling error:", error)
      }
    }, 3000)
  }

  stopPolling() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
      this.pollingInterval = null
    }
  }

  // --- Display helpers ---

  showLoading() {
    if (this.hasLoadingIndicatorTarget) this.loadingIndicatorTarget.classList.remove("hidden")
    if (this.hasScreenshotGridTarget) this.screenshotGridTarget.classList.add("hidden")
    if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.add("hidden")
    if (this.hasErrorStateTarget) this.errorStateTarget.classList.add("hidden")
  }

  hideLoading() {
    if (this.hasLoadingIndicatorTarget) this.loadingIndicatorTarget.classList.add("hidden")
  }

  showEmpty() {
    this.hideLoading()
    if (this.hasScreenshotGridTarget) this.screenshotGridTarget.classList.add("hidden")
    if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.remove("hidden")
    if (this.hasErrorStateTarget) this.errorStateTarget.classList.add("hidden")
  }

  showError(message) {
    this.hideLoading()
    if (this.hasScreenshotGridTarget) this.screenshotGridTarget.classList.add("hidden")
    if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.add("hidden")
    if (this.hasErrorStateTarget) this.errorStateTarget.classList.remove("hidden")
    if (this.hasErrorMessageTarget) this.errorMessageTarget.textContent = message
  }

  showUploadProgress(message, pct) {
    if (this.hasUploadProgressTarget) this.uploadProgressTarget.classList.remove("hidden")
    if (this.hasUploadStatusTarget) this.uploadStatusTarget.textContent = message
    if (this.hasUploadProgressBarTarget && pct !== undefined) {
      this.uploadProgressBarTarget.value = pct
    }
  }

  showUploadSuccess(message) {
    if (this.hasUploadStatusTarget) this.uploadStatusTarget.textContent = message
    if (this.hasUploadSpinnerTarget) this.uploadSpinnerTarget.classList.add("hidden")
    // Auto-hide progress after 3 seconds
    setTimeout(() => {
      if (this.hasUploadProgressTarget) this.uploadProgressTarget.classList.add("hidden")
      if (this.hasUploadSpinnerTarget) this.uploadSpinnerTarget.classList.remove("hidden")
    }, 3000)
  }

  showUploadError(message) {
    // Hide spinner and progress bar — only show the error text
    if (this.hasUploadSpinnerTarget) this.uploadSpinnerTarget.classList.add("hidden")
    if (this.hasUploadProgressBarTarget) this.uploadProgressBarTarget.classList.add("hidden")
    if (this.hasUploadProgressTarget) this.uploadProgressTarget.classList.remove("hidden")
    if (this.hasUploadStatusTarget) {
      this.uploadStatusTarget.textContent = message
      this.uploadStatusTarget.classList.add("text-error")
    }
    if (this.hasUploadButtonTarget) this.uploadButtonTarget.disabled = false
    setTimeout(() => {
      if (this.hasUploadProgressTarget) this.uploadProgressTarget.classList.add("hidden")
      if (this.hasUploadStatusTarget) this.uploadStatusTarget.classList.remove("text-error")
      if (this.hasUploadSpinnerTarget) this.uploadSpinnerTarget.classList.remove("hidden")
      if (this.hasUploadProgressBarTarget) this.uploadProgressBarTarget.classList.remove("hidden")
    }, 5000)
  }

  // --- Utility ---

  // Flattens the grouped API response (array of { display_type, screenshots[] })
  // into a flat map of display_type -> screenshots[].
  flattenGroups(groups) {
    const byType = {}
    groups.forEach(group => {
      const key = group.display_type || "unknown"
      if (!byType[key]) byType[key] = []
      ;(group.screenshots || []).forEach(ss => byType[key].push(ss))
    })
    return byType
  }

  thumbnailUrl(url, width, imgWidth, imgHeight) {
    if (!url) return url
    // Apple requires real values for BOTH {w} and {h} — passing 0 causes a 400.
    // Match the pattern from store_listing_sync/apple_importer.rb:101
    const tw = Math.min(imgWidth || 230, width)
    const th = imgWidth ? Math.round(tw / imgWidth * (imgHeight || 500)) : 500
    return url
      .replace(/\{w\}/g, String(tw))
      .replace(/\{h\}/g, String(th))
      .replace(/\{f\}/g, "png")
      .replace(/\{c\}/g, "fa")
  }

  formatDisplayType(type) {
    const map = {
      "APP_IPHONE_67": "iPhone 6.7\"/6.9\"",
      "APP_IPHONE_65": "iPhone 6.5\"",
      "APP_IPHONE_55": "iPhone 5.5\"",
      "APP_IPAD_PRO_3GEN_129": "iPad Pro 12.9\"",
      "APP_IPAD_PRO_3GEN_11": "iPad Pro 11\""
    }
    return map[type] || type.replace(/([A-Z])/g, " $1").replace(/_/g, " ").trim()
  }

  deviceIcon(type) {
    if (type.includes("IPAD")) return "fa-tablet-screen-button"
    return "fa-mobile-screen-button"
  }
}
