import { Controller } from "@hotwired/stimulus"

// JS MIRROR — must stay in sync with UiHelper. Update both on change.
// KW_TAG mirrors UiHelper::KW_TAG (editor-tab display tags).
// KW_CHIP_AVAILABLE / KW_CHIP_STAGED / KW_CHIP_TOO_LONG mirror UiHelper's
// KW_CHIP_* constants (suggestion chip states).
// KW_TAG_DISABLED is JS-only (the "already in use" chip has no Ruby equivalent
// because the server never renders an already-used chip).
const KW_TAG             = "inline-flex items-center gap-1 text-xs font-medium px-2 py-[0.25rem] rounded-md bg-primary/[0.08] text-primary/80 border border-primary/[0.1]"
const KW_TAG_DISABLED    = "inline-flex items-center gap-1 text-xs font-medium px-2 py-[0.25rem] rounded-md bg-base-content/[0.04] text-base-content/30 border border-base-content/[0.06] cursor-not-allowed"
const KW_CHIP_AVAILABLE  = "inline-flex items-center gap-1 text-xs font-medium px-2 py-[0.25rem] rounded-md bg-primary/[0.08] text-primary/80 border border-primary/[0.1] cursor-pointer hover:bg-primary/[0.15] transition-colors"
const KW_CHIP_STAGED     = "inline-flex items-center gap-1 text-xs font-medium px-2 py-[0.25rem] rounded-md bg-success/[0.12] text-success/90 border border-success/30 cursor-pointer"
const KW_CHIP_TOO_LONG   = "inline-flex items-center gap-1 text-xs font-medium px-2 py-[0.25rem] rounded-md bg-base-content/[0.02] text-base-content/35 border border-dashed border-base-content/[0.12] cursor-not-allowed"

const POPULARITY_PIP_FILLED   = "inline-block w-1 h-1 rounded-full bg-success/70"
const POPULARITY_PIP_MEDIUM   = "inline-block w-1 h-1 rounded-full bg-warning/70"
const POPULARITY_PIP_EMPTY    = "inline-block w-1 h-1 rounded-full bg-base-content/15"

const KEYWORD_LIMIT = 100

export default class extends Controller {
  static targets = [
    "suggestionsInput", "suggestionsContainer", "appName", "subtitle",
    "keywordsDisplay", "trackedList", "budgetCurrent", "budgetStaged",
    "budgetFree", "budgetProgress", "basketZone", "basketCount", "basketDelta",
    "recentSearches"
  ]

  static values = {
    suggestionsUrl:       String,
    keywordsStr:          String,
    country:              { type: String, default: "us" },
    limit:                { type: Number, default: KEYWORD_LIMIT },
    appId:                Number,
    locale:               String,
    popularityMap:        Object,
    appleAdsConnected:    Boolean,
    saveIdeaUrl:          String
  }

  connect() {
    this.debounceTimer = null
    this.basket = []
    this.restoreBasket()
    this.renderKeywordTags()
    this.renderBudgetBar()
    this.renderBasketZone()
    this.renderRecent()

    // Listen for successful commits dispatched from the Turbo Stream response.
    // Cleans up basket state, closes the modal, and refreshes keywordsStrValue
    // so chip-state math is accurate for subsequent interactions.
    this.boundCommitted = (e) => this.onCommitted(e)
    document.addEventListener("keyword-editor:committed", this.boundCommitted)
  }

  disconnect() {
    if (this.boundCommitted) {
      document.removeEventListener("keyword-editor:committed", this.boundCommitted)
    }
  }

  onCommitted(event) {
    // Clear basket state
    this.basket = []
    this.persistBasket()
    // Refresh the known current keywords so fits()/already-in-use math is accurate
    if (event.detail && typeof event.detail.keywords === "string") {
      this.keywordsStrValue = event.detail.keywords
    }
    // Close the commit modal
    const dialog = document.getElementById("commit-basket-modal")
    if (dialog && dialog.open && typeof dialog.close === "function") dialog.close()
    // Re-render everything that depends on basket/keywords state
    this.renderBudgetBar()
    this.renderBasketZone()
    this.renderKeywordTags()
    // If a search is active, re-run it so chip states update
    const term = this.hasSuggestionsInputTarget ? (this.suggestionsInputTarget.value || "").trim() : ""
    if (term.length >= 2) this.fetchSuggestions()
  }

  // ----- Suggestions search -----

