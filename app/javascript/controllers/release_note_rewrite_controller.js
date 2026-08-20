import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "rawInput",
    "submitBtn",
    "statusArea",
    "form",
    "githubRepoUrl",
    "githubFromRef",
    "githubToRef",
    "fetchBtn",
    "fetchStatus"
  ]
  static values = { url: String, fetchUrl: String }

  submit(event) {
    // Show loading state; let the form submit normally via Turbo
    if (!this.hasSubmitBtnTarget) return

    const btn = this.submitBtnTarget
    btn.disabled = true
    btn.classList.add("btn-disabled")

    // Store original content for potential restore
    this._originalNodes = Array.from(btn.childNodes).map(n => n.cloneNode(true))
    btn.textContent = ""

    const spinner = document.createElement("span")
    spinner.className = "loading loading-spinner loading-xs"
    btn.appendChild(spinner)
    btn.appendChild(document.createTextNode(" Rewriting..."))

    if (this.hasStatusAreaTarget) {
      this.statusAreaTarget.textContent = ""
      const statusWrap = document.createElement("div")
      statusWrap.className = "flex items-center gap-2 text-xs text-base-content/50 mt-2"

      const statusSpinner = document.createElement("span")
      statusSpinner.className = "loading loading-spinner loading-xs"

      const statusText = document.createTextNode("AI is rewriting your release notes...")

      statusWrap.append(statusSpinner, statusText)
      this.statusAreaTarget.appendChild(statusWrap)
    }
  }

  restore() {
    if (!this.hasSubmitBtnTarget || !this._originalNodes) return
    this.submitBtnTarget.disabled = false
    this.submitBtnTarget.classList.remove("btn-disabled")
    this.submitBtnTarget.textContent = ""
    this._originalNodes.forEach(n => this.submitBtnTarget.appendChild(n))

    if (this.hasStatusAreaTarget) {
      this.statusAreaTarget.textContent = ""
    }
  }

  // Fired after Turbo finishes the form submission. On success the controller's
  // turbo_stream response has already swapped the AI Rewrite button for a
  // "Rewriting…" pill; we just need to close the modal and reset state so the
  // next open is clean. On failure, restore the submit button.
  handleSubmitEnd(event) {
    const success = event?.detail?.success
    if (success) {
      const dialog = this.element.closest("dialog")
      if (dialog && dialog.open) dialog.close()
      if (this.hasFormTarget) this.formTarget.reset()
    }
    this.restore()
  }

  async fetchFromGit(event) {
    event.preventDefault()

    const repoUrl = this.githubRepoUrlTarget.value.trim()
    const fromRef = this.githubFromRefTarget.value.trim()
    const toRef = this.githubToRefTarget.value.trim()

    if (!repoUrl || !fromRef || !toRef) {
      this._showStatus("Please fill all three fields.", "error")
      return
    }

    this._setLoadingState(true)
    this._showStatus("Fetching commits from GitHub...", "info")

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await fetch(this.fetchUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": token
        },
        body: JSON.stringify({ repo_url: repoUrl, from_ref: fromRef, to_ref: toRef })
      })

      const data = await response.json()

      if (!response.ok) {
        this._showStatus(data.error || "Failed to fetch commits.", "error")
        return
      }

      if (data.commits) {
        this.rawInputTarget.value = data.commits
        this.rawInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
        this._showStatus("Commits loaded! Review and click 'Rewrite with AI' to continue.", "success")
      } else {
        this._showStatus(data.message || "No commits found.", "warning")
      }
    } catch (error) {
      this._showStatus("Network error: " + error.message, "error")
    } finally {
      this._setLoadingState(false)
    }
  }

  _setLoadingState(loading) {
    if (!this.hasFetchBtnTarget) return
    this.fetchBtnTarget.disabled = loading
    this.fetchBtnTarget.textContent = loading ? "Fetching..." : "Fetch commits"
  }

  _showStatus(message, level) {
    if (!this.hasFetchStatusTarget) return
    this.fetchStatusTarget.textContent = message
    this.fetchStatusTarget.classList.remove("hidden", "text-error", "text-warning", "text-success", "text-info")
    const cls = { error: "text-error", warning: "text-warning", success: "text-success", info: "text-info" }[level]
    if (cls) this.fetchStatusTarget.classList.add(cls)
  }
}
