import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    snapshots: Array
  }

  connect() {
    this.loadChart()
  }

  async loadChart() {
    try {
      const ChartModule = await import("chart.js/auto")
      const Chart = ChartModule.default || ChartModule.Chart || (typeof ChartModule === "function" ? ChartModule : null)

      if (!Chart || typeof Chart !== "function") {
        console.warn("Rating chart: Could not resolve Chart constructor from module", ChartModule)
        return
      }

      const canvas = this.element.querySelector("canvas")
      if (!canvas) return

      const snapshots = this.snapshotsValue || []
      if (snapshots.length === 0) return

      const labels = snapshots.map(s => s.date || s.snapshot_date)
      const data = snapshots.map(s => parseFloat(s.average_rating || s.avg || 0))

      const ctx = canvas.getContext("2d")

      // Theme-aware colors
      const computedStyle = getComputedStyle(this.element)
      const textColor = computedStyle.getPropertyValue("color") || "rgba(160,160,160,0.5)"

      // Derive a muted grid color from text
      const gridColor = textColor.replace(/[\d.]+\)$/, "0.06)")
      const tickColor = textColor.replace(/[\d.]+\)$/, "0.35)")

      // Brand purple palette
      const lineColor = "rgba(124, 58, 237, 0.85)"
      const fillTop = "rgba(124, 58, 237, 0.10)"
      const fillBottom = "rgba(124, 58, 237, 0.0)"
      const pointColor = "rgba(124, 58, 237, 1)"
      const pointHoverBg = "rgba(124, 58, 237, 0.15)"

      const gradient = ctx.createLinearGradient(0, 0, 0, canvas.height)
      gradient.addColorStop(0, fillTop)
      gradient.addColorStop(1, fillBottom)

      // Auto-scale y-axis around data range with padding
      const minVal = Math.min(...data)
      const maxVal = Math.max(...data)
      const padding = 0.3
      const yMin = Math.max(0, Math.floor((minVal - padding) * 2) / 2)  // snap to 0.5
      const yMax = Math.min(5, Math.ceil((maxVal + padding) * 2) / 2)

      // Format date labels: "Mar 13" instead of "2026-03-13"
      const shortLabels = labels.map(l => {
        try {
          const d = new Date(l + "T00:00:00")
          return d.toLocaleDateString("en-US", { month: "short", day: "numeric" })
        } catch { return l }
      })

      // Skip labels when too many — show every Nth
      const maxLabels = 12
      const skipN = Math.ceil(shortLabels.length / maxLabels)

      new Chart(ctx, {
        type: "line",
        data: {
          labels: shortLabels,
          datasets: [{
            label: "Rating",
            data: data,
            borderColor: lineColor,
            backgroundColor: gradient,
            borderWidth: 2,
            tension: 0.3,
            fill: true,
            pointBackgroundColor: pointColor,
            pointBorderColor: "transparent",
            pointBorderWidth: 0,
            pointRadius: 2.5,
            pointHoverRadius: 5,
            pointHoverBackgroundColor: pointColor,
            pointHoverBorderColor: pointHoverBg,
            pointHoverBorderWidth: 6
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          layout: {
            padding: { top: 8, right: 12, bottom: 0, left: 4 }
          },
          scales: {
            y: {
              min: yMin,
              max: yMax,
              ticks: {
                stepSize: 0.5,
                font: { size: 10, family: "inherit" },
                color: tickColor,
                callback: v => v.toFixed(1)
              },
              grid: { color: gridColor },
              border: { display: false }
            },
            x: {
              ticks: {
                maxRotation: 0,
                font: { size: 10, family: "inherit" },
                color: tickColor,
                callback: function(val, idx) {
                  return idx % skipN === 0 ? this.getLabelForValue(val) : ""
                }
              },
              grid: { display: false },
              border: { display: false }
            }
          },
          plugins: {
            legend: { display: false },
            tooltip: {
              backgroundColor: "rgba(15, 15, 20, 0.92)",
              titleColor: "rgba(255,255,255,0.6)",
              bodyColor: "#fff",
              titleFont: { size: 11, weight: "normal", family: "inherit" },
              bodyFont: { size: 13, weight: "600", family: "inherit" },
              padding: { top: 8, right: 12, bottom: 8, left: 12 },
              cornerRadius: 8,
              displayColors: false,
              callbacks: {
                title: ctx => ctx[0]?.label || "",
                label: ctx => `★ ${ctx.parsed.y.toFixed(2)}`
              }
            }
          },
          interaction: {
            mode: "index",
            intersect: false
          }
        }
      })
    } catch (e) {
      console.warn("Rating chart: Chart.js not available", e)
    }
  }
}
