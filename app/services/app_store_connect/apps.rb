module AppStoreConnect
  class Apps
    def initialize(client)
      @client = client
    end

    def list(limit: 50, &block)
      @client.paginate("apps", params: { limit: limit }, &block)
    end
  end
end
