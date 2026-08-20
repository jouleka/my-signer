require "rails_helper"

RSpec.describe TrialHistory do
  describe ".normalize" do
    it "lowercases and strips whitespace" do
      expect(TrialHistory.normalize("  User@Example.COM  ")).to eq("user@example.com")
    end

    it "drops the +tag subaddress before @" do
      expect(TrialHistory.normalize("user+trial2@acme.com")).to eq("user@acme.com")
    end

    it "applies normalization in combination (case + whitespace + plus-tag)" do
      expect(TrialHistory.normalize("  User+Trial2@Acme.COM  ")).to eq("user@acme.com")
    end

    it "returns nil for malformed input (no @)" do
      expect(TrialHistory.normalize("not-an-email")).to be_nil
    end

    it "returns nil for empty input" do
      expect(TrialHistory.normalize("")).to be_nil
      expect(TrialHistory.normalize(nil)).to be_nil
    end

    it "returns nil for blank local part (e.g., '+tag@host')" do
      # Stripping the +tag from a local that *starts* with + leaves nothing.
      expect(TrialHistory.normalize("+tag@example.com")).to be_nil
    end

    it "treats a trailing '+' as an empty subaddress (collapses to bare local)" do
      # Pin the behavior: 'user+@x.com' is the same identity as 'user@x.com'.
      expect(TrialHistory.normalize("user+@example.com")).to eq("user@example.com")
    end

    it "returns nil for blank domain" do
      expect(TrialHistory.normalize("user@")).to be_nil
    end

    it "strips dots from the local part for gmail.com addresses" do
      expect(TrialHistory.normalize("j.smith@gmail.com")).to eq("jsmith@gmail.com")
      expect(TrialHistory.normalize("john.doe+tag@gmail.com")).to eq("johndoe@gmail.com")
    end

    it "folds googlemail.com addresses to gmail.com" do
      expect(TrialHistory.normalize("user@googlemail.com")).to eq("user@gmail.com")
      expect(TrialHistory.normalize("j.smith+promo@googlemail.com")).to eq("jsmith@gmail.com")
    end

    it "does NOT strip dots for non-gmail addresses" do
      # Other providers treat dots as significant; don't over-normalize.
      expect(TrialHistory.normalize("j.smith@acme.com")).to eq("j.smith@acme.com")
    end

    it "returns nil when a gmail local part is dots-only" do
      # `....@gmail.com` collapses to empty after dot-stripping.
      expect(TrialHistory.normalize("....@gmail.com")).to be_nil
    end
  end

  describe ".hash_for" do
    it "produces a stable HMAC keyed by secret_key_base" do
      expected = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "user@example.com")
      expect(TrialHistory.hash_for("user@example.com")).to eq(expected)
    end

    it "normalizes via downcase, strip, and plus-tag stripping" do
      expect(TrialHistory.hash_for("  User@Example.COM  ")).to eq(TrialHistory.hash_for("user@example.com"))
      expect(TrialHistory.hash_for("user+anything@example.com")).to eq(TrialHistory.hash_for("user@example.com"))
    end

    it "returns nil for malformed input" do
      expect(TrialHistory.hash_for("not-an-email")).to be_nil
      expect(TrialHistory.hash_for(nil)).to be_nil
    end
  end

  describe ".claim! and .claimed?" do
    it "returns false when not claimed" do
      expect(TrialHistory.claimed?("new@example.com")).to be false
    end

    it "records a claim and returns true afterward" do
      TrialHistory.claim!("fresh@example.com")
      expect(TrialHistory.claimed?("fresh@example.com")).to be true
    end

    it "is idempotent -- claiming twice returns the same record" do
      first = TrialHistory.claim!("idempotent@example.com")
      second = TrialHistory.claim!("idempotent@example.com")

      expect(first).to eq(second)
      expect(TrialHistory.where(email_hash: TrialHistory.hash_for("idempotent@example.com")).count).to eq(1)
    end

    it "treats case/whitespace variants as the same email" do
      TrialHistory.claim!("original@example.com")
      expect(TrialHistory.claimed?("  ORIGINAL@example.com ")).to be true
    end

    # Plus-addressing bypass guard: previously, `user+a@example.com` and
    # `user+b@example.com` produced different hashes, so a malicious user
    # could chain unlimited trials by varying the +tag. Normalize now
    # strips the +tag, so all variants collide to the same record.
    it "claimed? returns true for plus-tag variants of a claimed email" do
      TrialHistory.claim!("user+a@example.com")
      expect(TrialHistory.claimed?("user+b@example.com")).to be true
      expect(TrialHistory.claimed?("user@example.com")).to be true
      expect(TrialHistory.claimed?("user+xyzpdq@example.com")).to be true
    end

    it "claim! is idempotent across plus-tag variants" do
      first = TrialHistory.claim!("alice+trial1@example.com")
      second = TrialHistory.claim!("alice+trial2@example.com")
      third = TrialHistory.claim!("alice@example.com")

      expect(first).to eq(second)
      expect(second).to eq(third)
      # Scope the count to THIS email's hash (matching the ".idempotent" test
      # above) rather than the whole table — an absolute `TrialHistory.count`
      # is fragile to any pre-existing row (the trial guard fires on every User
      # signup), which made this example nondeterministic. All three +tag
      # variants normalize to the same hash, so exactly one row must exist.
      expect(TrialHistory.where(email_hash: TrialHistory.hash_for("alice@example.com")).count).to eq(1)
    end

    # Gmail dot-aliasing bypass guard: `j.smith@gmail.com`,
    # `jsmith@gmail.com`, and `j.s.m.i.t.h@googlemail.com` are all the same
    # Gmail mailbox. Normalize folds them to the same hash so none can
    # bypass the trial lockout.
    it "treats Gmail dot-and-domain variants as the same identity" do
      TrialHistory.claim!("j.smith@gmail.com")

      expect(TrialHistory.claimed?("jsmith@gmail.com")).to be true
      expect(TrialHistory.claimed?("j.s.m.i.t.h@gmail.com")).to be true
      expect(TrialHistory.claimed?("jsmith@googlemail.com")).to be true
      expect(TrialHistory.claimed?("jsmith+second@gmail.com")).to be true
    end

    it "returns nil/false safely for malformed emails" do
      expect(TrialHistory.claim!("garbage")).to be_nil
      expect(TrialHistory.claimed?("garbage")).to be false
      expect { TrialHistory.claim!(nil) }.not_to raise_error
      expect(TrialHistory.claimed?(nil)).to be false
    end
  end
