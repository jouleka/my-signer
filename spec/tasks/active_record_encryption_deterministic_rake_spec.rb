require "rails_helper"
require "rake"

# Coverage for the active_record_encryption:rotate_deterministic_keyring task
# (follow-up to mysigner-33). The task re-encrypts every deterministic AR
# column under the current deterministic key. Unlike the primary-key sibling,
# this task spans three models and (for AppleAdsCredential) two columns on a
# single row. The spec verifies the iteration semantics, the multi-column
# atomic save, blank handling, idempotency, transactional safety, and the
# downstream properties operators rely on (find_by works, unique indexes
# stay enforced).
RSpec.describe "active_record_encryption rotate_deterministic_keyring rake task" do
  before(:all) do
    @previous_rake = Rake.application
    Rake.application = Rake::Application.new
    # `load` instead of `Rake.application.rake_require` — rake_require
    # mutates $LOADED_FEATURES, which prevents the sibling
    # active_record_encryption_rake_spec.rb (which also resets
    # Rake.application and calls rake_require) from re-registering the
    # tasks in its own fresh Rake.application. `load` redefines tasks
    # on whatever Rake.application is current at call time without
    # polluting the loaded-files set.
    load Rails.root.join("lib/tasks/active_record_encryption.rake").to_s
    Rake::Task.define_task(:environment)
  end

  after(:all) do
    Rake.application = @previous_rake
  end

  after do
    Rake::Task["active_record_encryption:rotate_deterministic_keyring"].reenable
  end

  let(:organization) { create(:organization) }

  let(:service_account_json) do
    {
      type: "service_account",
      project_id: "det-rotate-#{SecureRandom.hex(2)}",
      private_key: "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n",
      client_email: "det@example.iam.gserviceaccount.com",
      client_id: "det-client-id"
    }.to_json
  end

  def make_asc(key_id:)
    create(:app_store_connect_credential, organization: organization, key_id: key_id)
  end

  def make_apple_ads(client_id:, team_id:)
    create(:apple_ads_credential, organization: organization, client_id: client_id, team_id: team_id)
  end

  def make_google_play(developer_account_id:)
    create(:google_play_credential,
           organization: organization,
           developer_account_id: developer_account_id,
           service_account_json: service_account_json)
  end

  it "preserves every deterministic plaintext across all three models" do
    # WHY: the operator's contract — after rotation, every row's deterministic
    # columns must still decrypt to their original values. Multi-model
    # coverage in one test because the task processes all targets in a single
    # invocation; splitting per-model would mask cross-model regressions.
    asc = make_asc(key_id: "ROUND123")
    ads = make_apple_ads(client_id: "CLIENT-ROUND", team_id: "TEAM-RND")
    gp  = make_google_play(developer_account_id: "DEV-ROUND")

    Rake::Task["active_record_encryption:rotate_deterministic_keyring"].invoke

    expect(asc.reload.key_id).to eq("ROUND123")
    expect(ads.reload.client_id).to eq("CLIENT-ROUND")
    expect(ads.team_id).to eq("TEAM-RND")
    expect(gp.reload.developer_account_id).to eq("DEV-ROUND")
  end

  it "skips a GooglePlayCredential whose developer_account_id is blank" do
    # WHY: developer_account_id is the only optional deterministic column.
    # A row with it blank has nothing to re-encrypt; a wasted nil-roundtrip
    # would risk tripping the unique partial index if a sibling row already
    # has nil — and the printed "skipped" line is what operators look at to
    # confirm the run was clean.
    gp = create(:google_play_credential,
                organization: organization,
                developer_account_id: nil,
                service_account_json: service_account_json)

    output = capture_stdout do
      Rake::Task["active_record_encryption:rotate_deterministic_keyring"].invoke
    end

    expect(output).to include("skipped GooglePlayCredential##{gp.id}")
    expect(output).to include("no deterministic columns set")
    expect(gp.reload.developer_account_id).to be_nil
  end

  it "succeeds with zero rows when no records exist in any target model" do
    # WHY: an operator may rotate against a fresh staging environment with
    # no credentials yet. Must not blow up; must print the zero totals.
    expect(AppStoreConnectCredential.count).to eq(0)
    expect(AppleAdsCredential.count).to eq(0)
    expect(GooglePlayCredential.count).to eq(0)

    output = capture_stdout do
      Rake::Task["active_record_encryption:rotate_deterministic_keyring"].invoke
    end

    expect(output).to include("total: processed=0 succeeded=0 skipped=0")
  end

  it "is idempotent — re-running keeps the data readable" do
    # WHY: an operator may re-run the task (e.g. after a partial failure and
    # a fix). Two consecutive runs against the same data must leave the data
    # decryptable; a second nil-roundtrip-and-save MUST NOT lose plaintext.
    asc = make_asc(key_id: "IDEMP123")
    ads = make_apple_ads(client_id: "CLIENT-I", team_id: "TEAM-I")
    gp  = make_google_play(developer_account_id: "DEV-IDEMP")

    Rake::Task["active_record_encryption:rotate_deterministic_keyring"].invoke
    Rake::Task["active_record_encryption:rotate_deterministic_keyring"].reenable
    Rake::Task["active_record_encryption:rotate_deterministic_keyring"].invoke

    expect(asc.reload.key_id).to eq("IDEMP123")
    expect(ads.reload.client_id).to eq("CLIENT-I")
    expect(ads.team_id).to eq("TEAM-I")
    expect(gp.reload.developer_account_id).to eq("DEV-IDEMP")
  end

  it "rolls back the multi-column nil-roundtrip if save! raises (no data loss)" do
    # WHY: the riskiest moment in rotation — between the update_columns nil
    # write and the save!, the row is in a vulnerable state. For
    # AppleAdsCredential BOTH client_id AND team_id are nilled in one call,
    # so a mid-step raise without the transaction would null TWO columns at
    # once. Verify the transaction rolls both back.
    ads = make_apple_ads(client_id: "CLIENT-RB", team_id: "TEAM-RB")
    original_client_ct = ads.reload[:client_id]
    original_team_ct   = ads[:team_id]
    expect(original_client_ct).to be_present
    expect(original_team_ct).to be_present

    ads_double = AppleAdsCredential.find(ads.id)
    allow(AppleAdsCredential).to receive(:find_each).and_yield(ads_double)
    allow(ads_double).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(ads_double))

    expect {
      Rake::Task["active_record_encryption:rotate_deterministic_keyring"].invoke
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(ads.reload[:client_id]).to eq(original_client_ct)
    expect(ads[:team_id]).to eq(original_team_ct)
  end

  it "writes every deterministic column on a multi-column model in one save" do
    # WHY: AppleAdsCredential has client_id AND team_id as deterministic. The
    # task MUST nil and re-save both in a single update_columns + save! pair.
    # If it split them into two saves, the row would briefly sit with one
    # column wrapped under the new key and one under the old — a state that
    # breaks any uniqueness assumption that spans both columns and that an
    # observer mid-rotation would see as half-rotated.
    ads = make_apple_ads(client_id: "CLIENT-ATOM", team_id: "TEAM-ATOM")

    ads_double = AppleAdsCredential.find(ads.id)
    allow(AppleAdsCredential).to receive(:find_each).and_yield(ads_double)
    expect(ads_double).to receive(:update_columns).with(client_id: nil, team_id: nil).and_call_original.ordered
    expect(ads_double).to receive(:save!).with(validate: false).and_call_original.ordered

    Rake::Task["active_record_encryption:rotate_deterministic_keyring"].invoke
  end

  it "leaves deterministic columns findable by their plaintext via find_by after rotation" do
    # WHY: the whole point of deterministic encryption is "same plaintext →
    # same ciphertext", which lets Rails translate `find_by(col: plaintext)`
    # into an equality scan on ciphertext. If the rotation broke that
    # property (e.g. by writing under a different key than the current one
    # mid-loop), the lookup below would return nil.
    gp = make_google_play(developer_account_id: "FIND-ME-9001")

    Rake::Task["active_record_encryption:rotate_deterministic_keyring"].invoke

    expect(GooglePlayCredential.find_by(developer_account_id: "FIND-ME-9001")).to eq(gp)
  end

  it "preserves the unique (organization_id, developer_account_id) index after rotation" do
    # WHY: idx_unique_gp_dev_acc_per_org is a Postgres unique partial index
    # over the deterministic ciphertext. If rotation produced a different
    # ciphertext for the same plaintext under the active key, the index
    # would no longer enforce uniqueness over the underlying plaintext.
    # Verify directly by attempting a duplicate insert after rotation.
    make_google_play(developer_account_id: "UNIQ-VAL-42")

    Rake::Task["active_record_encryption:rotate_deterministic_keyring"].invoke

    expect {
      GooglePlayCredential.create!(
        organization: organization,
        name: "GP duplicate",
        developer_account_id: "UNIQ-VAL-42",
        service_account_json: service_account_json,
        active: true
      )
    }.to raise_error(ActiveRecord::RecordInvalid, /already been taken|has already/i)
  end

  private

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
