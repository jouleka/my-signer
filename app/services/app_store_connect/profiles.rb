module AppStoreConnect
  class Profiles
    def initialize(client)
      @client = client
    end

    def list(limit: 50, &block)
      # Include bundleId relationship to get bundle ID data
      @client.paginate("profiles", params: { limit: limit, include: "bundleId" }, &block)
    end

    # Get a specific profile with all relationships (certificates, devices, bundleId)
    def show(profile_id)
      @client.get("profiles/#{profile_id}", params: { include: "bundleId,certificates,devices" })
    end

    # name: string
    # profileType: "IOS_APP_DEVELOPMENT"|"IOS_APP_STORE"|"IOS_APP_ADHOC"|"IOS_APP_INHOUSE"|... per Apple
    # bundle_id_id: the App Store Connect id for the bundleId
    # certificate_ids: array of certificate ids
    # device_ids: array of device ids (required for development/adhoc)
    def create(name:, profile_type:, bundle_id_id:, certificate_ids:, device_ids: [])
      relationships = {
        bundleId: { data: { type: "bundleIds", id: bundle_id_id } },
        certificates: { data: Array(certificate_ids).map { |id| { type: "certificates", id: id } } }
      }
      if device_ids.present?
        relationships[:devices] = { data: Array(device_ids).map { |id| { type: "devices", id: id } } }
      end
      payload = {
        data: {
          type: "profiles",
          attributes: {
            name: name,
            profileType: profile_type
          },
          relationships: relationships
        }
      }
      @client.post("profiles", json: payload)
    end

    # Delete a profile by its remote_id
    def delete(profile_id)
      @client.delete("profiles/#{profile_id}")
    end
  end
end
