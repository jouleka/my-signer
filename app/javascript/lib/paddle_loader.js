let loadPromise
let initializedKey
const listeners = new Set()

function scriptLoaded() {
  return typeof window !== "undefined" && typeof window.Paddle !== "undefined"
}

function loadScript() {
  if (scriptLoaded()) return Promise.resolve(window.Paddle)
  if (loadPromise) return loadPromise

  loadPromise = new Promise((resolve, reject) => {
    const existing = document.querySelector('script[data-paddle-loader="true"]')
    if (existing) {
      existing.addEventListener("load", () => resolve(window.Paddle), { once: true })
      existing.addEventListener("error", () => reject(new Error("Unable to load Paddle.js")), { once: true })
      return
    }

    const script = document.createElement("script")
    script.src = "https://cdn.paddle.com/paddle/v2/paddle.js"
    script.async = true
    script.dataset.paddleLoader = "true"
    script.onload = () => resolve(window.Paddle)
    script.onerror = () => reject(new Error("Unable to load Paddle.js"))
    document.head.appendChild(script)
  })

  return loadPromise
}

export async function ensurePaddle({ token, environment, defaultTheme }) {
  const Paddle = await loadScript()
  const currentKey = `${environment}:${token}`

  if (initializedKey !== currentKey) {
    if (environment === "sandbox") {
      Paddle.Environment.set("sandbox")
    }

    // Set checkout-wide defaults at Initialize. Paddle's per-checkout
    // `settings.theme` override is sometimes ignored if Paddle has already
    // cached defaults from a prior page, so we pin the theme here too.
    // Default to dark (the app's default) if the caller didn't pass one.
    Paddle.Initialize({
      token,
      checkout: {
        settings: {
          theme: defaultTheme || "dark"
        }
      },
      eventCallback: event => {
        listeners.forEach(listener => listener(event))
      }
    })

    initializedKey = currentKey
  }

  return Paddle
}

export function subscribeToPaddleEvents(listener) {
  listeners.add(listener)

  return () => {
    listeners.delete(listener)
  }
}
