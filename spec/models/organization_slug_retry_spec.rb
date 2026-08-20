require "rails_helper"

RSpec.describe Organization, "slug retry on concurrent creation" do
  let(:owner_a) { User.create!(email: "alpha@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro) }
  let(:owner_b) { User.create!(email: "bravo@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro) }

  describe "#save_with_slug_retry" do
    it "saves when no collision happens" do
      org = Organization.new(name: "Normal Org", owner: owner_a)
      expect(org.save_with_slug_retry).to be true
      expect(org.slug).to eq("normal-org")
    end

    it "retries with a random suffix when save raises RecordNotUnique on slug" do
      racing = Organization.new(name: "Shared Name", owner: owner_b)

      # Simulate the race: Rails-level `uniqueness` validation passes (both
      # transactions observe "slug is free"), then the DB unique index rejects
      # the INSERT with RecordNotUnique. We stub save to raise the first time
      # and succeed the second.
      call_count = 0
      allow(racing).to receive(:save).and_wrap_original do |original, *args|
        call_count += 1
        if call_count == 1
          raise ActiveRecord::RecordNotUnique, "duplicate key value violates unique constraint \"index_organizations_on_slug\""
        else
          original.call(*args)
        end
      end

      expect(racing.save_with_slug_retry).to be true
      expect(racing.slug).to start_with("shared-name-")
      expect(racing.slug).not_to eq("shared-name")
      expect(call_count).to eq(2)
    end

    it "gives up after 3 attempts to avoid spinning on unrelated uniqueness errors" do
      org = Organization.new(name: "Give Up", owner: owner_a)

      # Always return a raw RecordNotUnique on save. Since the message doesn't
      # mention slug, the retry logic re-raises immediately.
      allow(org).to receive(:save).and_raise(ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: organizations.id"))

      expect { org.save_with_slug_retry }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#generate_slug bounded retry" do
    it "uses a bare slug when the base name is unique" do
      org = Organization.create!(name: "Unique Brand", owner: owner_a)
      expect(org.slug).to eq("unique-brand")
    end

    it "appends a small numeric suffix on the first few collisions" do
      Organization.create!(name: "Acme Co", owner: owner_a, slug: "acme-co")
      org = Organization.create!(name: "Acme Co", owner: owner_b)
      expect(org.slug).to eq("acme-co-1")
    end

    it "falls back to a random suffix after #{Organization::SLUG_NUMERIC_SUFFIX_ATTEMPTS} numeric collisions to avoid an unbounded scan" do
      base = "popular"
      # Pre-claim the base slug and every numbered slot the bounded loop would try.
      Organization.create!(name: base.titleize, owner: owner_a, slug: base)
      Organization::SLUG_NUMERIC_SUFFIX_ATTEMPTS.times do |i|
        # Use distinct owners by minting users on the fly so we don't trip the
        # owner_organization_limit validation while seeding the collision set.
        owner = User.create!(email: "popular-#{i}@ex.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro)
        Organization.create!(name: base.titleize, owner: owner, slug: "#{base}-#{i + 1}")
      end

      colliding = Organization.create!(name: base.titleize, owner: owner_b)

      # The fallback path appends `-` plus 6 hex chars (SecureRandom.hex(3)).
      expect(colliding.slug).to match(/\Apopular-[0-9a-f]{6}\z/)
    end
  end
end