  searchSuggestions() {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.fetchSuggestions(), 300)
  }

  async fetchSuggestions() {
    const term = this.suggestionsInputTarget.value.trim()
    if (term.length < 2) {
      this.renderHint("Type at least 2 characters to search")
      return
    }
    this.saveRecent(term)

    try {
      const url = `${this.suggestionsUrlValue}?term=${encodeURIComponent(term)}&country=${encodeURIComponent(this.countryValue)}`
      const response = await fetch(url, { headers: { "Accept": "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      this.renderSuggestions(data.suggestions || [])
    } catch (e) {
      this.renderHint("Failed to load suggestions")
    }
  }

  renderHint(text) {
    this.suggestionsContainerTarget.textContent = ""
    const p = document.createElement("p")
    p.className = "text-xs text-base-content/40 italic"
    p.textContent = text
    this.suggestionsContainerTarget.appendChild(p)
  }

  renderSuggestions(suggestions) {
    this.suggestionsContainerTarget.textContent = ""

    if (suggestions.length === 0) {
      this.renderHint("No suggestions found")
      return
    }

    const wrapper = document.createElement("div")
    wrapper.className = "flex flex-wrap gap-1.5"
    suggestions.forEach(s => wrapper.appendChild(this.buildChip(s)))
    this.suggestionsContainerTarget.appendChild(wrapper)
  }

  buildChip(keyword) {
    const state = this.computeChipState(keyword)
    const chip = document.createElement("span")
    chip.dataset.keyword = keyword
    chip.dataset.state = state

    switch (state) {
      case "already":
        chip.className = KW_TAG_DISABLED
        chip.title = "Already in your keywords"
        chip.appendChild(document.createTextNode(keyword))
        this.appendCheckMark(chip)
        break
      case "too-long":
        chip.className = KW_CHIP_TOO_LONG
        chip.title = `Not enough space (${keyword.length} chars needed, ${this.charsFree()} free)`
        chip.appendChild(document.createTextNode(keyword))
        break
      case "staged":
        chip.className = KW_CHIP_STAGED
        chip.title = "Click to unstage"
        chip.dataset.action = "click->keyword-editor#unstageKeyword"
        this.prependCheckMark(chip)
        chip.appendChild(document.createTextNode(keyword))
        this.appendPopularityPip(chip, keyword)
        this.appendCharCount(chip, keyword)
        break
      default: // "available"
        chip.className = KW_CHIP_AVAILABLE
        chip.title = "Click to stage"
        chip.dataset.action = "click->keyword-editor#stageKeyword"
        chip.appendChild(document.createTextNode(keyword))
        this.appendPopularityPip(chip, keyword)
        this.appendCharCount(chip, keyword)
        this.appendBookmarkButton(chip, keyword)
    }
    return chip
  }

  computeChipState(keyword) {
    if (this.isKeywordInUse(keyword)) return "already"
    if (this.basket.includes(keyword)) return "staged"
    if (!this.fits(keyword)) return "too-long"
    return "available"
  }

  // ----- Stage / unstage -----

  stageKeyword(event) {
    const keyword = event.currentTarget.dataset.keyword
    if (!keyword) return
    if (this.basket.includes(keyword)) return
    if (!this.fits(keyword)) return
    this.basket.push(keyword)
    this.persistBasket()
    this.rerender()
  }

  unstageKeyword(event) {
    const keyword = event.currentTarget.dataset.keyword
    if (!keyword) return
    this.basket = this.basket.filter(k => k !== keyword)
    this.persistBasket()
    this.rerender()
  }

  clearBasket() {
    this.basket = []
    this.persistBasket()
    this.rerender()
  }

  stageFromScratchpad(event) {
    event.preventDefault()
    const keyword = event.currentTarget.dataset.keyword
    if (!keyword) return
    if (this.basket.includes(keyword)) return
    if (!this.fits(keyword)) return
    this.basket.push(keyword)
    this.persistBasket()
    this.rerender()
  }

  confirmLocaleSwitch(event) {
    if (!this.basketHasItems()) return
    if (!window.confirm("You have staged keywords that haven't been committed. Switching locale will discard them. Continue?")) {
      event.preventDefault()
    } else {
      this.clearBasket()
    }
  }

  rerender() {
    const term = this.suggestionsInputTarget?.value.trim() || ""
    if (term.length >= 2) this.fetchSuggestions()
    this.renderBudgetBar()
    this.renderBasketZone()
  }

  // ----- Budget math -----

  currentChars() {
    return (this.keywordsStrValue || "").length
  }

  basketChars() {
    if (this.basket.length === 0) return 0
    const hasExisting = this.currentChars() > 0
    return this.basket.reduce((sum, kw, i) => {
      const sep = (hasExisting || i > 0) ? 2 : 0
      return sum + kw.length + sep
    }, 0)
  }

  charsFree() {
    return this.limitValue - this.currentChars() - this.basketChars()
  }

  fits(keyword) {
    const hasExisting = this.currentChars() > 0 || this.basket.length > 0
    const sep = hasExisting ? 2 : 0
    return (this.currentChars() + this.basketChars() + keyword.length + sep) <= this.limitValue
  }

  renderBudgetBar() {
    if (!this.hasBudgetProgressTarget && !this.hasBudgetCurrentTarget) return
    const total = this.limitValue
    const current = this.currentChars()
    const staged = this.basketChars()
    const pct = n => `${Math.max(0, Math.min(100, (n / total) * 100))}%`

    if (this.hasBudgetCurrentTarget) this.budgetCurrentTarget.style.width = pct(current)
    if (this.hasBudgetStagedTarget)  this.budgetStagedTarget.style.width  = pct(staged)
    if (this.hasBudgetFreeTarget)    this.budgetFreeTarget.textContent    = `${Math.max(0, this.charsFree())} free`
  }

  // ----- Basket zone rendering -----

  renderBasketZone() {
    if (!this.hasBasketZoneTarget) return
    if (this.basket.length === 0) {
      this.basketZoneTarget.classList.add("hidden")
      return
    }
    this.basketZoneTarget.classList.remove("hidden")
    if (this.hasBasketCountTarget) this.basketCountTarget.textContent = String(this.basket.length)
    if (this.hasBasketDeltaTarget) {
      const delta = this.basketChars()
      const free = Math.max(0, this.charsFree())
      this.basketDeltaTarget.textContent = `+${delta} chars · ${free} free after commit`
    }
  }

  // ----- Persistence -----

  storageKey() {
    return `suggestions:basket:${this.appIdValue}:${this.localeValue}`
  }

  persistBasket() {
    try {
      sessionStorage.setItem(this.storageKey(), JSON.stringify(this.basket))
    } catch (_) { /* quota / private mode — non-fatal */ }
  }

  restoreBasket() {
    try {
      const raw = sessionStorage.getItem(this.storageKey())
      if (!raw) return
      const parsed = JSON.parse(raw)
      if (Array.isArray(parsed)) this.basket = parsed.filter(k => typeof k === "string")
    } catch (_) { this.basket = [] }
  }

  // ----- Recent searches (localStorage) -----

  recentStorageKey() {
    // Mirrors the dismissable_controller.js colon-delimited convention.
    const uid = document.body.dataset.userId || "anon"
    return `suggestions:recent:${uid}`
  }

  loadRecent() {
    try {
      const raw = localStorage.getItem(this.recentStorageKey())
      return raw ? JSON.parse(raw).slice(0, 5) : []
    } catch (_) { return [] }
  }

  saveRecent(term) {
    if (!term || term.length < 2) return
    let list = this.loadRecent()
    list = [term, ...list.filter(t => t !== term)].slice(0, 5)
    try { localStorage.setItem(this.recentStorageKey(), JSON.stringify(list)) } catch (_) {}
    this.renderRecent()
  }

  renderRecent() {
    if (!this.hasRecentSearchesTarget) return
    const list = this.loadRecent()
    this.recentSearchesTarget.textContent = ""
    if (list.length === 0) {
      this.recentSearchesTarget.classList.add("hidden")
      return
    }
    this.recentSearchesTarget.classList.remove("hidden")
    const label = document.createElement("span")
    label.className = "text-[0.65rem] uppercase tracking-wider text-base-content/40 font-semibold mr-2"
    label.textContent = "Recent"
    this.recentSearchesTarget.appendChild(label)
    list.forEach(term => {
      const chip = document.createElement("button")
      chip.type = "button"
      chip.className = "px-2.5 py-1 text-[0.7rem] rounded-full bg-base-content/[0.04] text-base-content/60 border border-base-content/[0.06] mr-1.5 cursor-pointer hover:bg-base-content/[0.08]"
      chip.textContent = term
      chip.addEventListener("click", () => {
        this.suggestionsInputTarget.value = term
        this.fetchSuggestions()
      })
      this.recentSearchesTarget.appendChild(chip)
    })
  }

  // ----- Helpers -----

  isKeywordInUse(keyword) {
    const kw = this.normalize(keyword)
    if (!kw) return false
    const current = (this.keywordsStrValue || "").split(",").map(k => this.normalize(k))
    if (current.includes(kw)) return true
    if (this.hasAppNameTarget) {
      const nameWords = this.normalize(this.appNameTarget.textContent).split(/\s+/)
      if (nameWords.includes(kw)) return true
    }
    if (this.hasSubtitleTarget) {
      const subWords = this.normalize(this.subtitleTarget.textContent).split(/\s+/)
      if (subWords.includes(kw)) return true
    }
    return false
  }

  normalize(str) {
    if (str == null) return ""
    return String(str).normalize("NFC").toLowerCase().trim().replace(/\s+/g, " ")
  }

  appendCheckMark(chip) {
    chip.appendChild(document.createTextNode(" "))
    const i = document.createElement("i")
    i.className = "fa-solid fa-check text-[0.5rem]"
    chip.appendChild(i)
  }

  prependCheckMark(chip) {
    const i = document.createElement("i")
    i.className = "fa-solid fa-check text-[0.55rem] text-success/90 mr-0.5"
    chip.appendChild(i)
  }

  appendPopularityPip(chip, keyword) {
    if (!this.appleAdsConnectedValue) return
    const score = this.popularityMapValue[this.normalize(keyword)]
    if (!score) return
    const pip = document.createElement("span")
    pip.className = "inline-flex gap-[1.5px] ml-1"
    pip.title = `Apple Ads popularity: ${score}/100`
    const filled = Math.max(1, Math.min(5, Math.ceil((score / 100) * 5)))
    const colorClass = score >= 70 ? POPULARITY_PIP_FILLED
                     : score >= 40 ? POPULARITY_PIP_MEDIUM
                     : POPULARITY_PIP_EMPTY
    for (let i = 0; i < 5; i++) {
      const d = document.createElement("span")
      d.className = i < filled ? colorClass : POPULARITY_PIP_EMPTY
      pip.appendChild(d)
    }
    chip.appendChild(pip)
  }

  appendCharCount(chip, keyword) {
    const span = document.createElement("span")
    span.className = "text-[0.65rem] text-base-content/30 ml-1"
    span.textContent = `·${keyword.length}`
    chip.appendChild(span)
  }

  appendBookmarkButton(chip, keyword) {
    const mark = document.createElement("i")
    mark.className = "fa-regular fa-bookmark text-[0.55rem] text-base-content/30 ml-1 cursor-pointer hover:text-base-content/70"
    mark.dataset.keyword = keyword
    mark.dataset.action = "click->keyword-editor#bookmarkKeyword"
    mark.title = "Save for later"
    chip.appendChild(mark)
  }

  bookmarkKeyword(event) {
    event.stopPropagation()
    const keyword = event.currentTarget.dataset.keyword
    if (!keyword) return
    const url = this.saveIdeaUrlValue
    if (!url) return
    const token = document.querySelector("meta[name='csrf-token']")?.content
    fetch(url, {
      method: "POST",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": token || "",
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ saved_keyword_idea: { keyword } })
    }).then(r => r.text()).then(html => {
      if (typeof Turbo !== "undefined") Turbo.renderStreamMessage(html)
    })
  }

  renderKeywordTags() {
    if (!this.hasKeywordsDisplayTarget) return
    this.keywordsDisplayTarget.textContent = ""
    const keywords = (this.keywordsStrValue || "").split(",").map(k => k.trim()).filter(k => k)
    if (keywords.length === 0) {
      const span = document.createElement("span")
      span.className = "text-xs text-base-content/30 italic"
      span.textContent = "No keywords set"
      this.keywordsDisplayTarget.appendChild(span)
      return
    }
    const wrapper = document.createElement("div")
    wrapper.className = "flex flex-wrap gap-1.5"
    keywords.forEach(kw => {
      const tag = document.createElement("span")
      tag.className = KW_TAG
      tag.textContent = kw
      wrapper.appendChild(tag)
    })
    this.keywordsDisplayTarget.appendChild(wrapper)
    const counter = document.createElement("div")
    counter.className = "mt-2 text-xs text-base-content/40"
    counter.textContent = `${this.keywordsStrValue.length}/${this.limitValue} characters used`
    this.keywordsDisplayTarget.appendChild(counter)
  }

  basketHasItems() { return this.basket.length > 0 }
}
