import { Controller } from "@hotwired/stimulus"

// Table of Contents scroll spy controller
// Highlights the current section in the TOC as user scrolls
export default class extends Controller {
  static targets = ["link"]
  static values = { offset: { type: Number, default: 100 } }

  connect() {
    this.headings = []
    this.currentActiveLink = null
    this.linkTargets.forEach((link) => {
      const id = link.dataset.tocId
      const heading = document.getElementById(id)
      if (heading) {
        this.headings.push({ id, element: heading, link })
      }
    })

    this.handleScroll = this.handleScroll.bind(this)
    window.addEventListener("scroll", this.handleScroll, { passive: true })

    // Initial highlight
    requestAnimationFrame(() => this.handleScroll())
  }

  // Handle TOC link clicks with proper offset
  scrollToHeading(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.tocId
    const heading = document.getElementById(id)
    
    if (heading) {
      const targetPosition = heading.getBoundingClientRect().top + window.scrollY - this.offsetValue + 20
      window.scrollTo({ top: targetPosition, behavior: "smooth" })
      
      // Update URL hash without triggering scroll
      history.pushState(null, null, `#${id}`)
    }
  }

  disconnect() {
    window.removeEventListener("scroll", this.handleScroll)
  }

  handleScroll() {
    const scrollY = window.scrollY + this.offsetValue
    let activeHeading = null

    // Find the last heading that's above current scroll position
    for (const heading of this.headings) {
      if (heading.element.offsetTop <= scrollY) {
        activeHeading = heading
      } else {
        break
      }
    }

    // If no heading above, use first one
    if (!activeHeading && this.headings.length > 0) {
      activeHeading = this.headings[0]
    }

    if (activeHeading) {
      this.setActive(activeHeading.link)
    }
  }

  setActive(activeLink) {
    // Skip if same link is already active
    if (this.currentActiveLink === activeLink) return
    this.currentActiveLink = activeLink

    this.linkTargets.forEach((link) => {
      const isActive = link === activeLink
      link.classList.toggle("text-primary", isActive)
      link.classList.toggle("border-primary", isActive)
      link.classList.toggle("font-medium", isActive)
      link.classList.toggle("text-base-content/70", !isActive)
      link.classList.toggle("border-transparent", !isActive)
    })

    // Scroll active link into view in TOC sidebar (only within TOC container)
    if (activeLink) {
      const tocContainer = activeLink.closest("[data-controller='toc']")
      if (tocContainer) {
        const linkRect = activeLink.getBoundingClientRect()
        const containerRect = tocContainer.getBoundingClientRect()
        
        // Only scroll if link is outside visible area of TOC container
        if (linkRect.top < containerRect.top || linkRect.bottom > containerRect.bottom) {
          activeLink.scrollIntoView({ block: "nearest", behavior: "smooth" })
        }
      }
    }
  }
}
