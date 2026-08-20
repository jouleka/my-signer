module AppStoreConnect
  class Builds
    def initialize(client)
      @client = client
    end

    def list(app_id:, limit: 50, &block)
      @client.paginate("builds", params: {
        "filter[app]" => app_id,
        limit: limit,
        include: "preReleaseVersion"  # Include marketing version
      }, &block)
    end
  end
end
