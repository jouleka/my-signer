module AppStoreConnect
  class MerchantIds
    def initialize(client)
      @client = client
    end

    def list(limit: 200, &block)
      @client.paginate("merchantIds", params: { limit: limit }, &block)
    end

    def get(merchant_id)
      @client.get("merchantIds/#{merchant_id}")
    end

    # Create a new Merchant ID
    # identifier: string (e.g., "merchant.com.example.app")
    # name: string (optional, defaults to identifier)
    def create(identifier:, name: nil)
      payload = {
        data: {
          type: "merchantIds",
          attributes: {
            identifier: identifier,
            name: name || identifier
          }
        }
      }
      @client.post("merchantIds", json: payload)
    end

    # Delete a Merchant ID
    def delete(merchant_id)
      @client.delete("merchantIds/#{merchant_id}")
    end
  end
end
