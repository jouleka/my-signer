module AppStoreConnect
  class BundleIds
    def initialize(client)
      @client = client
    end

    def list(limit: 50, &block)
      @client.paginate("bundleIds", params: { limit: limit }, &block)
    end

    # Get a specific bundle ID with capabilities
    def show(bundle_id_remote_id)
      @client.get("bundleIds/#{bundle_id_remote_id}", params: { include: "bundleIdCapabilities" })
    end

    # Register a new Bundle ID in App Store Connect
    # identifier: string (e.g., "com.example.app")
    # name: string (e.g., "Example App")
    # platform: "IOS"|"MAC_OS"|"UNIVERSAL"
    def register(identifier:, name:, platform: "IOS")
      payload = {
        data: {
          type: "bundleIds",
          attributes: {
            identifier: identifier,
            name: name,
            platform: platform
          }
        }
      }
      @client.post("bundleIds", json: payload)
    end

    # Delete a Bundle ID from App Store Connect.
    # Apple returns 409 Conflict if the bundle ID has dependent resources
    # (apps, profiles, or capabilities). Callers should surface that as a
    # "remove dependents first" error rather than a generic failure.
    def delete(bundle_id_remote_id)
      @client.delete("bundleIds/#{bundle_id_remote_id}")
    end

    # List capabilities for a bundle ID
    # Note: The bundleIdCapabilities endpoint does not support the 'limit' parameter
    def list_capabilities(bundle_id_remote_id:, &block)
      @client.paginate("bundleIds/#{bundle_id_remote_id}/bundleIdCapabilities", params: {}, &block)
    end

    # Enable a capability for a bundle ID
    # capability_type: string (e.g., "PUSH_NOTIFICATIONS", "ICLOUD", etc.)
    # settings: array of capability settings (optional, for capabilities that require configuration)
    def enable_capability(bundle_id_remote_id:, capability_type:, settings: nil)
      payload = {
        data: {
          type: "bundleIdCapabilities",
          attributes: {
            capabilityType: capability_type
          },
          relationships: {
            bundleId: {
              data: {
                type: "bundleIds",
                id: bundle_id_remote_id
              }
            }
          }
        }
      }

      # Add settings if provided (for capabilities like iCloud, Data Protection, etc.)
      if settings.present?
        payload[:data][:attributes][:settings] = settings
      end

      @client.post("bundleIdCapabilities", json: payload)
    end

    # Disable (delete) a capability
    def disable_capability(capability_remote_id:)
      @client.delete("bundleIdCapabilities/#{capability_remote_id}")
    end

    # Update capability settings
    def update_capability(capability_remote_id:, settings:)
      payload = {
        data: {
          type: "bundleIdCapabilities",
          id: capability_remote_id,
          attributes: {
            settings: settings
          }
        }
      }
      @client.patch("bundleIdCapabilities/#{capability_remote_id}", json: payload)
    end
  end
end
