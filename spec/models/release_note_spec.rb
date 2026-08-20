require "rails_helper"

RSpec.describe ReleaseNote, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:android_app) { create(:android_app, organization: organization) }

  describe "validations" do
    it "is valid with valid attributes" do
      note = build(:release_note, organization: organization, listable: apple_app)
      expect(note).to be_valid
    end

    it "requires locale" do
      note = build(:release_note, organization: organization, listable: apple_app, locale: "")
      expect(note).not_to be_valid
      expect(note.errors[:locale]).to include("can't be blank")
    end

    describe "locale format" do
      %w[en en-US fr-CA zh-Hans zh-Hans-CN es-419 pt-BR de fil].each do |valid_locale|
        it "accepts '#{valid_locale}'" do
          note = build(:release_note, organization: organization, listable: apple_app, locale: valid_locale)
          expect(note).to be_valid, "Expected locale '#{valid_locale}' to be valid: #{note.errors[:locale].join(', ')}"
        end
      end

      [
        "123",            # digits only
        "a",              # too short
        "abcd",           # too long for language code
        "en_US",          # underscore instead of dash
        "en-",            # trailing dash
        "-US",            # leading dash
        "english",        # too long
        "en US",          # space
        "🇺🇸",           # emoji
        "1234"            # numeric only
      ].each do |invalid_locale|
        it "rejects '#{invalid_locale}'" do
          note = build(:release_note, organization: organization, listable: apple_app, locale: invalid_locale)
          expect(note).not_to be_valid
          expect(note.errors[:locale].first).to include("BCP 47")
        end
      end

      it "strips whitespace before validating" do
        note = build(:release_note, organization: organization, listable: apple_app, locale: "  en-US  ")
        expect(note).to be_valid
        expect(note.locale).to eq("en-US")
      end
    end

    describe "version_string format" do
      %w[1 1.2 1.2.3 2.1.0 10.20.30 1.2.3.4 2.1.0-beta 2.1.0+build123].each do |valid_version|
        it "accepts '#{valid_version}'" do
          note = build(:release_note, organization: organization, listable: apple_app, version_string: valid_version)
          expect(note).to be_valid, "Expected version '#{valid_version}' to be valid: #{note.errors[:version_string].join(', ')}"
        end
      end

      it "allows blank version_string" do
        note = build(:release_note, organization: organization, listable: apple_app, version_string: nil)
        expect(note).to be_valid
      end

      %w[abc v1.2.3 1..2 1.2.3.4.5 -1 .3].each do |invalid_version|
        it "rejects '#{invalid_version}'" do
          note = build(:release_note, organization: organization, listable: apple_app, version_string: invalid_version)
          expect(note).not_to be_valid
          expect(note.errors[:version_string]).to be_present
        end
      end
    end

    describe "build_number format" do
      %w[1 142 1.2.3 1-rc1 build.42].each do |valid_build|
        it "accepts '#{valid_build}'" do
          note = build(:release_note, organization: organization, listable: apple_app, build_number: valid_build)
          expect(note).to be_valid, "Expected build '#{valid_build}' to be valid: #{note.errors[:build_number].join(', ')}"
        end
      end

      it "allows blank build_number" do
        note = build(:release_note, organization: organization, listable: apple_app, build_number: nil)
        expect(note).to be_valid
      end

      [ "build 1", "1 2", "build@42", "build/42" ].each do |invalid_build|
        it "rejects '#{invalid_build}'" do
          note = build(:release_note, organization: organization, listable: apple_app, build_number: invalid_build)
          expect(note).not_to be_valid
          expect(note.errors[:build_number]).to be_present
        end
      end
    end

    it "requires status" do
      note = build(:release_note, organization: organization, listable: apple_app, status: nil)
      expect(note).not_to be_valid
    end

    it "validates status inclusion" do
      note = build(:release_note, organization: organization, listable: apple_app, status: "invalid")
      expect(note).not_to be_valid
      expect(note.errors[:status]).to include("is not included in the list")
    end

    it "allows all valid statuses" do
      ReleaseNote::STATUSES.each do |status|
        note = build(:release_note, organization: organization, listable: apple_app, status: status)
        expect(note).to be_valid, "Expected status '#{status}' to be valid"
      end
    end

    it "includes pending_review in STATUSES" do
      expect(ReleaseNote::STATUSES).to include("pending_review")
    end

    it "validates source inclusion" do
      note = build(:release_note, organization: organization, listable: apple_app, source: "invalid")
      expect(note).not_to be_valid
      expect(note.errors[:source]).to include("is not included in the list")
    end

    it "allows nil source" do
      note = build(:release_note, organization: organization, listable: apple_app, source: nil)
      expect(note).to be_valid
    end

    it "allows all valid sources" do
      ReleaseNote::SOURCES.each do |source|
        note = build(:release_note, organization: organization, listable: apple_app, source: source)
        expect(note).to be_valid, "Expected source '#{source}' to be valid"
      end
    end

    describe "rendered_text char limit" do
      it "rejects rendered_text over 4000 chars for iOS" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          rendered_text: "A" * 4001
        )
        expect(note).not_to be_valid
        expect(note.errors[:rendered_text].first).to include("maximum is 4000")
      end

      it "accepts rendered_text within 4000 chars for iOS" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          rendered_text: "A" * 4000
        )
        expect(note).to be_valid
      end

      it "rejects rendered_text over 500 chars for Android" do
        note = build(:release_note,
          organization: organization,
          listable: android_app,
          rendered_text: "A" * 501
        )
        expect(note).not_to be_valid
        expect(note.errors[:rendered_text].first).to include("maximum is 500")
      end

      it "accepts rendered_text within 500 chars for Android" do
        note = build(:release_note,
          organization: organization,
          listable: android_app,
          rendered_text: "A" * 500
        )
        expect(note).to be_valid
      end

      it "allows blank rendered_text" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          rendered_text: "",
          template_data: {}
        )
        expect(note).to be_valid
      end
    end

    describe "template_data structure" do
      it "allows empty hash" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          template_data: {},
          rendered_text: "Some text"
        )
        expect(note).to be_valid
      end

      it "rejects non-hash template_data" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          template_data: "not a hash",
          rendered_text: "Some text"
        )
        expect(note).not_to be_valid
        expect(note.errors[:template_data]).to include("must be a hash")
      end

      it "rejects invalid categories" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          template_data: { "invalid_category" => [ "item" ] },
          rendered_text: "Some text"
        )
        expect(note).not_to be_valid
        expect(note.errors[:template_data].first).to include("invalid category")
      end

      it "requires array values for categories" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          template_data: { "new" => "not an array" },
          rendered_text: "Some text"
        )
        expect(note).not_to be_valid
        expect(note.errors[:template_data].first).to include("must be an array")
      end

      it "requires string items in arrays" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          template_data: { "new" => [ 123, 456 ] },
          rendered_text: "Some text"
        )
        expect(note).not_to be_valid
        expect(note.errors[:template_data].first).to include("must contain only strings")
      end

      it "accepts valid template_data with all categories" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          template_data: {
            "new" => [ "Feature A" ],
            "improved" => [ "Better B" ],
            "fixed" => [ "Bug C" ]
          }
        )
        expect(note).to be_valid
      end

      it "accepts valid template_data with partial categories" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          template_data: { "new" => [ "Feature A" ] },
          rendered_text: "NEW\n- Feature A"
        )
        expect(note).to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:draft_note) { create(:release_note, organization: organization, listable: apple_app, status: "draft", version_string: "1.0.0") }
    let!(:applied_note) { create(:release_note, :applied, organization: organization, listable: apple_app, version_string: "1.1.0") }
    let!(:published_note) { create(:release_note, :published, organization: organization, listable: apple_app, version_string: "2.0.0") }
    let!(:archived_note) { create(:release_note, :archived, organization: organization, listable: apple_app, version_string: "0.9.0") }
    let!(:android_note) { create(:release_note, :android, organization: organization, listable: android_app) }

    describe ".for_app" do
      it "filters by listable" do
        expect(described_class.for_app(apple_app).count).to eq(4)
        expect(described_class.for_app(android_app).count).to eq(1)
      end
    end

    describe ".drafts" do
      it "returns only draft notes" do
        expect(described_class.drafts).to include(draft_note, android_note)
        expect(described_class.drafts).not_to include(applied_note, published_note, archived_note)
      end
    end

    describe ".applied" do
      it "returns only applied notes" do
        expect(described_class.applied).to include(applied_note)
        expect(described_class.applied).not_to include(draft_note, published_note)
      end
    end

    describe ".pending_review" do
      let!(:pending_note) do
        create(:release_note, :pending_review,
          organization: organization, listable: apple_app, version_string: "3.0.0")
      end

      it "returns only pending_review notes" do
        expect(described_class.pending_review).to include(pending_note)
        expect(described_class.pending_review).not_to include(draft_note, applied_note, published_note, archived_note)
      end
    end

    describe ".published" do
      it "returns only published notes" do
        expect(described_class.published).to include(published_note)
        expect(described_class.published).not_to include(draft_note, applied_note)
      end
    end

    describe ".archived" do
      it "returns only archived notes" do
        expect(described_class.archived).to include(archived_note)
        expect(described_class.archived).not_to include(draft_note, published_note)
      end
    end

    describe ".recent" do
      it "orders by created_at desc" do
        results = described_class.recent
        expect(results.first.created_at).to be >= results.last.created_at
      end
    end

    describe ".by_version" do
      it "orders by version_string desc" do
        results = described_class.for_app(apple_app).by_version
        versions = results.map(&:version_string)
        expect(versions).to eq([ "2.0.0", "1.1.0", "1.0.0", "0.9.0" ])
      end
    end
  end

  describe "platform helpers" do
    it "returns :ios for AppleApp" do
      note = build(:release_note, listable: apple_app)
      expect(note.platform).to eq(:ios)
      expect(note.ios?).to be true
      expect(note.android?).to be false
    end

    it "returns :android for AndroidApp" do
      note = build(:release_note, listable: android_app, rendered_text: "Short")
      expect(note.platform).to eq(:android)
      expect(note.android?).to be true
      expect(note.ios?).to be false
    end

    it "returns correct char_limit for iOS" do
      note = build(:release_note, listable: apple_app)
      expect(note.char_limit).to eq(4000)
    end

    it "returns correct char_limit for Android" do
      note = build(:release_note, listable: android_app, rendered_text: "Short")
      expect(note.char_limit).to eq(500)
    end
  end

  describe "#render_text_from_template" do
    it "renders correct output format" do
      note = build(:release_note,
        listable: apple_app,
        template_data: {
          "new" => [ "Dark mode" ],
          "improved" => [ "Faster loading" ],
          "fixed" => [ "Crash on startup" ]
        }
      )
      expected = "NEW\n- Dark mode\n\nIMPROVED\n- Faster loading\n\nFIXED\n- Crash on startup"
      expect(note.render_text_from_template).to eq(expected)
    end

    it "handles empty categories" do
      note = build(:release_note,
        listable: apple_app,
        template_data: {
          "new" => [ "Dark mode" ],
          "improved" => [],
          "fixed" => [ "Bug fix" ]
        }
      )
      expected = "NEW\n- Dark mode\n\nFIXED\n- Bug fix"
      expect(note.render_text_from_template).to eq(expected)
    end

    it "handles nil items in template_data" do
      note = build(:release_note,
        listable: apple_app,
        template_data: { "new" => [ "Feature A" ] }
      )
      result = note.render_text_from_template
      expect(result).to eq("NEW\n- Feature A")
    end

    it "handles completely empty template_data" do
      note = build(:release_note,
        listable: apple_app,
        template_data: {}
      )
      expect(note.render_text_from_template).to eq("")
    end

    it "skips blank string items" do
      note = build(:release_note,
        listable: apple_app,
        template_data: { "new" => [ "Feature A", "", "Feature B" ] }
      )
      result = note.render_text_from_template
      expect(result).to eq("NEW\n- Feature A\n- Feature B")
    end
  end

  describe "#apply_to_store_listings!" do
    let!(:base_listing) do
      create(:store_listing, organization: organization, listable: apple_app, locale: "en-US")
    end
    let!(:de_listing) do
      create(:store_listing, organization: organization, listable: apple_app, locale: "de-DE")
    end

    it "updates base locale store listing whats_new" do
      note = create(:release_note,
        organization: organization,
        listable: apple_app,
        locale: "en-US",
        rendered_text: "NEW\n- Dark mode"
      )
      note.apply_to_store_listings!

      expect(base_listing.reload.whats_new).to eq("NEW\n- Dark mode")
    end

    it "applies translations to other locale store listings" do
      note = create(:release_note, :with_translations,
        organization: organization,
        listable: apple_app,
        locale: "en-US",
        rendered_text: "NEW\n- Dark mode"
      )
      note.apply_to_store_listings!

      expect(de_listing.reload.whats_new).to eq("NEU\n- Dunkelmodus hinzugefuegt")
    end

    it "updates status to applied" do
      note = create(:release_note,
        organization: organization,
        listable: apple_app,
        locale: "en-US"
      )
      note.apply_to_store_listings!

      expect(note.reload.status).to eq("applied")
      expect(note.applied_at).to be_present
    end
  end

  describe "#diff_with" do
    let(:note_v1) do
      create(:release_note,
        organization: organization,
        listable: apple_app,
        version_string: "1.0.0",
        rendered_text: "OLD\n- Old feature",
        template_data: { "new" => [ "Old feature" ] }
      )
    end

    let(:note_v2) do
      create(:release_note,
        organization: organization,
        listable: apple_app,
        version_string: "2.0.0",
        rendered_text: "NEW\n- New feature",
        template_data: { "new" => [ "New feature" ] }
      )
    end

    it "returns correct diff hash" do
      diff = note_v2.diff_with(note_v1)

      expect(diff[:version_string][:before]).to eq("1.0.0")
      expect(diff[:version_string][:after]).to eq("2.0.0")
      expect(diff[:rendered_text][:before]).to eq("OLD\n- Old feature")
      expect(diff[:rendered_text][:after]).to eq("NEW\n- New feature")
      expect(diff[:template_data][:before]).to eq({ "new" => [ "Old feature" ] })
      expect(diff[:template_data][:after]).to eq({ "new" => [ "New feature" ] })
    end

    it "returns nil when other_note is nil" do
      diff = note_v2.diff_with(nil)
      expect(diff).to be_nil
    end
  end

  describe "callbacks" do
    describe "auto_render_text" do
      it "renders text from template when template_data changes and rendered_text is blank" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          template_data: { "new" => [ "Dark mode" ] },
          rendered_text: nil
        )
        note.save!

        expect(note.rendered_text).to eq("NEW\n- Dark mode")
      end

      it "does not override existing rendered_text" do
        note = build(:release_note,
          organization: organization,
          listable: apple_app,
          template_data: { "new" => [ "Dark mode" ] },
          rendered_text: "Custom text"
        )
        note.save!

        expect(note.rendered_text).to eq("Custom text")
      end
    end

    describe "set_applied_timestamp" do
      it "sets applied_at when status changes to applied" do
        note = create(:release_note, organization: organization, listable: apple_app)
        note.update!(status: "applied")

        expect(note.applied_at).to be_within(2.seconds).of(Time.current)
      end
    end

    describe "set_published_timestamp" do
      it "sets published_at when status changes to published" do
        note = create(:release_note, :applied, organization: organization, listable: apple_app)
        note.update!(status: "published")

        expect(note.published_at).to be_within(2.seconds).of(Time.current)
      end
    end
  end

  describe "review workflow" do
    let(:author) { create(:user) }
    let(:reviewer) { create(:user) }

    describe "#submit_for_review!" do
      it "transitions draft to pending_review and stamps timestamp" do
        note = create(:release_note, organization: organization, listable: apple_app, status: "draft")

        note.submit_for_review!(user: author)

        expect(note.reload.status).to eq("pending_review")
        expect(note.submitted_for_review_at).to be_within(2.seconds).of(Time.current)
      end

      it "raises when not in draft" do
        note = create(:release_note, :applied, organization: organization, listable: apple_app)
        expect { note.submit_for_review!(user: author) }.to raise_error(/Cannot submit/)
      end

      it "raises when already pending_review" do
        note = create(:release_note, :pending_review, organization: organization, listable: apple_app)
        expect { note.submit_for_review!(user: author) }.to raise_error(/Cannot submit/)
      end
    end

    describe "#approve_review!" do
      it "transitions pending_review back to draft, stamps reviewer, clears comment" do
        note = create(:release_note, :pending_review, organization: organization, listable: apple_app)

        note.approve_review!(user: reviewer)

        expect(note.reload.status).to eq("draft")
        expect(note.reviewed_by).to eq(reviewer)
        expect(note.reviewed_at).to be_within(2.seconds).of(Time.current)
        expect(note.review_comment).to be_nil
      end

      it "clears comment even if one is passed in blank" do
        note = create(:release_note, :pending_review, organization: organization, listable: apple_app)

        note.approve_review!(user: reviewer, comment: "")

        expect(note.reload.review_comment).to be_nil
      end

      it "raises when not in pending_review" do
        note = create(:release_note, organization: organization, listable: apple_app, status: "draft")
        expect { note.approve_review!(user: reviewer) }.to raise_error(/Cannot approve/)
      end
    end

    describe "#reject_review!" do
      it "transitions pending_review back to draft, stamps reviewer, saves comment" do
        note = create(:release_note, :pending_review, organization: organization, listable: apple_app)

        note.reject_review!(user: reviewer, comment: "Needs more detail")

        expect(note.reload.status).to eq("draft")
        expect(note.reviewed_by).to eq(reviewer)
        expect(note.reviewed_at).to be_within(2.seconds).of(Time.current)
        expect(note.review_comment).to eq("Needs more detail")
      end

      it "raises if comment is blank" do
        note = create(:release_note, :pending_review, organization: organization, listable: apple_app)
        expect { note.reject_review!(user: reviewer, comment: "") }.to raise_error(/Rejection requires a comment/)
      end

      it "raises if comment is only whitespace" do
        note = create(:release_note, :pending_review, organization: organization, listable: apple_app)
        expect { note.reject_review!(user: reviewer, comment: "   ") }.to raise_error(/Rejection requires a comment/)
      end

      it "raises if comment is nil" do
        note = create(:release_note, :pending_review, organization: organization, listable: apple_app)
        expect { note.reject_review!(user: reviewer, comment: nil) }.to raise_error(/Rejection requires a comment/)
      end

      it "raises when not in pending_review" do
        note = create(:release_note, organization: organization, listable: apple_app, status: "draft")
        expect { note.reject_review!(user: reviewer, comment: "text") }.to raise_error(/Cannot reject/)
      end
    end

    describe "predicates" do
      it "#pending_review? returns true only for pending_review status" do
        expect(build(:release_note, status: "pending_review")).to be_pending_review
        expect(build(:release_note, status: "draft")).not_to be_pending_review
      end

      it "#reviewed? returns true once reviewed_at is set" do
        note = build(:release_note, reviewed_at: nil)
        expect(note).not_to be_reviewed

        note.reviewed_at = Time.current
        expect(note).to be_reviewed
      end

      it "#approved? returns true when reviewed with no comment" do
        note = build(:release_note, reviewed_at: Time.current, review_comment: nil)
        expect(note).to be_approved
      end

      it "#approved? returns false when comment is present" do
        note = build(:release_note, reviewed_at: Time.current, review_comment: "Needs work")
        expect(note).not_to be_approved
      end

      it "#approved? returns false when never reviewed" do
        note = build(:release_note, reviewed_at: nil, review_comment: nil)
        expect(note).not_to be_approved
      end

      it "#rejected? returns true when reviewed with comment and back in draft" do
        note = build(:release_note, :review_requested_changes, organization: organization, listable: apple_app)
        expect(note).to be_rejected
      end

      it "#rejected? returns false when no review comment" do
        note = build(:release_note, status: "draft", reviewed_at: Time.current, review_comment: nil)
        expect(note).not_to be_rejected
      end
    end
  end
end
