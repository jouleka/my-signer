// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Release the browser's modal top layer before Turbo replaces or caches the
// document. Removing an open dialog during a form redirect can otherwise
// leave the new page inert even though the dialog is no longer visible.
function closeDialogsBeforeNavigation() {
  document.querySelectorAll("dialog[open]").forEach(dialog => dialog.close())
}

document.addEventListener("turbo:before-render", closeDialogsBeforeNavigation)
document.addEventListener("turbo:before-cache", closeDialogsBeforeNavigation)
