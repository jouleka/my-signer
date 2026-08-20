module AppStoreConnect
  class Devices
    def initialize(client)
      @client = client
    end

    def list(limit: 50, &block)
      @client.paginate("devices", params: { limit: limit }, &block)
    end

    # name: string, platform: "IOS"|"MAC_OS"|"TV_OS", udid: string
    def register(name:, platform:, udid:)
      payload = {
        data: {
          type: "devices",
          attributes: { name: name, platform: platform, udid: udid }
        }
      }
      @client.post("devices", json: payload)
    end

    # Rename a device
    # device_id: the App Store Connect remote ID
    # name: new device name
    def update(device_id:, name:)
      payload = {
        data: {
          type: "devices",
          id: device_id,
          attributes: { name: name }
        }
      }
      @client.patch("devices/#{device_id}", json: payload)
    end
  end
end
