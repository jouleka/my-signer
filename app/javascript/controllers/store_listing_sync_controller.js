import { Controller } from "@hotwired/stimulus"
import { showConfirmDialog } from "controllers/confirm_dialog_controller"

// Handles sync/push actions for store listings with polling-based auto-refresh.
export default class extends Controller {
  static values = {
    syncUrl: String,
    statusUrl: String,
    interval: { type: Number, default: 2000 }
  }

  sync(event) {
    event.preventDefault()
    const btn = event.currentTarget
    const url = btn.dataset.url || this.syncUrlValue
    if (!url) return
    this._disableButton(btn)
    this._activeOperation = "sync"
    this._showSyncBanner()
    this._postAction(url, btn)
  }

  async push(event) {
    event.preventDefault()
    const form = event.currentTarget
    const btn = event.submitter || form.querySelector('button[type="submit"]')
    const confirmed = await showConfirmDialog({
      title: "Push changes", message: btn.dataset.turboConfirm,
      confirmText: "Push", variant: "info"
    })
    if (!confirmed) return
    this._disableButton(btn)
    this._activeOperation = "push"
    this._showPushBanner()
    this._postAction(form.action, btn)
  }

  async _postAction(url, btn) {
    this._activeButton = btn
    for (const identifier of ["store-listing-editor", "locale-switcher"]) {
      const element = this.element.querySelector(`[data-controller~="${identifier}"]`)
      const editor = element && this.application.getControllerForElementAndIdentifier(element, identifier)
      if (editor && !await editor.flushSave()) {
        this._enableButton(btn)
        this._clearStatus()
        return
      }
    }
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this._csrf()
        },
        credentials: "same-origin"
      })

      if (!res.ok || res.redirected) {
        let msg = `HTTP ${res.status}`
        try { const d = await res.json(); if (d.error) msg = d.error } catch {}
        throw new Error(msg)
      }

      const result = await res.json()
      this._operationId = result.operation?.id
      this._startPolling()
    } catch (e) {
      this._enableButton(btn)
      this._showPushResult("error", "Action failed", e.message, 0)
    }
  }

  _startPolling() {
    if (!this.hasStatusUrlValue) return
    if (this._timer) clearInterval(this._timer)

    const operation = this._activeOperation

    this._timer = setInterval(async () => {
      try {
        const res = await fetch(this.statusUrlValue, {
          headers: { Accept: "application/json" },
          credentials: "same-origin"
        })
        if (!res.ok) return
        const data = await res.json()

        if (operation === "push") {
          if (data.push_status === "success" || data.push_status === "partial_success") {
            this._stopPolling()
            this._handlePushSuccess(data)
          } else if (data.push_status === "failed") {
            this._stopPolling()
            this._handlePushFailure(data)
          }
        } else if (operation === "submit") {
          if (data.submission_status === "submitted") {
            this._stopPolling()
            this._handleSubmitSuccess(data)
          } else if (data.submission_status === "failed") {
            this._stopPolling()
            this._handleSubmitFailure(data)
          }
        } else {
          const sync = data.sync_operation
          if (sync?.id !== this._operationId) return
          if (sync.status === "completed") {
            this._stopPolling()
            this._showToast("Sync completed", true)
            this._reloadPage()
          } else if (sync.status === "failed") {
            this._stopPolling()
            this._showPushResult("error", "Sync failed", sync.error || "Please try again.", 0)
          }
        }
      } catch (e) {
        // ignore polling errors
      }
    }, this.intervalValue)

    this._timeout = setTimeout(() => {
      if (this._timer) {
        this._stopPolling()
        this._clearStatus()
        this._showToast("Operation is taking longer than expected. Refresh to check.", false)
      }
    }, 120000)
  }

  _stopPolling() {
    if (this._timer) {
      clearInterval(this._timer)
      this._timer = null
    }
    this._enableButton(this._activeButton)
    if (this._timeout) {
      clearTimeout(this._timeout)
      this._timeout = null
    }
  }

  _handlePushSuccess(data) {
    this._reloadPage()
  }

  _handlePushFailure(data) {
    const error = data.push_error || "Unknown error occurred"
    this._showPushResult("error", "Push failed", error, 0)
  }

  // Submission lifecycle handlers — used when the Stimulus controller detects
  // [data-submission-active] on connect and starts polling for the transient
  // submission_status → "submitted" / "failed" transition. Reuses the same
  // SN_* banner constants as push so no new JS MIRROR is needed.

  _handleSubmitSuccess(data) {
    // Show a brief success banner, then reload so the submission tab renders
    // the new WAITING_FOR_REVIEW state.
    this._showPushResult("success", "Submitted for review", "Apple accepted the submission. Reloading…", 2500)
    setTimeout(() => this._reloadPage(), 2600)
  }

  _handleSubmitFailure(data) {
    const error = data.submission_error || "Submission failed for an unknown reason."
    this._showPushResult("error", "Submission failed", error, 0)
    // Reload after a short delay so the full error panel renders on the page
    // (the in-page banner is a preview; the submission tab has the detailed
    // error card which is easier to read).
    setTimeout(() => this._reloadPage(), 4000)
  }

  // Tailwind class strings used by the dynamically-built sync banners.
  // MUST MATCH the SN_* constants in app/helpers/ui_helper.rb. When you change
  // one side, update the other in the same commit.
  // Defined as constants on the controller so the strings appear once and
  // Tailwind's @source scanner picks them up.
  static SN_BASE = "relative rounded-[0.625rem] px-3 py-[0.625rem] border overflow-hidden"
  static SN_LOADING = "border-primary/[0.12] bg-primary/[0.04] animate-pulse"
  static SN_SUCCESS = "border-success/20 bg-success/[0.06]"
  static SN_WARNING = "border-warning/20 bg-warning/[0.06]"
  static SN_ERROR   = "border-error/20 bg-error/[0.06]"
  static SN_ICON_BASE    = "flex items-center justify-center w-5 h-5 rounded-full shrink-0"
  static SN_ICON_SUCCESS = "bg-success/15 text-success"
  static SN_ICON_WARNING = "bg-warning/15 text-warning"
  static SN_ICON_ERROR   = "bg-error/15 text-error"
  static SN_CLOSE = "flex items-center justify-center w-5 h-5 rounded text-base-content/30 hover:text-base-content/70 hover:bg-base-content/[0.06] transition-all text-[0.625rem] cursor-pointer"
  static SN_PROGRESS_BASE = "absolute bottom-0 left-0 h-[2px] w-full rounded-b-[0.625rem] origin-left animate-[sn-countdown_linear_forwards]"

  _showPushBanner() {
    const el = document.getElementById("sync-status")
    if (!el) return
    el.textContent = ""

    const wrapper = this._el("div", `${this.constructor.SN_BASE} ${this.constructor.SN_LOADING}`)
    wrapper.dataset.pushActive = "true"

    const flex = this._el("div", "flex items-center gap-3")
    const spinner = this._el("span", "loading loading-spinner loading-xs text-primary")
    const textCol = this._el("div")
    const title = this._el("span", "text-sm font-medium text-base-content/80")
    title.textContent = "Pushing changes to the store\u2026"
    const sub = this._el("p", "text-xs text-base-content/40 mt-0.5")
    sub.textContent = "This usually takes a few seconds."

    textCol.append(title, sub)
    flex.append(spinner, textCol)
    wrapper.appendChild(flex)
    el.appendChild(wrapper)
  }

  _showPushResult(type, titleText, detailText, timeout) {
    const el = document.getElementById("sync-status")
    if (!el) return
    el.textContent = ""

    const C = this.constructor
    const config = {
      success: { iconClass: C.SN_ICON_SUCCESS, icon: "fa-check", snClass: C.SN_SUCCESS, progressBg: "bg-success/35" },
      warning: { iconClass: C.SN_ICON_WARNING, icon: "fa-check", snClass: C.SN_WARNING, progressBg: "bg-warning/35" },
      error:   { iconClass: C.SN_ICON_ERROR,   icon: "fa-xmark", snClass: C.SN_ERROR,   progressBg: "bg-error/35" }
    }[type]

    const hasDetail = detailText && detailText.length > 0

    // Wrapper
    const wrapper = this._el("div", `${C.SN_BASE} ${config.snClass}`)
    wrapper.dataset.controller = "inline-notification"
    if (timeout > 0) {
      wrapper.dataset.inlineNotificationTimeoutValue = String(timeout)
      wrapper.dataset.action = "mouseenter->inline-notification#pause mouseleave->inline-notification#resume"
    }

    // Row
    const row = this._el("div", `flex ${hasDetail ? "items-start" : "items-center"} gap-3`)

    // Icon
    const iconWrap = this._el("div", `${C.SN_ICON_BASE} ${config.iconClass}${hasDetail ? " mt-0.5" : ""}`)
    const icon = this._el("i", `fa-solid ${config.icon} text-[0.625rem]`)
    iconWrap.appendChild(icon)

    // Content
    const content = this._el("div", "flex-1 min-w-0")
    const titleRow = this._el("div", "flex items-center gap-2")
    const titleEl = this._el("span", "text-sm font-semibold text-base-content/90")
    titleEl.textContent = titleText

    const closeBtn = this._el("button", `${C.SN_CLOSE} ml-auto`)
    closeBtn.setAttribute("aria-label", "Dismiss")
    closeBtn.dataset.action = "click->inline-notification#dismiss"
    const closeIcon = this._el("i", "fa-solid fa-xmark")
    closeBtn.appendChild(closeIcon)

    titleRow.append(titleEl, closeBtn)
    content.appendChild(titleRow)

    if (hasDetail) {
      const detail = this._el("p", "text-xs text-base-content/50 mt-1 leading-relaxed")
      detail.textContent = detailText
      content.appendChild(detail)
    }

    row.append(iconWrap, content)
    wrapper.appendChild(row)

    // Progress bar
    if (timeout > 0) {
      const progress = this._el("div", `${C.SN_PROGRESS_BASE} ${config.progressBg}`)
      progress.dataset.progressBar = ""
      progress.style.animationDuration = `${timeout}ms`
      wrapper.appendChild(progress)
    }

    el.appendChild(wrapper)
  }

  connect() {
    const syncActive = this.element.querySelector("[data-sync-active]")
    if (syncActive) {
      this._operationId = syncActive.dataset.syncActive
      this._activeOperation = "sync"
      this._startPolling()
      return
    }

    // If page loaded with push in progress, resume polling
    const pushActive = document.getElementById("sync-status")?.querySelector("[data-push-active]")
    if (pushActive) {
      this._activeOperation = "push"
      this._startPolling()
      return
    }

    // If page loaded with an iOS submission in progress, resume polling. The
    // submission tab renders [data-submission-active] when
    // AppStoreVersion#submitting? — this lets a user reload the page mid-
    // submission without losing the progress indicator.
    const submitActive = this.element.querySelector("[data-submission-active]")
    if (submitActive) {
      this._activeOperation = "submit"
      this._startPolling()
    }
  }

  disconnect() {
    this._stopPolling()
  }

  _showSyncBanner() {
    const el = document.getElementById("sync-status")
    if (!el) return
    el.textContent = ""

    const C = this.constructor
    const wrapper = this._el("div", `${C.SN_BASE} ${C.SN_LOADING}`)
    const flex = this._el("div", "flex items-center gap-3")
    const spinner = this._el("span", "loading loading-spinner loading-xs text-primary")
    const label = this._el("span", "text-sm text-base-content/70")
    label.textContent = "Syncing from store\u2026"

    flex.append(spinner, label)
    wrapper.appendChild(flex)
    el.appendChild(wrapper)
  }

  _clearStatus() {
    const el = document.getElementById("sync-status")
    if (el) el.textContent = ""
  }

  _reloadPage() {
    if (window.Turbo) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    } else {
      window.location.reload()
    }
  }

  _disableButton(btn) {
    if (!btn) return
    btn.disabled = true
    btn.classList.add("btn-disabled")
  }

  _enableButton(btn) {
    if (!btn) return
    btn.disabled = false
    btn.classList.remove("btn-disabled")
  }

  _showToast(message, ok) {
    const container = document.getElementById("toast-container")
    if (!container) return
    const div = document.createElement("div")
    div.className = `alert ${ok ? "alert-success" : "alert-error"} shadow-lg max-w-sm`
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-toast-type-value", ok ? "success" : "error")
    div.textContent = message
    container.appendChild(div)
  }

  /** Create an element with optional classes */
  _el(tag, classes) {
    const el = document.createElement(tag)
    if (classes) el.className = classes
    return el
  }

  _csrf() {
    const tag = document.querySelector('meta[name="csrf-token"]')
    return tag ? tag.content : ""
  }
}
