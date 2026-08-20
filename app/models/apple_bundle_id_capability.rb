class AppleBundleIdCapability < ApplicationRecord
  belongs_to :apple_bundle_id

  CAPABILITY_TYPES = %w[
    ACCESS_WIFI_INFORMATION
    APP_ATTEST
    APP_GROUPS
    APPLE_ID_AUTH
    APPLE_PAY
    ASSOCIATED_DOMAINS
    AUTOFILL_CREDENTIAL_PROVIDER
    CLASSKIT
    COREMEDIA_HLS_LOW_LATENCY
    DATA_PROTECTION
    DEVICE_CHECK
    EXTENDED_VIRTUAL_ADDRESS_SPACE
    FAMILY_CONTROLS
    FILEPROVIDER_TESTINGMODE
    FONT_INSTALLATION
    GAME_CENTER
    GROUP_ACTIVITIES
    HEALTHKIT
    HEALTHKIT_ACCESS
    HEALTHKIT_RECALIBRATE_ESTIMATES
    HOMEKIT
    HOT_SPOT
    ICLOUD
    IN_APP_PURCHASE
    INTER_APP_AUDIO
    MAPS
    MULTIPATH
    NETWORK_EXTENSIONS
    NFC_TAG_READING
    PERSONAL_VPN
    PUSH_NOTIFICATIONS
    SIGN_IN_WITH_APPLE
    SIRIKIT
    SYSTEM_EXTENSION_INSTALL
    USER_MANAGEMENT
    WALLET
    WIRELESS_ACCESSORY_CONFIGURATION
  ].freeze

  validates :remote_id, presence: true
  validates :capability_type, presence: true, inclusion: { in: CAPABILITY_TYPES, allow_blank: true }
  validates :capability_type, uniqueness: { scope: :apple_bundle_id_id }

  scope :sorted, -> { order(:capability_type) }

  def display_name
    capability_type.to_s.titleize.gsub("Nfc", "NFC").gsub("Hls", "HLS")
  end

  def icon
    case capability_type
    when "PUSH_NOTIFICATIONS" then "fa-bell"
    when "ICLOUD" then "fa-cloud"
    when "APPLE_PAY", "WALLET" then "fa-wallet"
    when "SIGN_IN_WITH_APPLE", "APPLE_ID_AUTH" then "fa-right-to-bracket"
    when "GAME_CENTER" then "fa-gamepad"
    when "HEALTHKIT", "HEALTHKIT_ACCESS", "HEALTHKIT_RECALIBRATE_ESTIMATES" then "fa-heart-pulse"
    when "HOMEKIT" then "fa-house"
    when "SIRIKIT" then "fa-microphone"
    when "MAPS" then "fa-map"
    when "NFC_TAG_READING" then "fa-wifi"
    when "ASSOCIATED_DOMAINS" then "fa-link"
    when "APP_GROUPS" then "fa-layer-group"
    when "DATA_PROTECTION" then "fa-shield"
    when "IN_APP_PURCHASE" then "fa-cart-shopping"
    when "NETWORK_EXTENSIONS", "PERSONAL_VPN" then "fa-network-wired"
    when "ACCESS_WIFI_INFORMATION", "HOT_SPOT" then "fa-wifi"
    when "CLASSKIT" then "fa-graduation-cap"
    when "FAMILY_CONTROLS" then "fa-users"
    when "FONT_INSTALLATION" then "fa-font"
    when "DEVICE_CHECK", "APP_ATTEST" then "fa-check-circle"
    else "fa-puzzle-piece"
    end
  end
end
