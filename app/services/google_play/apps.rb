module GooglePlay
  class Apps
    def initialize(client)
      @client = client
    end

    # Placeholder: Android Publisher API does not expose a direct "list all apps" without account context.
    # Typically you know package names. We keep this for future expansion or if developer account API allows it.
    def get(package_name)
      edit = @client.create_edit(package_name)
      @client.commit_edit(package_name, edit.id)
      { "package_name" => package_name }
    end
  end
end
