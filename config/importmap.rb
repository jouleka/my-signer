# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers", preload: false
pin "jszip", to: "jszip.min.js", preload: false
pin "lib/font_loader", to: "lib/font_loader.js", preload: false
pin "lib/paddle_loader", to: "lib/paddle_loader.js", preload: false
pin "lib/screenshot/caption_renderer", to: "lib/screenshot/caption_renderer.js", preload: false
pin "lib/screenshot/frame_renderer", to: "lib/screenshot/frame_renderer.js", preload: false
pin "lib/screenshot/history_manager", to: "lib/screenshot/history_manager.js", preload: false
pin "lib/screenshot/emoji_utils", to: "lib/screenshot/emoji_utils.js", preload: false
pin "lib/screenshot/sticker_renderer", to: "lib/screenshot/sticker_renderer.js", preload: false
pin "lib/screenshot/sticker_image_cache", to: "lib/screenshot/sticker_image_cache.js", preload: false
pin "lib/screenshot/sticker_interaction", to: "lib/screenshot/sticker_interaction.js", preload: false
pin "lib/screenshot/mesh_gradient_renderer", to: "lib/screenshot/mesh_gradient_renderer.js", preload: false
pin "lib/screenshot/pattern_renderer", to: "lib/screenshot/pattern_renderer.js", preload: false
pin "lib/screenshot/perspective_renderer", to: "lib/screenshot/perspective_renderer.js", preload: false
pin "lib/screenshot/custom_image_cache", to: "lib/screenshot/custom_image_cache.js", preload: false
pin "lib/screenshot/text_compliance_checker", to: "lib/screenshot/text_compliance_checker.js", preload: false
pin "lib/screenshot/dark_mode_transform", to: "lib/screenshot/dark_mode_transform.js", preload: false
pin "chart.js/auto", to: "https://cdn.jsdelivr.net/npm/chart.js@4.4.7/auto/+esm", preload: false
