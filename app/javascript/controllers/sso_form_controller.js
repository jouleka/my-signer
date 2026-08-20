import { Controller } from "@hotwired/stimulus"

// Drives the SSO configuration form UX:
//   - IdP preset buttons pre-fill the name-identifier format + attribute
//     mapping placeholders for Okta, Azure AD, and Google Workspace.
//   - Live PEM certificate preview shows whether the pasted cert parses
//     (string-level markers only; full x509 parsing is done server-side).
//   - Enforcement checkbox gets a conspicuous warning card when toggled
//     on (since this has real lockout implications).
//
// Targets:
//   nameIdSelect   - <select> for name_identifier_format
//   emailHint      - <p> under idp_cert / mappings that updates per preset
//   certArea       - <textarea> for idp_cert
//   certStatus     - <span> that shows "PEM markers detected" / "Looks invalid"
//   enforceInput   - <input type=checkbox> for enforced
//   enforceWarning - <div> hidden by default, shown when enforced is checked
export default class extends Controller {
  static targets = ["nameIdSelect", "emailHint", "certArea", "certStatus", "enforceInput", "enforceWarning"]

  static presets = {
    okta: {
      nameId: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
      emailClaim: "user.email",
      nameClaim: "user.firstName + ' ' + user.lastName",
      note: "Okta sends email via the Name ID when EmailAddress format is selected. Add an email attribute statement in Okta if you want it as a claim too."
    },
    azure: {
      nameId: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
      emailClaim: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
      nameClaim: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
      note: "Microsoft Entra ID (Azure AD) sends claims via SOAP-style URNs. Make sure your Unique User Identifier (Name ID) is set to user.mail with Email Address format."
    },
    google: {
      nameId: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
      emailClaim: "email",
      nameClaim: "name",
      note: "Google Workspace uses simple claim names. In the Admin console, map 'email' to Primary email and 'name' to Full name."
    },
    custom: {
      nameId: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
      emailClaim: null,
      nameClaim: null,
      note: "Using a generic SAML 2.0 IdP. We'll accept email via the Name ID by default; add explicit email/name attribute mappings if your IdP requires them."
    }
  }

  connect() {
    this.checkCert()
    this.checkEnforce()
  }

  applyPreset(event) {
    event.preventDefault()
    const preset = event.currentTarget.dataset.preset
    const cfg = this.constructor.presets[preset]
    if (!cfg) return

    // Highlight the chosen button visually
    this.element.querySelectorAll("[data-preset]").forEach((btn) => {
      btn.classList.remove("ring-2", "ring-primary/40", "bg-primary/10", "text-primary")
      btn.classList.add("bg-base-100", "text-base-content/70")
    })
    event.currentTarget.classList.remove("bg-base-100", "text-base-content/70")
    event.currentTarget.classList.add("ring-2", "ring-primary/40", "bg-primary/10", "text-primary")

    if (this.hasNameIdSelectTarget) {
      this.nameIdSelectTarget.value = cfg.nameId
      this.nameIdSelectTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }

    if (this.hasEmailHintTarget) {
      this.emailHintTarget.textContent = cfg.note
    }
  }

  // Lightweight client-side validation to give instant feedback. The server
  // still parses with OpenSSL and returns structured errors -- this is just
  // "you're in the ballpark".
  checkCert() {
    if (!this.hasCertAreaTarget || !this.hasCertStatusTarget) return
    const value = (this.certAreaTarget.value || "").trim()
    const status = this.certStatusTarget

    // Clear existing children safely (no innerHTML).
    while (status.firstChild) status.removeChild(status.firstChild)

    if (value.length === 0) {
      status.className = "text-xs text-base-content/40"
      status.appendChild(document.createTextNode("Waiting for certificate paste…"))
      return
    }

    const hasBegin = value.includes("-----BEGIN CERTIFICATE-----")
    const hasEnd = value.includes("-----END CERTIFICATE-----")

    if (hasBegin && hasEnd) {
      status.className = "text-xs text-success"
      const icon = document.createElement("i")
      icon.className = "fa-solid fa-circle-check mr-1"
      status.appendChild(icon)
      status.appendChild(document.createTextNode(" PEM markers detected. Server will verify the x509 contents on save."))
    } else {
      status.className = "text-xs text-warning"
      const icon = document.createElement("i")
      icon.className = "fa-solid fa-triangle-exclamation mr-1"
      status.appendChild(icon)
      status.appendChild(document.createTextNode(" Missing BEGIN/END markers. Paste the entire PEM block including the header and footer lines."))
    }
  }

  checkEnforce() {
    if (!this.hasEnforceInputTarget || !this.hasEnforceWarningTarget) return
    const on = this.enforceInputTarget.checked
    this.enforceWarningTarget.classList.toggle("hidden", !on)
  }
}
