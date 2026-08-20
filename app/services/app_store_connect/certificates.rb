module AppStoreConnect
  class Certificates
    def initialize(client)
      @client = client
    end

    def list(limit: 50, &block)
      @client.paginate("certificates", params: { limit: limit }, &block)
    end
  end
end
