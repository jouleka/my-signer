import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "input",
    "error",
    "hint",
    "requirement",
    "summary",
    "matchMessage",
    "submit"
  ]

  static values = {
    field: String,
    minPasswordLength: { type: Number, default: 12 },
    emailValue: String
  }

  connect() {
    this.touchedFields = new Set()
    this.passwordTouched = false
    this.confirmationTouched = false
    this.currentPasswordTouched = false

    this.passwordValid = false
    this.confirmationValid = false
    this.currentPasswordValid = false

    this.inputTargets.forEach((input) => {
      const wrapper = this.findInputWrapper(input)
      if (wrapper?.classList.contains("input-error")) {
        const field = this.fieldFor(input)
        this.markTouchedField(field)
        this.touchedFields.add(input)
        if (input.value) {
          this.validate(input)
        }
      }
    })

    if (this.passwordInput && !this.touchedFields.has(this.passwordInput)) {
      this.handlePasswordRequirements(this.passwordInput, this.passwordInput.value || "", [])
    }

    if (this.passwordConfirmationInput && !this.touchedFields.has(this.passwordConfirmationInput)) {
      this.handlePasswordConfirmation(this.passwordConfirmationInput, this.passwordConfirmationInput.value || "", [])
    }

    if (this.currentPasswordInput && !this.touchedFields.has(this.currentPasswordInput)) {
      this.handleCurrentPassword(this.currentPasswordInput, this.currentPasswordInput.value || "", [])
    }

    this.updateSubmitState()
  }

  validate(eventOrInput) {
    const input = eventOrInput.target || eventOrInput
    const field = this.fieldFor(input)
    if (!field) return

    const rawValue = input.value || ""
    const value = field === "password" ? rawValue : rawValue.trim()

    this.touchedFields.add(input)
    this.markTouchedField(field)

    const errors = []

    switch (field) {
      case "email":
        errors.push(...this.validateEmail(value, input))
        break
      case "password":
        errors.push(...this.validatePassword(rawValue, input))
        break
      case "password_confirmation":
        errors.push(...this.validatePasswordConfirmation(rawValue, input))
        break
      case "current_password":
        if (this.touchedFields.has(input) && !rawValue) {
          errors.push("can't be blank")
        }
        break
    }

    this.showErrors(input, errors)
    this.afterValidate(field, input, rawValue, errors)
  }

  afterValidate(field, input, rawValue, errors) {
    switch (field) {
      case "password":
        this.handlePasswordRequirements(input, rawValue, errors)
        break
      case "password_confirmation":
        this.handlePasswordConfirmation(input, rawValue, errors)
        break
      case "current_password":
        this.handleCurrentPassword(input, rawValue, errors)
        break
    }

    this.updateSubmitState()
  }

  validateEmail(value, input) {
    const errors = []
    if (!value && this.touchedFields.has(input)) {
      errors.push("can't be blank")
    } else if (value && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
      errors.push("is invalid")
    }
    return errors
  }

  validatePassword(value, input) {
    const errors = []

    if (!value) {
      if (this.touchedFields.has(input)) {
        errors.push("can't be blank")
      }
      return errors
    }

    if (!this.usesPasswordChecklist()) {
      if (value.length < this.minPasswordLengthValue) {
        errors.push(`is too short (minimum is ${this.minPasswordLengthValue} characters)`)
      }

      const rules = {
        lowercase: /[a-z]/,
        uppercase: /[A-Z]/,
        digit: /\d/,
        symbol: /[^A-Za-z0-9]/
      }

      const ruleNames = {
        lowercase: "lowercase",
        uppercase: "uppercase",
        digit: "digit",
        symbol: "symbol"
      }

      Object.entries(rules).forEach(([name, regex]) => {
        if (!value.match(regex)) {
          errors.push(`must include at least one ${ruleNames[name]} character`)
        }
      })
    }

    return errors
  }

  validatePasswordConfirmation(value, input) {
    const errors = []

    const passwordInput = this.passwordInput || this.element.querySelector('input[name*="[password]"]:not([name*="confirmation"]):not([name*="current"])')
    const isOptional = passwordInput && !passwordInput.value && input.closest('form')?.action?.includes('registration') && input.closest('form')?.method === 'put'

    if (!value && !isOptional) {
      if (this.touchedFields.has(input)) {
        errors.push("can't be blank")
      }
      return errors
    }

    if (isOptional && !passwordInput.value) {
      return errors
    }

    if (passwordInput && passwordInput.value && value && passwordInput.value !== value) {
      if (!this.hasMatchMessageTarget) {
        errors.push("doesn't match Password")
      }
    }

    return errors
  }

  showErrors(input, errors) {
    const formControl = input.closest('.form-control')
    if (!formControl) return

    const errorContainer = formControl.querySelector('.validator-error')
    const errorText = errorContainer?.querySelector('span')
    const hintContainer = formControl.querySelector('.validator-hint')
    const inputWrapper = this.findInputWrapper(input)

    if (errors.length > 0) {
      inputWrapper?.classList.add('input-error', 'border-error')
      inputWrapper?.classList.remove('border-base-300')

      if (errorContainer && errorText) {
        errorText.textContent = errors[0]
        errorContainer.classList.remove('hidden')
        errorContainer.classList.add('flex')
      }

      if (hintContainer) {
        hintContainer.classList.add('hidden')
      }
    } else {
      inputWrapper?.classList.remove('input-error', 'border-error')
      inputWrapper?.classList.add('border-base-300')

      if (errorContainer) {
        errorContainer.classList.add('hidden')
        errorContainer.classList.remove('flex')
      }

      if (hintContainer) {
        hintContainer.classList.remove('hidden')
      }
    }
  }

  input(event) {
    const input = event.currentTarget
    this.validate(input)

    if (
      input.dataset.field === 'password' ||
      (input.name?.includes('[password]') && !input.name?.includes('confirmation') && !input.name?.includes('current'))
    ) {
      const passwordConfirmationInput = this.element.querySelector('input[name*="[password_confirmation]"]')
      if (passwordConfirmationInput && passwordConfirmationInput.value) {
        this.validate(passwordConfirmationInput)
      }
    }
  }

  blur(event) {
    this.validate(event.currentTarget)
  }

  handlePasswordRequirements(input, value, errors) {
    if (!input) return

    const hasChecklist = this.usesPasswordChecklist()
    const states = this.computeRequirementStates(value)
    const totalRequirements = hasChecklist ? this.requirementTargets.length : 0
    let satisfiedCount = 0

    if (hasChecklist) {
      const highlight = this.passwordTouched && value.length > 0
      this.requirementTargets.forEach((element) => {
        const rule = element.dataset.rule
        if (!rule) return
        const satisfied = states[rule] ?? false
        if (satisfied) satisfiedCount += 1
        this.decorateRequirement(element, satisfied, highlight)
      })
      this.updateSummary(value, satisfiedCount, totalRequirements)
    }

    const allRequirementsMet = hasChecklist ? states.all : errors.length === 0
    const hasValue = value.length > 0

    if (!this.passwordTouched && this.touchedFields.has(input)) {
      this.passwordTouched = true
    }

    if (hasChecklist) {
      const shouldHighlight = this.passwordTouched && (hasValue || errors.length > 0)
      const shouldBeValid = hasValue && allRequirementsMet && errors.length === 0
      this.setInputValidity(input, shouldBeValid || (!shouldHighlight && !hasValue))
      this.passwordValid = shouldBeValid
    } else {
      this.passwordValid = hasValue && errors.length === 0
    }
  }

  handlePasswordConfirmation(input, value, errors) {
    if (!input) return

    const passwordValue = this.passwordInput ? this.passwordInput.value : ""
    const confirmationHasValue = value.length > 0
    const mismatch = confirmationHasValue && passwordValue && passwordValue !== value

    if (!this.confirmationTouched && this.touchedFields.has(input)) {
      this.confirmationTouched = true
    }

    const showMismatchMessage = mismatch || (errors.length > 0 && errors[0]?.toLowerCase().includes('match'))

    if (this.hasMatchMessageTarget) {
      const defaultMessage = this.matchMessageTarget.dataset.defaultMessage || "Must match new password"
      const serverMessage = errors.find((message) => message.toLowerCase().includes('match'))
      const messageToShow = serverMessage || defaultMessage

      if (showMismatchMessage) {
        this.matchMessageTarget.textContent = messageToShow
        this.matchMessageTarget.classList.remove('hidden')
      } else {
        this.matchMessageTarget.textContent = defaultMessage
        this.matchMessageTarget.classList.add('hidden')
      }
    }

    const shouldHighlight = this.confirmationTouched && (confirmationHasValue || errors.length > 0)
    const isValid = confirmationHasValue && !mismatch && errors.length === 0

    this.setInputValidity(input, isValid || (!shouldHighlight && !confirmationHasValue))
    this.confirmationValid = isValid
  }

  handleCurrentPassword(input, value, errors) {
    if (!input) return

    if (!this.currentPasswordTouched && this.touchedFields.has(input)) {
      this.currentPasswordTouched = true
    }

    const hasValue = value.length > 0
    const shouldHighlight = this.currentPasswordTouched
    const isValid = hasValue && errors.length === 0

    this.setInputValidity(input, isValid || (!shouldHighlight && !hasValue))
    this.currentPasswordValid = isValid
  }

  updateSubmitState() {
    if (!this.hasSubmitTarget) return

    const passwordReady = this.passwordInput ? this.passwordValid : true
    const confirmationReady = this.passwordConfirmationInput ? this.confirmationValid : true
    const currentReady = this.currentPasswordInput ? this.currentPasswordValid : true

    const enable = passwordReady && confirmationReady && currentReady
    this.submitTarget.disabled = !enable
  }

  computeRequirementStates(value) {
    const minLength = this.minPasswordLengthValue || 12
    const identifier = this.emailIdentifier

    const states = {
      length: value.length >= minLength,
      uppercase: /[A-Z]/.test(value),
      lowercase: /[a-z]/.test(value),
      digit: /\d/.test(value),
      symbol: /[^A-Za-z0-9]/.test(value),
      email: identifier ? !value.toLowerCase().includes(identifier) : true
    }

    states.all = Object.values(states).every(Boolean)
    return states
  }

  decorateRequirement(element, satisfied, highlight) {
    const icon = element.querySelector('[data-role="icon"]')

    element.classList.remove('text-success', 'text-error', 'text-base-content/60')
    if (satisfied) {
      element.classList.add('text-success')
    } else if (highlight) {
      element.classList.add('text-error')
    } else {
      element.classList.add('text-base-content/60')
    }

    if (icon) {
      if (satisfied) {
        icon.className = 'fa-solid fa-circle-check text-success text-[10px]'
      } else if (highlight) {
        icon.className = 'fa-solid fa-circle-xmark text-error text-[10px]'
      } else {
        icon.className = 'fa-regular fa-circle text-base-content/40 text-[10px]'
      }
    }
  }

  updateSummary(value, satisfiedCount, total) {
    if (!this.hasSummaryTarget) return

    const summary = this.summaryTarget
    const baseClass = 'badge badge-xs'

    if (!value.length) {
      summary.textContent = 'Start typing'
      summary.className = `${baseClass} badge-ghost`
    } else if (satisfiedCount === total) {
      summary.textContent = 'Ready'
      summary.className = `${baseClass} badge-success`
    } else {
      summary.textContent = `${satisfiedCount}/${total} met`
      summary.className = `${baseClass} badge-warning`
    }
  }

  markTouchedField(field) {
    switch (field) {
      case 'password':
        this.passwordTouched = true
        break
      case 'password_confirmation':
        this.confirmationTouched = true
        break
      case 'current_password':
        this.currentPasswordTouched = true
        break
    }
  }

  setInputValidity(input, valid) {
    if (!input) return
    const wrapper = this.findInputWrapper(input)
    if (!wrapper) return

    if (valid) {
      wrapper.classList.remove('input-error', 'border-error')
    } else {
      wrapper.classList.add('input-error', 'border-error')
    }
  }

  findInputWrapper(input) {
    return input.closest('label.input') || input.closest('.input')
  }

  fieldFor(input) {
    return input.dataset.field || this.fieldValue || input.name?.match(/\[(\w+)\]/)?.[1]
  }

  usesPasswordChecklist() {
    return this.hasRequirementTarget
  }

  get passwordInput() {
    return this.inputTargets.find((input) => this.fieldFor(input) === 'password')
  }

  get passwordConfirmationInput() {
    return this.inputTargets.find((input) => this.fieldFor(input) === 'password_confirmation')
  }

  get currentPasswordInput() {
    return this.inputTargets.find((input) => this.fieldFor(input) === 'current_password')
  }

  get emailIdentifier() {
    if (!this.hasEmailValue || !this.emailValue) return ''
    const localPart = this.emailValue.split('@')[0]
    return localPart ? localPart.toLowerCase() : ''
  }
}

