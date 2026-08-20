require "test_helper"

class ApiAuthAfterSoftDeleteTest < ActionDispatch::IntegrationTest
  def make_user(**overrides)
    user = User.new({
      email: "u-#{SecureRandom.hex(6)}@example.test",
      password: "Password123!",
      accepts_terms: "1"
    }.merge(overrides))
    user.skip_confirmation!
    user.save!
    user
  end

  test "API status endpoint accepts an active token" do
    user  = make_user
    org   = Organization.create!(name: "Org #{SecureRandom.hex(4)}", owner: user)
    _, plain = ApiToken.generate_for(user: user, organization: org, name: "t1")

    get "/api/v1/status", headers: { "Authorization" => "Bearer #{plain}" }
    assert_response :success
  end

  test "API status endpoint REJECTS the same token after the user is soft-deleted" do
    user  = make_user
    org   = Organization.create!(name: "Org #{SecureRandom.hex(4)}", owner: user)
    _, plain = ApiToken.generate_for(user: user, organization: org, name: "t1")

    user.soft_delete!

    get "/api/v1/status", headers: { "Authorization" => "Bearer #{plain}" }
    assert_response :unauthorized,
      "API auth must reject CLI tokens belonging to a soft-deleted user"
  end
end
