module AppStoreConnect
  class Testflight
    def initialize(client)
      @client = client
    end

    def list(app_id:, limit: 200)
      # https://developer.apple.com/documentation/appstoreconnectapi/list_beta_groups
      path = "/v1/apps/#{app_id}/betaGroups"
      params = {
        limit: limit,
        fields: {
          betaGroups: "name,publicLinkEnabled,publicLink,isInternalGroup,createdDate,app,betaTesters"
        }
      }

      @client.paginate(path, params: params) do |body|
        yield body
      end
    end

    def list_testers(group_id:, limit: 200)
      # https://developer.apple.com/documentation/appstoreconnectapi/list_all_beta_testers_in_a_beta_group
      path = "/v1/betaGroups/#{group_id}/betaTesters"
      params = {
        limit: limit,
        fields: {
          betaTesters: "email,firstName,lastName,inviteType,state"
        }
      }

      @client.paginate(path, params: params) do |body|
        yield body
      end
    end
  end
end
