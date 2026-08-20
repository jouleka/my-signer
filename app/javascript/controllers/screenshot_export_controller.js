import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "sizeCheckbox", "progressContainer", "progressText", "progressBar", "exportButton", "localeCheckbox", "fastlaneToggle"]
  static values = { presets: Object }

  async getJSZipCtor() {
    if (this._jszipCtor) return this._jszipCtor
    if (window.JSZip) {
      this._jszipCtor = window.JSZip
      return this._jszipCtor
    }

    await import("jszip")
    this._jszipCtor = window.JSZip
    if (!this._jszipCtor) throw new Error("JSZip failed to initialize")
    return this._jszipCtor
  }

  openModal() {
    const modal = document.getElementById("export_modal")
    if (modal) modal.showModal()
    this.syncExportButton()
  }

  syncExportButton() {
    if (!this.hasExportButtonTarget) return
    const anyChecked = this.sizeCheckboxTargets.some(cb => cb.checked)
    this.exportButtonTarget.disabled = !anyChecked
  }

  quickExport(event) {
    const btn = event.currentTarget
    const preset = btn.dataset.preset
    this.exportPresets([preset], btn)
  }

  async startExport() {
    const selectedPresets = this.sizeCheckboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.dataset.preset)

    if (selectedPresets.length === 0) return

    await this.exportPresets(selectedPresets)
  }

  async exportPresets(presetKeys, sourceBtn = null) {
    // Get the editor controller
    const editorElement = this.element
    const editorController = this.application.getControllerForElementAndIdentifier(editorElement, "screenshot-editor")
    if (!editorController) return

    const settings = editorController.getCurrentSettings()
    const sceneDataTargets = editorController.getSceneDataTargets()
    const imageCache = editorController.getImageCache()

    if (sceneDataTargets.length === 0) return

    // Track original button children for inline feedback
    let btnOriginalChildren
    if (sourceBtn) {
      btnOriginalChildren = Array.from(sourceBtn.childNodes).map(n => n.cloneNode(true))
      sourceBtn.disabled = true
      this.setBtnContent(sourceBtn, "loading", "Exporting...")
    }

    // Show modal progress (only when triggered from modal)
    if (!sourceBtn) {
      if (this.hasProgressContainerTarget) {
        this.progressContainerTarget.classList.remove("hidden")
      }
      if (this.hasExportButtonTarget) {
        this.exportButtonTarget.disabled = true
      }
    }

    const allPresets = this.presetsValue || {}

    // Collect all sizes to render
    const sizes = []
    presetKeys.forEach(key => {
      const preset = allPresets[key]
      if (preset) {
        preset.forEach(size => {
          sizes.push({ ...size, preset: key })
        })
      }
    })

    // Determine locales to export
    const selectedLocales = this.localeCheckboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.dataset.locale)

    // If no locale checkboxes or none selected, export default only
    const localesToExport = selectedLocales.length > 0 ? selectedLocales : [null]
    const isMultiLocale = selectedLocales.length > 0

    // Check if Fastlane folder structure is requested
    const useFastlaneLayout = this.hasFastlaneToggleTarget && this.fastlaneToggleTarget.checked

    const totalWork = sceneDataTargets.length * sizes.length * localesToExport.length
    let completed = 0

    try {
      const JSZipCtor = await this.getJSZipCtor()
      const zip = new JSZipCtor()

      for (const locale of localesToExport) {
        for (const [sceneIdx, sceneData] of sceneDataTargets.entries()) {
          const sceneId = sceneData.dataset.sceneId
          const position = sceneData.dataset.scenePosition || "1"
          let sceneOverrides = {}
          try { sceneOverrides = JSON.parse(sceneData.dataset.sceneOverrides || "{}") } catch {}

          // Determine caption/subtitle for this locale
          let caption, subtitle
          if (locale && isMultiLocale) {
            let variants = {}
            try { variants = JSON.parse(sceneData.dataset.sceneLocaleVariants || "{}") } catch {}
            const localeData = variants[locale] || {}
            caption = localeData.caption_text || sceneData.dataset.sceneCaption || ""
            subtitle = localeData.subtitle_text || sceneData.dataset.sceneSubtitle || ""
          } else {
            caption = sceneData.dataset.sceneCaption || ""
            subtitle = sceneData.dataset.sceneSubtitle || ""
          }

          // Ensure image is loaded
          let image = imageCache.get(sceneId)
          if (!image) {
            image = await this.loadImage(sceneData.dataset.sceneImageUrl)
            imageCache.set(sceneId, image)
          }

          for (const size of sizes) {
            const sceneSettings = { ...settings, caption_text: caption, subtitle_text: subtitle, ...sceneOverrides }

            // Inject panoramic slice info for this scene
            if (settings.background_type === "panoramic") {
              sceneSettings.panoramic_scene_index = sceneIdx
              sceneSettings.panoramic_total_scenes = sceneDataTargets.length
            }
            // Use the preset's matching device frame for correct dimensions
            if (settings.device_frame && settings.device_frame !== "none" && size.device_frame) {
              sceneSettings.device_frame = size.device_frame
            }
            const canvas = await editorController.renderAtSize(image, size.width, size.height, sceneSettings)

            // Convert to blob
            const blob = await new Promise((resolve, reject) =>
              canvas.toBlob(b => b ? resolve(b) : reject(new Error("Canvas export failed — canvas may be tainted by cross-origin images")), "image/png")
            )

            // Determine folder path based on layout format
            const fileName = `screenshot_${String(position).padStart(2, "0")}.png`

            if (useFastlaneLayout) {
              // Fastlane layout: screenshots/{locale}/{fileName}
              // When multiple presets are selected, add a device subfolder to
              // prevent filename collisions (all presets share the same
              // position-based filename).
              const localeFolder = locale || "en-US"
              if (presetKeys.length > 1) {
                const deviceFolder = this.folderForPreset(size.preset)
                zip.file(`screenshots/${localeFolder}/${deviceFolder}/${fileName}`, blob)
              } else {
                zip.file(`screenshots/${localeFolder}/${fileName}`, blob)
              }
            } else if (isMultiLocale && locale) {
              const folderName = this.folderForPreset(size.preset)
              zip.file(`${locale}/${folderName}/${fileName}`, blob)
            } else {
              const folderName = this.folderForPreset(size.preset)
              zip.file(`${folderName}/${fileName}`, blob)
            }

            completed++
            if (sourceBtn) {
              const pct = Math.round((completed / totalWork) * 100)
              this.setBtnContent(sourceBtn, "loading", `${pct}%`)
            } else {
              this.updateProgress(completed, totalWork)
            }
          }
        }
      }

      // Generate and download ZIP
      if (sourceBtn) {
        this.setBtnContent(sourceBtn, "loading", "Zipping...")
      } else {
        this.updateProgressText("Generating ZIP...")
      }
      const content = await zip.generateAsync({ type: "blob" })

      const url = URL.createObjectURL(content)
      const a = document.createElement("a")
      a.href = url
      a.download = useFastlaneLayout ? "fastlane_screenshots.zip" : "screenshots.zip"
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)

      // Show success
      if (sourceBtn) {
        this.setBtnContent(sourceBtn, "fa-solid fa-check", "Done")
        setTimeout(() => {
          this.restoreBtn(sourceBtn, btnOriginalChildren)
        }, 2000)
      } else {
        const modal = document.getElementById("export_modal")
        if (modal) modal.close()
      }
    } catch (error) {
      console.error("Export failed:", error)
      if (sourceBtn) {
        this.setBtnContent(sourceBtn, "fa-solid fa-xmark", "Failed")
        setTimeout(() => {
          this.restoreBtn(sourceBtn, btnOriginalChildren)
        }, 2000)
      } else {
        this.updateProgressText("Export failed. Please try again.")
      }
    } finally {
      if (!sourceBtn) {
        if (this.hasProgressContainerTarget) {
          setTimeout(() => {
            this.progressContainerTarget.classList.add("hidden")
          }, 2000)
        }
        if (this.hasExportButtonTarget) {
          this.exportButtonTarget.disabled = false
        }
      }
    }
  }

  setBtnContent(btn, iconClass, text) {
    btn.textContent = ""
    if (iconClass === "loading") {
      const spinner = document.createElement("span")
      spinner.className = "loading loading-spinner loading-xs"
      btn.appendChild(spinner)
    } else {
      const icon = document.createElement("i")
      icon.className = iconClass
      btn.appendChild(icon)
    }
    btn.appendChild(document.createTextNode(` ${text}`))
  }

  restoreBtn(btn, originalChildren) {
    btn.textContent = ""
    originalChildren.forEach(child => btn.appendChild(child))
    btn.disabled = false
  }

  loadImage(url) {
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.crossOrigin = "anonymous"
      img.onload = () => resolve(img)
      img.onerror = reject
      img.src = url
    })
  }

  folderForPreset(preset) {
    const map = {
      "ios_required": "iOS/iPhone_Required",
      "ios_optional": "iOS/iPhone_5.5",
      "ios_ipad": "iOS/iPad",
      "android_phone": "Android/Phone",
      "android_tablet_7": "Android/Tablet_7",
      "android_tablet_10": "Android/Tablet_10"
    }
    return map[preset] || preset
  }

  updateProgress(completed, total) {
    const pct = Math.round((completed / total) * 100)
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.value = pct
    }
    this.updateProgressText(`Rendering... ${completed}/${total}`)
  }

  updateProgressText(text) {
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = text
    }
  }
}
