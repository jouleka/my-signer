import { application } from "controllers/application"
import UpgradeGateController from "controllers/upgrade_gate_controller"
import UpgradePromptController from "controllers/upgrade_prompt_controller"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"

// Load confirm dialog eagerly so Turbo.config.forms.confirm is installed before any form renders
import "controllers/confirm_dialog_controller"

application.register("upgrade-gate", UpgradeGateController)
application.register("upgrade-prompt", UpgradePromptController)

lazyLoadControllersFrom("controllers", application)
