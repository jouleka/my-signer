require "rails_helper"

# End-to-end coverage for config/initializers/auth_failure_audit.rb. Hits
# /users/sign_in with a wrong password and asserts that:
#   - one audit event is written per owned org for the first failed attempt
#   - subsequent failures within 60s for the same email+ip are deduped (no
#     additional audit rows), bounding write-amplification
#
# Test env Rails.cache defaults to NullStore, which would make the dedup a
# no-op. We swap in an in-process MemoryStore for these specs to exercise
# the real production behavior. Existing initializer tests (none currently)
# remain unaffected because cache_store is restored after each example.
RSpec.describe "Auth failure audit dedup", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) do
    User.create!(
      email: "owner-auth-fail@example.com",
      password: "SecurePassword123!",
      confirmed_at: Time.current,
      plan_tier: :team  # Team plan allows owning multiple orgs (Free caps at 1)
    )
  end
  let!(:org_one) { Organization.create!(name: "Org One", owner: owner) }
  let!(:org_two) { Organization.create!(name: "Org Two", owner: owner) }

  before do
    # Stub a real backend so the dedup actually fires; the production code
    # uses Rails.cache.read/write to gate the audit fan-out. Test env uses
    # NullStore by default, which would make the dedup a no-op. The stub is
    # per-example; RSpec resets it in `after` so other specs are unaffected.
    #
    # Note: this stub does NOT redirect Rack::Attack's cache, which captured
    # the original NullStore reference at boot in
    # config/initializers/rack_attack.rb. So the throttle remains a no-op
    # across these examples -- which is what we want, since we're testing
    # the audit-write dedup, not the request-level throttle.
    memory_store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(memory_store)
  end

  def post_failed_login(email:)
    post user_session_path, params: { user: { email: email, password: "WRONG-PASSWORD!" } }
  end

  it "writes one sign_in_failed audit event per owned org on the first failed attempt" do
    expect { post_failed_login(email: owner.email) }
      .to change { AuditEvent.where(action: "sign_in_failed").count }.by(2)

    events = AuditEvent.where(action: "sign_in_failed").order(:created_at)
    expect(events.map(&:organization_id)).to match_array([ org_one.id, org_two.id ])
    expect(events.map(&:actor_id).uniq).to eq([ owner.id ])
    expect(events.first.metadata["email_domain"]).to eq("example.com")
  end

  it "dedups a second failed attempt for the same email+ip within 60 seconds" do
    post_failed_login(email: owner.email)
    initial_count = AuditEvent.where(action: "sign_in_failed").count
    expect(initial_count).to eq(2)  # one per owned org

    # Second attempt within the dedup window: must NOT add more audit rows.
    expect { post_failed_login(email: owner.email) }
      .not_to change { AuditEvent.where(action: "sign_in_failed").count }
  end

  it "writes again once the dedup window (60s) actually expires" do
    post_failed_login(email: owner.email)
    expect(AuditEvent.where(action: "sign_in_failed").count).to eq(2)

    # Use ActiveSupport's travel_to to advance time past the 60s expires_in.
    # This exercises the *real* TTL semantics of MemoryStore -- a typo of
    # `expires_in: 60.minutes` instead of `60.seconds` would make this test
    # fail, where Rails.cache.clear would still pass.
    travel_to(61.seconds.from_now) do
      expect { post_failed_login(email: owner.email) }
        .to change { AuditEvent.where(action: "sign_in_failed").count }.by(2)
    end
  end

  it "does NOT dedup across different emails (key includes the email)" do
    # Different email same IP must NOT collide. If the dedup key ever drops
    # the email, both attempts would coalesce and a brute-force across many
    # accounts from one IP would silently lose audit coverage.
    other = User.create!(
      email: "second-owner@example.com",
      password: "SecurePassword123!",
      confirmed_at: Time.current,
      plan_tier: :team
    )
    Organization.create!(name: "Second Owner Org", owner: other)

    post_failed_login(email: owner.email)         # 2 events (org_one, org_two)
    expect(AuditEvent.where(action: "sign_in_failed").count).to eq(2)

    expect { post_failed_login(email: other.email) }
      .to change { AuditEvent.where(action: "sign_in_failed").count }.by(1)
  end

  it "no-ops when the submitted email does not match a user (privacy: don't leak existence)" do
    expect { post_failed_login(email: "nobody-here@example.com") }
      .not_to change { AuditEvent.where(action: "sign_in_failed").count }
  end
end
