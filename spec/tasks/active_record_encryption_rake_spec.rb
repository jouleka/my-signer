require "rails_helper"
require "rake"

# Coverage for the active_record_encryption:rotate_keyring task (mysigner-33).
# The task re-encrypts every SsoConfiguration#idp_cert under the current
# AR encryption primary key. The spec verifies iteration semantics, blank
# handling, idempotency, and the transactional safety of the nil-roundtrip
# (the only part of the task that could lose customer data if a failure
# fired between the two writes).
RSpec.describe "active_record_encryption rake tasks" do
  before(:all) do
    @previous_rake = Rake.application
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/active_record_encryption", [ Rails.root.join("lib").to_s ])
    Rake::Task.define_task(:environment)
  end

  after(:all) do
    Rake.application = @previous_rake
  end

  after do
    Rake::Task["active_record_encryption:rotate_keyring"].reenable
  end

  let(:owner) { create(:user, :team_plan, email: "rotate-owner-#{SecureRandom.hex(4)}@example.com") }
  let(:organization) { Organization.create!(name: "Rotate Org", owner: owner) }
  # SsoConfiguration#cert_format does a real OpenSSL::X509::Certificate.new
  # parse on the value, so the spec needs an actual self-signed cert. Cheap
  # to generate at let-time; doesn't need to chain to anything real because
  # we never validate the chain.
  let(:valid_pem) do
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new.tap do |c|
      c.version    = 2
      c.serial     = SecureRandom.random_number(2**64)
      c.subject    = OpenSSL::X509::Name.parse("/CN=rotate-spec.example.com")
      c.issuer     = c.subject
      c.public_key = key.public_key
      c.not_before = Time.now - 60
      c.not_after  = Time.now + 60 * 60 * 24
      c.sign(key, OpenSSL::Digest.new("SHA256"))
    end
    cert.to_pem
  end

  def build_sso_config(cert: valid_pem)
    SsoConfiguration.create!(
      organization: organization,
      idp_entity_id: "https://idp.example.com/saml/metadata",
      idp_sso_target_url: "https://idp.example.com/saml/sso",
      idp_cert: cert,
      enabled: true,
      enforced: false
    )
  end

  it "re-encrypts each SsoConfiguration#idp_cert by going through a nil-roundtrip and save" do
    # WHY: this is the core contract. Rails AR encryption only re-encrypts on
    # write. Assigning the same plaintext is a no-op (no dirty flag, no save).
    # The task forces a re-encrypt by writing nil to the underlying column
    # then re-assigning the original plaintext through the AR encryption
    # layer, which encrypts under the CURRENT primary key. Verify the task
    # actually does this — without it, a rotation deploy would leave data
    # still wrapped under the old (potentially leaked) key.
    sso = build_sso_config

    # Spy on the save and update_columns calls. The spec asserts the
    # specific contract: nil-roundtrip then save!.
    sso_double = SsoConfiguration.find(sso.id)
    allow(SsoConfiguration).to receive(:find_each).and_yield(sso_double)
    expect(sso_double).to receive(:update_columns).with(idp_cert: nil).and_call_original.ordered
    expect(sso_double).to receive(:save!).with(validate: false).and_call_original.ordered

    Rake::Task["active_record_encryption:rotate_keyring"].invoke
  end

  it "leaves the plaintext readable after the rotation completes" do
    # WHY: the operational property the operator cares about. After rotation,
    # every SsoConfiguration must still decrypt to its original idp_cert.
    # The nil-roundtrip is internal plumbing; if it's broken, decrypting
    # post-rotation would return nil or garbage.
    sso = build_sso_config(cert: valid_pem)
    original = sso.idp_cert
    expect(original).to be_present

    Rake::Task["active_record_encryption:rotate_keyring"].invoke

    expect(sso.reload.idp_cert).to eq(original)
  end

  it "skips rows whose idp_cert is blank (no nil-roundtrip on already-empty data)" do
    # WHY: an empty SsoConfiguration (idp_cert unset) has nothing to
    # re-encrypt. The task should not perform the nil-roundtrip — that
    # would be a wasted write — and definitely should not raise.
    sso = build_sso_config
    sso.update_columns(idp_cert: nil)

    sso_double = SsoConfiguration.find(sso.id)
    allow(SsoConfiguration).to receive(:find_each).and_yield(sso_double)
    expect(sso_double).not_to receive(:save!)
    expect(sso_double).not_to receive(:update_columns)

    output = capture_stdout do
      Rake::Task["active_record_encryption:rotate_keyring"].invoke
    end
    expect(output).to include("skipped SsoConfiguration##{sso.id}")
    expect(output).to include("idp_cert is blank")
  end

  it "succeeds with zero rows when there are no SsoConfigurations" do
    # WHY: the rotation task may be run by an operator on an environment that
    # has no SSO-configured orgs (e.g. staging, or before any customer has
    # set up SSO). Must not blow up — should report processed=0 and exit.
    expect(SsoConfiguration.count).to eq(0)

    output = capture_stdout do
      Rake::Task["active_record_encryption:rotate_keyring"].invoke
    end
    expect(output).to include("processed=0 succeeded=0 skipped=0")
  end

  it "is idempotent — re-running re-encrypts again without losing data" do
    # WHY: the operator might run the task twice (once before verifying the
    # *_PREVIOUS env var can be dropped, once again after). Each run must
    # leave the data readable.
    sso = build_sso_config
    original = sso.idp_cert

    Rake::Task["active_record_encryption:rotate_keyring"].invoke
    Rake::Task["active_record_encryption:rotate_keyring"].reenable
    Rake::Task["active_record_encryption:rotate_keyring"].invoke

    expect(sso.reload.idp_cert).to eq(original)
  end

  it "rolls back the nil-roundtrip if save! raises mid-task (no data loss)" do
    # WHY: the most important safety property. The nil-roundtrip is a
    # two-step write: first set idp_cert to nil, then re-assign + save!.
    # If anything between those steps raises (KMS down, validation failure,
    # disk full), without the transaction we'd be left with idp_cert=nil
    # in the DB — irreversible data loss. With the transaction, the nil
    # write rolls back and the original ciphertext is preserved.
    sso = build_sso_config
    original_encrypted_value = sso.reload[:idp_cert]
    expect(original_encrypted_value).to be_present

    sso_double = SsoConfiguration.find(sso.id)
    allow(SsoConfiguration).to receive(:find_each).and_yield(sso_double)
    # Make save! raise AFTER update_columns has nulled the ciphertext.
    allow(sso_double).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(sso_double))

    expect {
      Rake::Task["active_record_encryption:rotate_keyring"].invoke
    }.to raise_error(ActiveRecord::RecordInvalid)

    # The transaction rolled the nil write back. Original ciphertext intact.
    expect(sso.reload[:idp_cert]).to eq(original_encrypted_value)
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
