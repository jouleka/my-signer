module GooglePlay
  class Uploader
    def initialize(client)
      @client = client
    end

    # Returns uploaded bundle object
    def upload_aab!(package_name:, aab_path:)
      edit = @client.create_edit(package_name)
      bundle = @client.upload_aab(package_name, edit.id, aab_path)
      @client.commit_edit(package_name, edit.id)
      bundle
    end

    # Assign a version code to a track with release notes
    def assign_to_track!(package_name:, edit_id:, track:, releases: [])
      @client.update_track(package_name, edit_id, track, releases: releases)
    end
  end
end
