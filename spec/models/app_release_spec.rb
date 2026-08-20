require "rails_helper"

RSpec.describe AppRelease, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:android_app) { create(:android_app, organization: organization) }

  describe "validations" do
    it "is valid with valid attributes" do
      release = build(:app_release, organization: organization, listable: apple_app)
      expect(release).to be_valid
    end

    it "requires status" do
      release = build(:app_release, organization: organization, listable: apple_app, status: nil)
      expect(release).not_to be_valid
    end

    it "validates status inclusion" do
      release = build(:app_release, organization: organization, listable: apple_app, status: "bogus")
      expect(release).not_to be_valid
      expect(release.errors[:status]).to be_present
    end

    it "allows all defined statuses" do
      AppRelease::STATUSES.each do |status|
        release = build(:app_release, organization: organization, listable: apple_app, status: status)
        expect(release).to be_valid, "Expected status '#{status}' to be valid"
      end
    end

    it "accepts AppleApp and AndroidApp listables only" do
      ios_release = build(:app_release, listable: apple_app)
      android_release = build(:app_release, listable: android_app)
      expect(ios_release).to be_valid
      expect(android_release).to be_valid
    end

    it "enforces uniqueness on (listable_type, listable_id, version_string)" do
      create(:app_release, organization: organization, listable: apple_app, version_string: "1.0.0")
      duplicate = build(:app_release, organization: organization, listable: apple_app, version_string: "1.0.0")
      expect(duplicate).not_to be_valid
    end

    it "allows multiple releases for the same app with different versions" do
      create(:app_release, organization: organization, listable: apple_app, version_string: "1.0.0")
      v2 = build(:app_release, organization: organization, listable: apple_app, version_string: "2.0.0")
      expect(v2).to be_valid
    end
  end

  describe "scopes" do
    let!(:draft) { create(:app_release, organization: organization, listable: apple_app, status: "draft", version_string: "1.0.0") }
    let!(:in_review) { create(:app_release, organization: organization, listable: apple_app, status: "in_review", version_string: "2.0.0") }
    let!(:live) { create(:app_release, organization: organization, listable: apple_app, status: "live", version_string: "3.0.0") }
    let!(:archived) { create(:app_release, organization: organization, listable: apple_app, status: "archived", version_string: "4.0.0") }

    it "scope :draft returns only drafts" do
      expect(described_class.draft).to contain_exactly(draft)
    end

    it "scope :in_review returns only in_review" do
      expect(described_class.in_review).to contain_exactly(in_review)
    end

    it "scope :live returns only live" do
      expect(described_class.live).to contain_exactly(live)
    end

    it "scope :archived returns only archived" do
      expect(described_class.archived).to contain_exactly(archived)
    end

    it "scope :for_app filters by listable" do
      other_app = create(:apple_app, organization: organization, sku: "OTHER-#{SecureRandom.hex(4)}")
      other_release = create(:app_release, organization: organization, listable: other_app, version_string: "1.0.0")
      expect(described_class.for_app(apple_app)).not_to include(other_release)
      expect(described_class.for_app(apple_app)).to include(draft, in_review, live, archived)
    end
  end

  describe "platform helpers" do
    it "#ios? returns true for AppleApp listable" do
      release = build(:app_release, listable: apple_app)
      expect(release).to be_ios
      expect(release).not_to be_android
      expect(release.platform).to eq(:ios)
    end

    it "#android? returns true for AndroidApp listable" do
      release = build(:app_release, listable: android_app)
      expect(release).to be_android
      expect(release).not_to be_ios
      expect(release.platform).to eq(:android)
    end
  end

  describe "#store_listings" do
    let(:release) { create(:app_release, organization: organization, listable: apple_app) }

    it "returns store listings for the app" do
      en_listing = create(:store_listing, organization: organization, listable: apple_app, locale: "en-US")
      de_listing = create(:store_listing, organization: organization, listable: apple_app, locale: "de-DE")
      other_app = create(:apple_app, organization: organization, sku: "OTHER-#{SecureRandom.hex(4)}")
      other_app_listing = create(:store_listing, organization: organization, listable: other_app, locale: "en-US")

      expect(release.store_listings).to include(en_listing, de_listing)
      expect(release.store_listings).not_to include(other_app_listing)
    end

    it "#store_listing_for finds a listing by locale" do
      en_listing = create(:store_listing, organization: organization, listable: apple_app, locale: "en-US")
      expect(release.store_listing_for("en-US")).to eq(en_listing)
      expect(release.store_listing_for("ja")).to be_nil
    end
  end

  describe "#release_notes" do
    let(:release) { create(:app_release, organization: organization, listable: apple_app, version_string: "2.0.0") }

    it "returns all release notes for the app" do
      v1_note = create(:release_note, organization: organization, listable: apple_app, version_string: "1.0.0")
      v2_note = create(:release_note, organization: organization, listable: apple_app, version_string: "2.0.0")
      other_app = create(:apple_app, organization: organization, sku: "OTHER-#{SecureRandom.hex(4)}")
      other_app_note = create(:release_note, organization: organization, listable: other_app, version_string: "2.0.0")

      expect(release.release_notes).to include(v1_note, v2_note)
      expect(release.release_notes).not_to include(other_app_note)
    end

    it "#release_notes_for_this_version filters by version_string" do
      v1_note = create(:release_note, organization: organization, listable: apple_app, version_string: "1.0.0")
      v2_note = create(:release_note, organization: organization, listable: apple_app, version_string: "2.0.0")

      expect(release.release_notes_for_this_version).to contain_exactly(v2_note)
    end

    it "#release_notes_for_this_version is empty when version_string is blank" do
      release.update!(version_string: nil)
      create(:release_note, organization: organization, listable: apple_app, version_string: "2.0.0")
      expect(release.release_notes_for_this_version).to be_empty
    end
  end

  describe "#primary_release_note" do
    let(:release) { create(:app_release, organization: organization, listable: apple_app, version_string: "2.0.0") }

    it "returns the en-US note for this version when present" do
      en_note = create(:release_note, organization: organization, listable: apple_app, version_string: "2.0.0", locale: "en-US")
      create(:release_note, organization: organization, listable: apple_app, version_string: "2.0.0", locale: "de-DE")

      expect(release.primary_release_note).to eq(en_note)
    end

    it "falls back to any note for this version" do
      de_note = create(:release_note, organization: organization, listable: apple_app, version_string: "2.0.0", locale: "de-DE")
      expect(release.primary_release_note).to eq(de_note)
    end

    it "falls back to a draft note for the app when no note for this version" do
      draft = create(:release_note, organization: organization, listable: apple_app, version_string: "1.5.0", status: "draft")
      expect(release.primary_release_note).to eq(draft)
    end
  end

  describe "#primary_locale" do
    it "returns en-US for AppleApp" do
      release = build(:app_release, listable: apple_app)
      expect(release.primary_locale).to eq("en-US")
    end

    it "returns the AndroidApp.default_language when present" do
      android_app.update!(default_language: "fr-CA")
      release = build(:app_release, listable: android_app)
      expect(release.primary_locale).to eq("fr-CA")
    end

    it "falls back to en-US for AndroidApp without default_language" do
      android_app.update!(default_language: nil)
      release = build(:app_release, listable: android_app)
      expect(release.primary_locale).to eq("en-US")
    end

    context "for an iOS app with non-en-US primaryLocale" do
      it "returns the actual Apple primary locale, not en-US" do
        apple_app_en_gb = create(:apple_app, :en_gb_primary, organization: organization)
        release = build(:app_release, listable: apple_app_en_gb)
        expect(release.primary_locale).to eq("en-GB")
      end
    end

    context "for an Android app with non-en-US default_language" do
      it "returns the Android default language" do
        android_de = create(:android_app, organization: organization, default_language: "de-DE")
        release = build(:app_release, listable: android_de)
        expect(release.primary_locale).to eq("de-DE")
      end
    end
  end

  describe "#computed_status" do
    let(:release) { create(:app_release, organization: organization, listable: apple_app, version_string: "1.0.0") }

    it "returns 'unknown' when no platform release exists" do
      expect(release.computed_status).to eq("unknown")
    end

    it "returns 'live' for READY_FOR_SALE iOS state" do
      AppStoreVersion.create!(
        organization: organization,
        apple_app: apple_app,
        version_id: "asv-#{SecureRandom.hex(4)}",
        version_string: "1.0.0",
        app_store_state: "READY_FOR_SALE"
      )
      expect(release.computed_status).to eq("live")
    end

    it "returns 'in_review' for IN_REVIEW iOS state" do
      AppStoreVersion.create!(
        organization: organization,
        apple_app: apple_app,
        version_id: "asv-#{SecureRandom.hex(4)}",
        version_string: "1.0.0",
        app_store_state: "IN_REVIEW"
      )
      expect(release.computed_status).to eq("in_review")
    end

    it "returns 'rejected' for REJECTED iOS state" do
      AppStoreVersion.create!(
        organization: organization,
        apple_app: apple_app,
        version_id: "asv-#{SecureRandom.hex(4)}",
        version_string: "1.0.0",
        app_store_state: "REJECTED"
      )
      expect(release.computed_status).to eq("rejected")
    end

    it "returns the Android status string directly" do
      android_release = create(:app_release, organization: organization, listable: android_app, version_string: "1.0.0")
      PlayStoreRelease.create!(
        android_app: android_app,
        version_code: "100",
        track: "production",
        status: "live"
      )
      expect(android_release.computed_status).to eq("live")
    end
  end
end
