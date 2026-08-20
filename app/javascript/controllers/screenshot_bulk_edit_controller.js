import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "tableBody", "tableHead", "bulkTable", "cellCount"]
  static values = {
    bulkUpdateUrl: String,
    locales: Array
  }

  open() {
    const editorElement = this.element
    const editorController = this.application.getControllerForElementAndIdentifier(editorElement, "screenshot-editor")
    if (!editorController) return

    // Save current locale text before reading scene data
    if (editorController._saveCurrentLocaleTextToDOM) {
      editorController._saveCurrentLocaleTextToDOM()
    }

    const sceneDataTargets = editorController.getSceneDataTargets()
    if (sceneDataTargets.length === 0) return

    const locales = this.localesValue || []
    const hasLocales = locales.length > 0
    const defaultLocale = hasLocales ? locales[0] : null

    const modal = document.getElementById("bulk_edit_modal")
    const thead = this.hasTableHeadTarget ? this.tableHeadTarget : modal?.querySelector("thead tr")
    const tbody = this.hasTableBodyTarget ? this.tableBodyTarget : modal?.querySelector("tbody")

    // Build table header
    if (thead) {
      while (thead.firstChild) thead.removeChild(thead.firstChild)

      const addTh = (text, extraClass = "", colspan = 1) => {
        const th = document.createElement("th")
        th.className = `text-[11px] font-semibold uppercase tracking-wider text-base-content/50 px-3 py-2.5 text-left whitespace-nowrap ${extraClass}`
        th.textContent = text
        if (colspan > 1) th.colSpan = colspan
        thead.appendChild(th)
      }

      addTh("#", "w-10 text-center")

      if (hasLocales) {
        // Show default locale label
        addTh(`${defaultLocale} Caption`, "min-w-[160px]")
        addTh(`${defaultLocale} Subtitle`, "min-w-[140px]")

        // Additional locale columns
        locales.forEach(locale => {
          if (locale !== defaultLocale) {
            addTh(`${locale} Caption`, "min-w-[160px] border-l border-base-300/50")
            addTh(`${locale} Subtitle`, "min-w-[140px]")
          }
        })
      } else {
        addTh("Caption", "min-w-[200px]")
        addTh("Subtitle", "min-w-[180px]")
      }
    }

    // Build rows
    if (tbody) {
      while (tbody.firstChild) tbody.removeChild(tbody.firstChild)

      let cellCount = 0

      sceneDataTargets.forEach((sceneData, idx) => {
        const sceneId = sceneData.dataset.sceneId
        const position = sceneData.dataset.scenePosition || "1"
        const caption = sceneData.dataset.sceneCaption || ""
        const subtitle = sceneData.dataset.sceneSubtitle || ""
        let variants = {}
        try { variants = JSON.parse(sceneData.dataset.sceneLocaleVariants || "{}") } catch {}

        const row = document.createElement("tr")
        row.dataset.sceneId = sceneId
        row.className = "group hover:bg-base-200/30 transition-colors"

        // Position cell
        const posCell = document.createElement("td")
        posCell.className = "text-xs font-medium text-base-content/30 text-center px-3 py-0 w-10"
        posCell.textContent = position
        row.appendChild(posCell)

        // Default caption & subtitle
        row.appendChild(this._createInputCell("caption_text", caption))
        row.appendChild(this._createInputCell("subtitle_text", subtitle))
        cellCount += 2

        // Locale cells
        if (hasLocales) {
          locales.forEach(locale => {
            if (locale !== defaultLocale) {
              const localeCaption = variants[locale]?.caption_text || ""
              const localeSubtitle = variants[locale]?.subtitle_text || ""
              row.appendChild(this._createInputCell("locale_caption", localeCaption, locale, true))
              row.appendChild(this._createInputCell("locale_subtitle", localeSubtitle, locale))
              cellCount += 2
            }
          })
        }

        tbody.appendChild(row)
      })

      // Keyboard navigation: Enter = move down, Tab = move right (handled natively)
      tbody.querySelectorAll("input").forEach(input => {
        input.addEventListener("keydown", (e) => {
          if (e.key === "Enter") {
            e.preventDefault()
            const td = input.closest("td")
            const tr = td.closest("tr")
            const cellIdx = Array.from(tr.cells).indexOf(td)
            const nextRow = tr.nextElementSibling
            if (nextRow) {
              const nextInput = nextRow.cells[cellIdx]?.querySelector("input")
              if (nextInput) nextInput.focus()
            }
          }
        })
      })

      // Update cell count label
      if (this.hasCellCountTarget) {
        this.cellCountTarget.textContent = `${sceneDataTargets.length} scenes \u00b7 ${cellCount} cells`
      }
    }

    if (modal) modal.showModal()
  }

  _createInputCell(field, value, locale, isLocaleBorder) {
    const td = document.createElement("td")
    td.className = `p-0${isLocaleBorder ? " border-l border-base-300/50" : ""}`

    const input = document.createElement("input")
    input.type = "text"
    input.className = "w-full bg-transparent px-3 py-2.5 text-sm outline-none border-0 focus:bg-primary/5 transition-colors placeholder:text-base-content/20"
    input.dataset.field = field
    input.value = value
    input.placeholder = "\u2014"
    if (locale) input.dataset.locale = locale
    td.appendChild(input)
    return td
  }

  async saveBulk() {
    const modal = document.getElementById("bulk_edit_modal")
    const tbody = this.hasTableBodyTarget ? this.tableBodyTarget : modal?.querySelector("tbody")
    if (!tbody) return

    const scenes = []
    const locales = this.localesValue || []
    const hasLocales = locales.length > 0

    tbody.querySelectorAll("tr").forEach(row => {
      const sceneId = row.dataset.sceneId
      const captionInput = row.querySelector("[data-field='caption_text']")
      const subtitleInput = row.querySelector("[data-field='subtitle_text']")

      const sceneData = {
        id: sceneId,
        caption_text: captionInput?.value || "",
        subtitle_text: subtitleInput?.value || ""
      }

      if (hasLocales) {
        const localeVariants = {}
        row.querySelectorAll("[data-field='locale_caption']").forEach(input => {
          const locale = input.dataset.locale
          localeVariants[locale] = localeVariants[locale] || {}
          localeVariants[locale].caption_text = input.value
        })
        row.querySelectorAll("[data-field='locale_subtitle']").forEach(input => {
          const locale = input.dataset.locale
          localeVariants[locale] = localeVariants[locale] || {}
          localeVariants[locale].subtitle_text = input.value
        })
        sceneData.locale_variants = localeVariants
      }

      scenes.push(sceneData)
    })

    const csrfToken = document.querySelector("meta[name=csrf-token]")?.content

    // Disable save button during request
    const saveBtn = modal?.querySelector("[data-action*='saveBulk']")
    if (saveBtn) {
      saveBtn.disabled = true
      saveBtn.querySelector("i")?.classList.replace("fa-floppy-disk", "fa-spinner")
      saveBtn.querySelector("i")?.classList.add("fa-spin")
    }

    try {
      const resp = await fetch(this.bulkUpdateUrlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken, "Accept": "application/json" },
        body: JSON.stringify({ scenes })
      })

      if (resp.ok) {
        // Update DOM scene data attributes
        const editorElement = this.element
        const editorController = this.application.getControllerForElementAndIdentifier(editorElement, "screenshot-editor")

        scenes.forEach(scene => {
          const sceneData = editorController?.findSceneData(scene.id)
          if (sceneData) {
            sceneData.dataset.sceneCaption = scene.caption_text
            sceneData.dataset.sceneSubtitle = scene.subtitle_text
            if (scene.locale_variants) {
              sceneData.dataset.sceneLocaleVariants = JSON.stringify(scene.locale_variants)
            }
          }
        })

        // Reload current scene text
        if (editorController?._loadLocaleText) {
          editorController._loadLocaleText()
        } else if (editorController?.currentSceneId) {
          const sd = editorController.findSceneData(editorController.currentSceneId)
          if (sd && editorController.hasCaptionTextTarget) {
            editorController.captionTextTarget.value = sd.dataset.sceneCaption || ""
          }
          if (sd && editorController.hasSubtitleTextTarget) {
            editorController.subtitleTextTarget.value = sd.dataset.sceneSubtitle || ""
          }
        }

        if (editorController) editorController.updatePreview()

        // Update thumbnail labels (respecting current locale)
        if (editorController?._updateThumbnailLabelsForLocale) {
          editorController._updateThumbnailLabelsForLocale()
        } else {
          scenes.forEach(scene => {
            const editorSceneData = editorController?.findSceneData(scene.id)
            if (editorSceneData) {
              editorController?.thumbnailTargets?.forEach(thumb => {
                const sid = thumb.dataset.screenshotEditorSceneIdParam
                if (String(sid) === String(scene.id)) {
                  const label = thumb.querySelector("p")
                  if (label) label.textContent = scene.caption_text || `Scene ${editorSceneData.dataset.scenePosition}`
                }
              })
            }
          })
        }

        if (modal) modal.close()
      } else {
        const data = await resp.json().catch(() => ({}))
        console.error("Bulk update failed:", data)
        alert("Failed to save. Please try again.")
      }
    } catch (err) {
      console.error("Bulk update error:", err)
      alert("Failed to save. Please try again.")
    } finally {
      if (saveBtn) {
        saveBtn.disabled = false
        saveBtn.querySelector("i")?.classList.replace("fa-spinner", "fa-floppy-disk")
        saveBtn.querySelector("i")?.classList.remove("fa-spin")
      }
    }
  }
}
