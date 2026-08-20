import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    data: Array,
    color: { type: String, default: "rgba(124, 58, 237, 0.6)" }
  }

  async connect() {
    if (!this.dataValue || this.dataValue.length === 0) return

    try {
      const { Chart } = await import("chart.js/auto")

      const canvas = document.createElement("canvas")
      canvas.style.width = "100%"
      canvas.style.height = "100%"
      this.element.appendChild(canvas)

      const ctx = canvas.getContext("2d")
      const gradient = ctx.createLinearGradient(0, 0, 0, canvas.parentElement.clientHeight || 40)
      // Derive fill color from line color, handling both rgba and oklch formats.
      // Canvas 2D context supports oklch() natively in modern browsers.
      const color = this.colorValue
      let fillColor
      if (color.startsWith("oklch")) {
        // oklch with alpha: oklch(0.55 0.2 285 / 0.7) → replace alpha
        // oklch without alpha: oklch(0.55 0.2 285) → append alpha
        if (color.match(/\/\s*[\d.]+\s*\)/)) {
          fillColor = color.replace(/\/\s*[\d.]+\s*\)/, "/ 0.12)")
        } else {
          fillColor = color.replace(/\)$/, " / 0.12)")
        }
      } else {
        fillColor = color.replace(/[\d.]+\)$/, "0.15)")
      }
      gradient.addColorStop(0, fillColor)
      gradient.addColorStop(1, "transparent")

      new Chart(ctx, {
        type: "line",
        data: {
          labels: this.dataValue.map((_, i) => i),
          datasets: [{
            data: this.dataValue,
            borderColor: this.colorValue,
            backgroundColor: gradient,
            borderWidth: 1.5,
            fill: true,
            pointRadius: 0,
            tension: 0.4
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: false }, tooltip: { enabled: false } },
          scales: {
            x: { display: false },
            y: { display: false, beginAtZero: false }
          },
          elements: { line: { capBezierPoints: true } }
        }
      })
    } catch (e) {
      // Chart.js not available — fail silently
    }
  }
}
