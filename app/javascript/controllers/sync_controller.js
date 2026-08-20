import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    orgId: Number,
    url: String,
    statusUrl: String,
    interval: { type: Number, default: 1500 },
    badgeId: { type: String, default: "sync-badge" },
    modalId: { type: String, default: "asc-add-cred-modal" },
    autoReload: { type: Boolean, default: true }
  }

  static targets = ["button"]

  connect() {
    // If a sync is already running when the page loads (user refreshed mid-sync,
    // or another tab kicked one off), show the in-progress state and resume
    // polling so the user never stares at a silent button.
    if (!this.hasStatusUrlValue) return
    this._resumeIfRunning()
  }

  disconnect() {
    this._stopPolling()
  }

  async _resumeIfRunning() {
    try {
      const res = await fetch(this.statusUrlValue, {
        headers: { Accept: "application/json" }, credentials: "same-origin"
      })
      if (!res.ok) return
      const data = await res.json()
      if (data.running) {
        this._setButtonSyncing()
        this._navBadge(true)
        this._startPolling()
      }
    } catch (e) { /* silent */ }
  }

  async start(event) {
    event.preventDefault()
    this._setButtonSyncing()
    try {
      this._navBadge(true)
      const res = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": this._csrf() },
        credentials: "same-origin"
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      this._toast("Sync enqueued", true, { syncTag: "enqueued" })
      this._startPolling()
      // NOTE: don't reset the button here — polling owns the button state until
      // completion, failure, or timeout. This is the whole point: the user sees
      // a persistent "Syncing…" spinner the entire time, so they always know
      // the current state.
    } catch (e) {
      this._toast("Failed to enqueue sync. Please try again.", false, { syncTag: "failed" })
      this._resetButton()
      this._navBadge(false, "error")
    }
  }

  _setButtonSyncing() {
    const btn = this.buttonTarget || this.element
    if (this._originalButtonHtml == null) this._originalButtonHtml = btn.innerHTML
    btn.disabled = true
    btn.classList.add("btn-disabled")
    btn.innerHTML = `<span class="loading loading-spinner loading-xs mr-2"></span>Syncing…`
  }

  _resetButton() {
    const btn = this.buttonTarget || this.element
    btn.disabled = false
    btn.classList.remove("btn-disabled")
    if (this._originalButtonHtml != null) {
      btn.innerHTML = this._originalButtonHtml
      this._originalButtonHtml = null
    }
  }

  _csrf() {
    const tag = document.querySelector('meta[name="csrf-token"]')
    return tag && tag.content
  }

  _toast(message, ok, options = {}) {
    const container = document.getElementById("toast-container")
    if (!container) return
    // When a sync toast is tagged (enqueued / completed / failed), remove any
    // previously-issued sync toast first so we never stack two at once.
    if (options.syncTag) {
      container.querySelectorAll("[data-sync-toast]").forEach(el => el.remove())
    }
    const div = document.createElement("div")
    div.className = `alert ${ok ? "alert-success" : "alert-error"} shadow-lg max-w-sm`
    if (options.syncTag) div.setAttribute("data-sync-toast", options.syncTag)
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-toast-type-value", ok ? "success" : "error")
    div.setAttribute("data-action", "mouseenter->toast#mouseenter mouseleave->toast#mouseleave")

    // Construct via DOM APIs (textContent everywhere) so a future caller
    // that passes a server-derived string can't inject markup. Mirrors
    // the safe-DOM approach in `_toastWithLink`. All current callers
    // pass static strings, so this is defense-in-depth, not a fix for
    // an exploitable hole today.
    const icon = document.createElement("i")
    icon.className = `fa-solid ${ok ? "fa-circle-check" : "fa-circle-exclamation"}`
    div.appendChild(icon)

    const messageSpan = document.createElement("span")
    messageSpan.className = "flex-1"
    messageSpan.textContent = message
    div.appendChild(messageSpan)

    const closeBtn = document.createElement("button")
    closeBtn.className = "btn btn-sm btn-ghost ml-2"
    closeBtn.setAttribute("data-action", "click->toast#close")
    const closeIcon = document.createElement("i")
    closeIcon.className = "fa-solid fa-xmark"
    closeBtn.appendChild(closeIcon)
    div.appendChild(closeBtn)

    container.appendChild(div)
  }

  // Builds the partial/failure toast via safe DOM APIs (no innerHTML on
  // user-derived strings). `message` and `linkText` are appended via
  // textContent so the third-party error messages bubbled up by
  // status_aggregator can't inject markup or scripts into the page.
  _toastWithLink(message, linkText, linkUrl, syncTag = "partial") {
    const container = document.getElementById("toast-container")
    if (!container) return
    // Clear any prior sync toasts so partial-failure doesn't stack on top of
    // the earlier "Sync enqueued".
    container.querySelectorAll("[data-sync-toast]").forEach(el => el.remove())

    const div = document.createElement("div")
    div.className = "alert bg-base-100 border border-base-300 shadow-xl max-w-md"
    div.setAttribute("data-sync-toast", syncTag)
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-toast-type-value", "warning")
    div.setAttribute("data-toast-timeout-value", "20000") // 20s for warnings
    div.setAttribute("data-action", "mouseenter->toast#mouseenter mouseleave->toast#mouseleave")

    const icon = document.createElement("i")
    icon.className = "fa-solid fa-triangle-exclamation text-warning"
    div.appendChild(icon)

    const messageSpan = document.createElement("span")
    messageSpan.className = "flex-1"
    messageSpan.textContent = message
    div.appendChild(messageSpan)

    const link = document.createElement("a")
    link.href = linkUrl
    link.className = "btn btn-sm btn-primary gap-1"
    link.setAttribute("data-turbo-frame", "_top")
    link.textContent = linkText
    const linkIcon = document.createElement("i")
    linkIcon.className = "fa-solid fa-arrow-right text-xs"
    link.appendChild(linkIcon)
    div.appendChild(link)

    const closeBtn = document.createElement("button")
    closeBtn.className = "btn btn-sm btn-circle btn-ghost"
    closeBtn.setAttribute("data-action", "click->toast#close")
    const closeIcon = document.createElement("i")
    closeIcon.className = "fa-solid fa-xmark"
    closeBtn.appendChild(closeIcon)
    div.appendChild(closeBtn)

    container.appendChild(div)
  }

  // Authenticated dashboard URL with an anchor to the sync-error-alerts
  // section in app/views/home/index.html.erb. Replaces the prior
  // `_androidAppsUrl()` helper which:
  //   1) extracted the org ID by regex from window.location.pathname,
  //      which fails silently when the user triggers sync from `/`
  //      (the most common case via the navbar button) — the fallback
  //      was `window.location.href`, so clicking "See details" looked
  //      like a complete no-op (just refreshing the same page);
  //   2) was hardcoded to `/android_apps` even when the partial failure
  //      was iOS-only.
  // The home dashboard already renders distinct iOS / Android failure
  // cards with the actual error message — that's the page the user
  // wants to land on when chasing "what failed".
  _dashboardUrl() {
    return "/#sync-error-alerts"
  }

  // Builds a human-readable summary of which jobs failed for the toast,
  // pulled from `data.jobs` in the polling response. Falls back to a
  // generic message when the structured field is missing.
  _failureSummary(data) {
    const labels = {
      asc: "App Store Connect",
      google_play: "Google Play",
      reviews: "Reviews",
      analytics: "Analytics",
      cpp: "Custom product pages",
      keywords_rank: "Keyword rankings",
      keywords_popularity: "Keyword popularity"
    }
    const failed = []
    const seenLabels = new Set()
    for (const [name, job] of Object.entries(data?.jobs || {})) {
      if (job?.status !== "error") continue
      const label = labels[name] || name
      if (seenLabels.has(label)) continue
      seenLabels.add(label)
      failed.push(label)
    }
    if (failed.length === 0) return null

    const list = failed.length === 1
      ? failed[0]
      : `${failed.slice(0, -1).join(", ")} and ${failed[failed.length - 1]}`
    return `Sync failed for ${list}`
  }

  _startPolling() {
    if (!this.hasStatusUrlValue) return
    this._stopPolling()
    this._completionFired = false
    this._pollFailureCount = 0
    this._pollStartTime = Date.now()
    const MAX_POLL_DURATION_MS = 10 * 60 * 1000 // 10 min
    const MAX_CONSECUTIVE_FAILURES = 5          // ~7.5s of blind retries before giving up

    this._timer = setInterval(async () => {
      // Hard timeout — surface to user instead of polling forever
      if (Date.now() - this._pollStartTime > MAX_POLL_DURATION_MS) {
        this._stopPolling()
        this._resetButton()
        this._navBadge(false, "partial")
        this._toast("Sync is taking longer than expected. Refresh the page to check status.", false, { syncTag: "timeout" })
        return
      }

      let data
      try {
        const res = await fetch(this.statusUrlValue, {
          headers: { Accept: "application/json" }, credentials: "same-origin"
        })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        data = await res.json()
        this._pollFailureCount = 0
      } catch (e) {
        this._pollFailureCount++
        if (this._pollFailureCount >= MAX_CONSECUTIVE_FAILURES) {
          this._stopPolling()
          this._resetButton()
          this._navBadge(false, "error")
          this._toast("Lost connection while syncing. Please refresh to see the result.", false, { syncTag: "failed" })
        }
        return
      }

      if (data.running) return  // still running, keep polling

      // Completion — guard against overlapping ticks
      if (this._completionFired) return
      this._completionFired = true
      this._stopPolling()
      this._resetButton()
      this._navBadge(false, data.last_sync_status)

      const status = data.last_sync_status
      if (status === "ok") {
        this._toast("Sync completed", true, { syncTag: "completed" })
        if (this.autoReloadValue) {
          setTimeout(() => this._reload(), 800)
        }
      } else if (status === "partial") {
        const summary = this._failureSummary(data) || "Some jobs failed to sync"
        this._toastWithLink(summary, "See details", this._dashboardUrl(), "partial")
      } else {
        // Full failure (status === "error" or anything else non-ok). The
        // earlier copy was "Check the dashboard for details" with no link
        // -- which left the user to manually find the dashboard. Now we
        // surface the same See-details affordance and a per-job summary
        // when the polling endpoint provides one.
        const summary = this._failureSummary(data) || "Sync failed"
        this._toastWithLink(summary, "See details", this._dashboardUrl(), "failed")
        if (this.autoReloadValue) {
          setTimeout(() => this._reload(), 2000)
        }
      }
    }, this.intervalValue)
  }

  _stopPolling() {
    if (this._timer) {
      clearInterval(this._timer)
      this._timer = null
    }
  }

  _reload() {
    if (window.Turbo) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    } else {
      window.location.reload()
    }
  }

  _navBadge(running, status) {
    const container = document.getElementById(this.badgeIdValue)
    if (!container) return
    const icon = container.querySelector("i")
    const label = container.querySelector("span[data-label]")

    container.classList.remove("hidden", "badge-success", "badge-error", "badge-info", "badge-warning")

    if (running) {
      container.classList.add("badge-info")
      if (icon) icon.className = "fa-solid fa-spinner fa-spin mr-1"
      if (label) {
        label.textContent = "Syncing…"
        label.dataset.label = "syncing"
      }
      container.classList.add("animate-pulse")
    } else {
      container.classList.remove("animate-pulse")
      if (status === "ok") {
        container.classList.add("badge-success")
        if (icon) icon.className = "fa-solid fa-check mr-1"
        if (label) {
          label.textContent = "Synced"
          label.dataset.label = "success"
        }
      } else if (status === "partial") {
        container.classList.add("badge-warning")
        if (icon) icon.className = "fa-solid fa-exclamation mr-1"
        if (label) {
          label.textContent = "Partial"
          label.dataset.label = "partial"
        }
      } else {
        container.classList.add("badge-error")
        if (icon) icon.className = "fa-solid fa-xmark mr-1"
        if (label) {
          label.textContent = "Failed"
          label.dataset.label = "error"
        }
      }
      setTimeout(() => container.classList.add("hidden"), 3500)
    }
  }

  openCredentialsModal(event) {
    event.preventDefault()
    const modal = document.getElementById(this.modalIdValue)
    if (modal && typeof modal.showModal === "function") {
      modal.showModal()
    }
  }
}


