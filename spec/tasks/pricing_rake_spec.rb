require "rails_helper"
require "rake"

RSpec.describe "pricing rake tasks" do
  before(:all) do
    @previous_rake = Rake.application
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/pricing", [ Rails.root.join("lib").to_s ])
    Rake::Task.define_task(:environment)
  end

  after(:all) do
    Rake.application = @previous_rake
  end

  after do
    Rake::Task["pricing:assign_plan"].reenable
    Rake::Task["pricing:audit_over_limit"].reenable
  end

  it "assigns a plan to the requested user" do
    user = create(:user)

    expect {
      Rake::Task["pricing:assign_plan"].invoke(user.email, "team")
    }.to output("Assigned team plan to #{user.email}\n").to_stdout

    expect(user.reload.plan_tier).to eq("team")
  end

  it "prints owners and organizations that exceed their limits" do
    owner = create(:user, :team_plan, email: "audit@example.com")
    create(:organization, owner: owner, name: "Audit One")
    create(:organization, owner: owner, name: "Audit Two")
    over_limit_org = owner.owned_organizations.first
    over_limit_org.memberships.create!(user: create(:user, email: "member@example.com"), role: :developer)
    owner.update!(plan_tier: :free)

    output = capture_stdout do
      Rake::Task["pricing:audit_over_limit"].invoke
    end

    expect(output).to include("Owners over limit:")
    expect(output).to include("audit@example.com")
    expect(output).to include("Organizations over limit:")
    expect(output).to include(over_limit_org.name)
  end

  def capture_stdout
    original_stdout = $stdout
    fake_stdout = StringIO.new
    $stdout = fake_stdout
    yield
    fake_stdout.string
  ensure
    $stdout = original_stdout
  end
end
