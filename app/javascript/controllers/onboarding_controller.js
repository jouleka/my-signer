import { Controller } from "@hotwired/stimulus"

// Onboarding wizard controller
// Handles progress animation, platform selection, copy-to-clipboard, and celebration effects
export default class extends Controller {
  static targets = ["progressBar", "progressText", "platformInput", "platformCard", "orgName", "orgSubmit", "confettiCanvas"]
  static values = {
    step: Number,
    totalSteps: Number,
    platform: { type: String, default: "both" }
  }

  connect() {
    this.animateProgressBar()

    // Auto-celebrate on the complete step
    if (this.stepValue >= this.totalStepsValue) {
      setTimeout(() => this.celebrate(), 500)
    }
  }

  // --- Progress Bar ---
  animateProgressBar() {
    if (!this.hasProgressBarTarget) return
    const progress = this.stepValue > 0
      ? Math.round(((this.stepValue) / this.totalStepsValue) * 100)
      : 20 // endowed progress effect: start at 20%

    requestAnimationFrame(() => {
      this.progressBarTarget.style.width = `${progress}%`
      if (this.hasProgressTextTarget) {
        this.progressTextTarget.textContent = `${progress}%`
      }
    })
  }

  // --- Platform Selection ---
  selectPlatform(event) {
    const card = event.currentTarget
    const platform = card.dataset.platform

    this.platformValue = platform
    if (this.hasPlatformInputTarget) {
      this.platformInputTarget.value = platform
    }

    // Update visual state
    this.platformCardTargets.forEach(c => {
      c.classList.remove("ring-2", "ring-primary", "border-primary")
      c.classList.add("border-base-300")
      const check = c.querySelector("[data-check]")
      if (check) check.classList.add("hidden")
    })

    card.classList.add("ring-2", "ring-primary", "border-primary")
    card.classList.remove("border-base-300")
    const check = card.querySelector("[data-check]")
    if (check) check.classList.remove("hidden")
  }

  // --- Org Name Validation ---
  validateOrgName() {
    if (!this.hasOrgNameTarget || !this.hasOrgSubmitTarget) return
    const name = this.orgNameTarget.value.trim()
    this.orgSubmitTarget.disabled = name.length === 0
  }

  // --- Copy to Clipboard ---
  async copy(event) {
    const button = event.currentTarget
    const text = button.dataset.copyText
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
      const icon = button.querySelector("i")
      const label = button.querySelector("[data-copy-label]")

      if (icon) {
        const originalClass = icon.className
        icon.className = "fa-solid fa-check text-success"
        setTimeout(() => { icon.className = originalClass }, 2000)
      }
      if (label) {
        const originalText = label.textContent
        label.textContent = "Copied!"
        setTimeout(() => { label.textContent = originalText }, 2000)
      }
    } catch (err) {
      console.error("Copy failed:", err)
    }
  }

  // --- Confetti Celebration ---
  celebrate() {
    if (!this.hasConfettiCanvasTarget) return
    const canvas = this.confettiCanvasTarget
    canvas.classList.remove("hidden")
    const ctx = canvas.getContext("2d")
    canvas.width = window.innerWidth
    canvas.height = window.innerHeight

    const particles = []
    const colors = ["#6419E6", "#D926A9", "#1FB2A6", "#F59E0B", "#3B82F6", "#10B981", "#EF4444", "#8B5CF6"]

    for (let i = 0; i < 150; i++) {
      particles.push({
        x: Math.random() * canvas.width,
        y: Math.random() * canvas.height - canvas.height,
        vx: (Math.random() - 0.5) * 8,
        vy: Math.random() * 3 + 2,
        color: colors[Math.floor(Math.random() * colors.length)],
        size: Math.random() * 8 + 3,
        rotation: Math.random() * 360,
        rotationSpeed: (Math.random() - 0.5) * 10,
        shape: Math.random() > 0.5 ? "rect" : "circle"
      })
    }

    let frame = 0
    const maxFrames = 180

    const animate = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height)

      particles.forEach(p => {
        p.x += p.vx
        p.y += p.vy
        p.vy += 0.05
        p.vx *= 0.99
        p.rotation += p.rotationSpeed

        ctx.save()
        ctx.translate(p.x, p.y)
        ctx.rotate((p.rotation * Math.PI) / 180)
        ctx.globalAlpha = Math.max(0, 1 - frame / maxFrames)
        ctx.fillStyle = p.color

        if (p.shape === "rect") {
          ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.6)
        } else {
          ctx.beginPath()
          ctx.arc(0, 0, p.size / 2, 0, Math.PI * 2)
          ctx.fill()
        }
        ctx.restore()
      })

      frame++
      if (frame < maxFrames) {
        requestAnimationFrame(animate)
      } else {
        canvas.classList.add("hidden")
        ctx.clearRect(0, 0, canvas.width, canvas.height)
      }
    }

    requestAnimationFrame(animate)
  }

  // --- Token reveal animation ---
  revealToken() {
    const tokenEl = this.element.querySelector("[data-token-value]")
    if (!tokenEl) return
    tokenEl.classList.remove("blur-sm")
    tokenEl.classList.add("animate-pulse")
    setTimeout(() => tokenEl.classList.remove("animate-pulse"), 1000)
  }
}