end

RSpec.describe "User re-entry trial prevention" do
  it "does NOT grant a trial on re-registration of the same email" do
    # First registration -- explicit with_reverse_trial because the test suite
    # default skips the trial callback.
    User.with_reverse_trial do
      first = User.create!(email: "reentry@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      expect(first.plan_tier).to eq("pro")
      expect(TrialHistory.claimed?("reentry@example.com")).to be true

      # Simulate the user deleting their account...
      first.destroy
      expect(User.find_by(email: "reentry@example.com")).to be_nil
      # TrialHistory entry persists across user deletion
      expect(TrialHistory.claimed?("reentry@example.com")).to be true

      # ...and re-registering with the same email.
      second = User.create!(email: "reentry@example.com", password: "SecurePassword123!", confirmed_at: Time.current)

      expect(second.plan_tier).to eq("free")
      expect(second.trial_ends_at).to be_nil
    end
  end

  it "DOES grant a trial to a brand-new email that was never claimed" do
    User.with_reverse_trial do
      user = User.create!(email: "brandnew@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      expect(user.plan_tier).to eq("pro")
      expect(user.trial_ends_at).to be_within(5.seconds).of(14.days.from_now)
    end
  end

  # Plus-addressing trial-bypass regression: a user who claimed a trial as
  # `eve@example.com` cannot get a second trial by registering as
  # `eve+second@example.com`.
  it "does NOT grant a trial when re-registering with a plus-tag variant" do
    User.with_reverse_trial do
      original = User.create!(email: "eve@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      expect(original.plan_tier).to eq("pro")

      # Now another (or the same) user registers with a +tag variant.
      tagged = User.create!(email: "eve+second@example.com", password: "SecurePassword123!", confirmed_at: Time.current)

      expect(tagged.plan_tier).to eq("free")
      expect(tagged.trial_ends_at).to be_nil
    end
  end
end
