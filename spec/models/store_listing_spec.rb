require "rails_helper"

RSpec.describe StoreListing, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:android_app) { create(:android_app, organization: organization) }

  describe "validations" do
    it "is valid with valid attributes for iOS" do
      listing = described_class.new(
        organization: organization,
        listable: apple_app,
        locale: "en-US",
        app_name: "My App",
        description: "A great app."
      )
      expect(listing).to be_valid
    end

    it "is valid with valid attributes for Android" do
      listing = described_class.new(
        organization: organization,
        listable: android_app,
        locale: "en-US",
        app_name: "My App",
        short_description: "A great app."
      )
      expect(listing).to be_valid
    end

    it "requires a locale" do
      listing = described_class.new(organization: organization, listable: apple_app, locale: "")
      expect(listing).not_to be_valid
      expect(listing.errors[:locale]).to include("can't be blank")
    end

    it "validates sync_status inclusion" do
      listing = described_class.new(
        organization: organization, listable: apple_app, locale: "en-US", sync_status: "invalid"
      )
      expect(listing).not_to be_valid
      expect(listing.errors[:sync_status]).to include("is not included in the list")
    end

    it "validates translation_status inclusion when present" do
      listing = described_class.new(
        organization: organization, listable: apple_app, locale: "en-US", translation_status: "invalid"
      )
      expect(listing).not_to be_valid
    end

    it "allows nil translation_status" do
      listing = described_class.new(
        organization: organization, listable: apple_app, locale: "en-US", translation_status: nil
      )
      expect(listing).to be_valid
    end

    it "enforces unique locale per listable" do
      create(:store_listing, organization: organization, listable: apple_app, locale: "en-US")
      duplicate = described_class.new(organization: organization, listable: apple_app, locale: "en-US")
      expect(duplicate).not_to be_valid
    end

    it "allows same locale for different apps" do
      create(:store_listing, organization: organization, listable: apple_app, locale: "en-US")
      other = described_class.new(organization: organization, listable: android_app, locale: "en-US")
      expect(other).to be_valid
    end
  end

  describe "character limit validations" do
    context "iOS app" do
      it "rejects app_name over 30 chars" do
        listing = described_class.new(
          organization: organization, listable: apple_app, locale: "en-US",
          app_name: "A" * 31
        )
        expect(listing).not_to be_valid
        expect(listing.errors[:app_name].first).to include("maximum is 30")
      end

      it "rejects subtitle over 30 chars" do
        listing = described_class.new(
          organization: organization, listable: apple_app, locale: "en-US",
          subtitle: "A" * 31
        )
        expect(listing).not_to be_valid
      end

      it "rejects keywords over 100 chars" do
        listing = described_class.new(
          organization: organization, listable: apple_app, locale: "en-US",
          keywords: "A" * 101
        )
        expect(listing).not_to be_valid
      end

      it "rejects description over 4000 chars" do
        listing = described_class.new(
          organization: organization, listable: apple_app, locale: "en-US",
          description: "A" * 4001
        )
        expect(listing).not_to be_valid
      end

      it "rejects promotional_text over 170 chars" do
        listing = described_class.new(
          organization: organization, listable: apple_app, locale: "en-US",
          promotional_text: "A" * 171
        )
        expect(listing).not_to be_valid
      end

      it "accepts values within limits" do
        listing = described_class.new(
          organization: organization, listable: apple_app, locale: "en-US",
          app_name: "A" * 30,
          subtitle: "B" * 30,
          keywords: "C" * 100,
          description: "D" * 4000,
          promotional_text: "E" * 170
        )
        expect(listing).to be_valid
      end
    end

    context "Android app" do
      it "rejects app_name over 30 chars" do
        listing = described_class.new(
          organization: organization, listable: android_app, locale: "en-US",
          app_name: "A" * 31
        )
        expect(listing).not_to be_valid
      end

      it "rejects short_description over 80 chars" do
        listing = described_class.new(
          organization: organization, listable: android_app, locale: "en-US",
          short_description: "A" * 81
        )
        expect(listing).not_to be_valid
      end
    end
  end

  describe "platform field restrictions" do
    it "rejects Android-only fields on iOS app" do
      listing = described_class.new(
        organization: organization, listable: apple_app, locale: "en-US",
        short_description: "Not allowed on iOS"
      )
      expect(listing).not_to be_valid
      expect(listing.errors[:short_description]).to include("is not applicable for iOS apps")
    end

    it "rejects iOS-only fields on Android app" do
      listing = described_class.new(
        organization: organization, listable: android_app, locale: "en-US",
        subtitle: "Not allowed on Android"
      )
      expect(listing).not_to be_valid
      expect(listing.errors[:subtitle]).to include("is not applicable for Android apps")
    end
  end

  describe "scopes" do
    before do
      create(:store_listing, organization: organization, listable: apple_app, locale: "en-US", sync_status: "synced")
      create(:store_listing, organization: organization, listable: apple_app, locale: "de-DE", sync_status: "modified")
      create(:store_listing, :android, organization: organization, listable: android_app, locale: "en-US", sync_status: "draft")
    end

    it "filters by platform" do
      expect(described_class.for_apple.count).to eq(2)
      expect(described_class.for_android.count).to eq(1)
    end

    it "filters by locale" do
      expect(described_class.for_locale("en-US").count).to eq(2)
    end

    it "filters by sync_status" do
      expect(described_class.synced.count).to eq(1)
      expect(described_class.modified.count).to eq(1)
      expect(described_class.drafts.count).to eq(1)
    end
  end

  describe "#platform helpers" do
    it "returns :ios for AppleApp" do
      listing = described_class.new(listable: apple_app)
      expect(listing.platform).to eq(:ios)
      expect(listing.ios?).to be true
      expect(listing.android?).to be false
    end

    it "returns :android for AndroidApp" do
      listing = described_class.new(listable: android_app)
      expect(listing.platform).to eq(:android)
      expect(listing.android?).to be true
      expect(listing.ios?).to be false
    end
  end

  describe "#char_limit_for" do
    it "returns correct limits for iOS fields" do
      listing = described_class.new(listable: apple_app)
      expect(listing.char_limit_for(:app_name)).to eq(30)
      expect(listing.char_limit_for(:subtitle)).to eq(30)
      expect(listing.char_limit_for(:keywords)).to eq(100)
      expect(listing.char_limit_for(:description)).to eq(4000)
    end

    it "returns correct limits for Android fields" do
      listing = described_class.new(listable: android_app)
      expect(listing.char_limit_for(:app_name)).to eq(30)
      expect(listing.char_limit_for(:short_description)).to eq(80)
      expect(listing.char_limit_for(:description)).to eq(4000)
    end
  end

  describe "#detect_modification" do
    it "changes synced to modified when content fields change" do
      listing = create(:store_listing, organization: organization, listable: apple_app,
        app_name: "Original", sync_status: "synced", last_synced_at: Time.current)
      listing.update!(app_name: "Updated")
      expect(listing.reload.sync_status).to eq("modified")
    end

    it "does not change draft to modified" do
      listing = create(:store_listing, organization: organization, listable: apple_app,
        app_name: "Original", sync_status: "draft")
      listing.update!(app_name: "Updated")
      expect(listing.reload.sync_status).to eq("draft")
    end
  end

  describe "#mark_synced!" do
    it "updates sync_status and last_synced_at" do
      listing = create(:store_listing, organization: organization, listable: apple_app, sync_status: "modified")
      listing.mark_synced!
      expect(listing.sync_status).to eq("synced")
      expect(listing.last_synced_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#includes_keyword?" do
    let(:listing) { create(:store_listing, keywords: "focus timer, Pomodoro, café") }

    it "matches exact normalized keyword" do
      expect(listing.includes_keyword?("focus timer")).to be true
    end

    it "matches case-insensitively" do
      expect(listing.includes_keyword?("POMODORO")).to be true
    end

    it "matches with accent folding via normalizer" do
      expect(listing.includes_keyword?("café")).to be true
    end

    it "returns false for absent keyword" do
      expect(listing.includes_keyword?("sprint")).to be false
    end

    it "handles empty keywords field" do
      listing.update!(keywords: "")
      expect(listing.includes_keyword?("focus")).to be false
    end

    it "handles nil keywords field" do
      listing.update_column(:keywords, nil)
      expect(listing.includes_keyword?("focus")).to be false
    end

    it "ignores surrounding whitespace in stored field" do
      listing.update!(keywords: "  focus timer ,  pomodoro  ")
      expect(listing.includes_keyword?("focus timer")).to be true
    end
  end
end
