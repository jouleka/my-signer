import { Controller } from "@hotwired/stimulus"

// Renders a per-country keyword rank history sparkline. The y-axis is
// reversed because "lower rank number = better"; a dip in the line is
// visually a gain.
//
// Includes full teardown (Chart.js chart instance + turbo:before-cache
// listener) so repeated expand/collapse of the same TrackedKeyword
// card doesn't leak observers or re-mount onto a cached canvas.
export default class extends Controller {
  static values = { labels: Array, data: Array }

  async connect() {
    // chart.js is pinned in importmap.rb and resolved via dynamic import.
    const ChartModule = await import("chart.js/auto")
    // Defend against races: if we were disconnected while awaiting the
    // module (e.g. turbo:before-cache, quick re-render), bail.
    if (!this.element.isConnected) return

    const Chart = ChartModule.Chart || ChartModule.default

    const ctx = this.element.getContext("2d")
    this.chart = new Chart(ctx, {
      type: "line",
      data: {
        labels: this.labelsValue,
        datasets: [{
          data: this.dataValue,
          label: "Rank (lower = better)",
          tension: 0.25,
          borderColor: "rgba(99, 102, 241, 0.8)",
          backgroundColor: "rgba(99, 102, 241, 0.1)",
          fill: true,
          pointRadius: 2
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: { reverse: true, beginAtZero: false, ticks: { precision: 0 } },
          x: { ticks: { maxTicksLimit: 7 } }
        },
        plugins: { legend: { display: false } }
      }
    })

    // Bind once so add/remove see the same function reference.
    this.destroyChart = this.destroyChart.bind(this)
    document.addEventListener("turbo:before-cache", this.destroyChart)
  }

  disconnect() {
    this.destroyChart()
    document.removeEventListener("turbo:before-cache", this.destroyChart)
  }

  destroyChart() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
}
