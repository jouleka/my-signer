module GooglePlay
  class Tracks
    def initialize(client)
      @client = client
    end

    def list(package_name)
      edit = @client.create_edit(package_name)
      resp = @client.list_tracks(package_name, edit.id)
      @client.commit_edit(package_name, edit.id)
      resp.tracks || []
    end
  end
end
