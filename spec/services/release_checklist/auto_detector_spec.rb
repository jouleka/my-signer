require "rails_helper"

RSpec.describe ReleaseChecklist::AutoDetector, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:android_app) { create(:android_app, organization: organization) }

  let(:apple_checklist) do
    create(:release_checklist,
      organization: organization,
      listable: apple_app,
      version_string: "1.0.0",
      platform: "ios"
    )
  end

  let(:android_checklist) do
    create(:release_checklist,
      organization: organization,
      listable: android_app,
      version_string: "1.0.0",
      platform: "android"
    )
  end

  def build_apple_detector(app: apple_app, checklist: apple_checklist, org: organization)
    described_class.new(checklist: checklist, organization: org, app: app)
  end

  def build_android_detector(app: android_app, checklist: android_checklist, org: organization)
    described_class.new(checklist: checklist, organization: org, app: app)
  end

  def good_ios_listing(app)
    create(
      :store_listing, :ios,
      organization: organization,
      listable: app,
      locale: "en-US",
      description: "A really great app that helps users do amazing things every day.",
      privacy_policy_url: "https://example.com/privacy",
      support_url: "https://example.com/support"
    )
  end

  def good_android_listing(app)
    create(
      :store_listing, :android,
      organization: organization,
      listable: app,
      locale: "en-US",
      description: "A really great app that helps users do amazing things every day."
    )
  end

  describe "#detect" do
    context "when the app is neither AppleApp nor AndroidApp" do
      it "returns an empty array" do
        # Use a string as a stand-in to avoid app type matching either branch
        result = described_class.new(
          checklist: apple_checklist,
          organization: organization,
          app: Object.new
        ).detect
        expect(result).to eq([])
      end
    end

    context "happy path with no detectable issues for iOS" do
      before do
        build = create(:apple_build,
          organization: organization,
          apple_app: apple_app,
          raw_json: { "attributes" => { "usesNonExemptEncryption" => false } }
        )
        create(:app_store_version,
          apple_app: apple_app,
          organization: organization,
          version_string: "1.0.0",
          app_store_state: "READY_FOR_SALE",
          apple_build: build
        )
        good_ios_listing(apple_app)
        create(:release_note,
          organization: organization,
          listable: apple_app,
          version_string: "1.0.0",
          rendered_text: "NEW\n- Things"
        )
      end

      it "returns no items" do
        expect(build_apple_detector.detect).to eq([])
      end
    end
  end

  describe "iOS rules" do
    describe "#check_ios_rejected_version" do
      %w[REJECTED METADATA_REJECTED DEVELOPER_REJECTED].each do |state|
        it "fires when state is #{state}" do
          version = create(:app_store_version,
            apple_app: apple_app,
            organization: organization,
            version_string: "2.5.0",
            app_store_state: state
          )
          good_ios_listing(apple_app)

          items = build_apple_detector.detect
          issue = items.find { |i| i["key"] == "auto_ios_rejected_#{version.id}" }

          expect(issue).not_to be_nil
          expect(issue["severity"]).to eq("error")
          expect(issue["required"]).to be true
          expect(issue["source"]).to eq("app_store_connect")
          expect(issue["auto_detected"]).to be true
          expect(issue["category"]).to eq("issue")
          expect(issue["action_url"]).to include("appstoreconnect.apple.com")
        end
      end

      it "does not fire for non-rejected states" do
        create(:app_store_version,
          apple_app: apple_app,
          organization: organization,
          app_store_state: "READY_FOR_SALE"
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].start_with?("auto_ios_rejected") }).to be true
      end

      it "returns nil when no version exists" do
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].start_with?("auto_ios_rejected") }).to be true
      end
    end

    describe "#check_ios_invalid_binary" do
      it "fires when state is INVALID_BINARY" do
        version = create(:app_store_version,
          apple_app: apple_app,
          organization: organization,
          version_string: "3.0.0",
          app_store_state: "INVALID_BINARY"
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_ios_invalid_binary_#{version.id}" }

        expect(issue).not_to be_nil
        expect(issue["severity"]).to eq("error")
        expect(issue["required"]).to be true
        expect(issue["source"]).to eq("app_store_connect")
        expect(issue["label"]).to include("Invalid binary")
      end

      it "does not fire for non-INVALID_BINARY states" do
        create(:app_store_version,
          apple_app: apple_app,
          organization: organization,
          app_store_state: "READY_FOR_SALE"
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].include?("invalid_binary") }).to be true
      end
    end

    describe "#check_ios_missing_privacy_url" do
      it "fires when iOS listing is missing privacy_policy_url" do
        create(:store_listing, :ios,
          organization: organization,
          listable: apple_app,
          locale: "en-US",
          description: "A great app description that is plenty long enough.",
          support_url: "https://example.com/support",
          privacy_policy_url: nil
        )

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_ios_missing_privacy_url" }

        expect(issue).not_to be_nil
        expect(issue["severity"]).to eq("error")
        expect(issue["required"]).to be true
        expect(issue["source"]).to eq("local_check")
      end

      it "does not fire when privacy_policy_url is present" do
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"] == "auto_ios_missing_privacy_url" }).to be true
      end
    end

    describe "#check_ios_missing_support_url" do
      it "fires when support_url is blank" do
        create(:store_listing, :ios,
          organization: organization,
          listable: apple_app,
          locale: "en-US",
          description: "A great app description that is plenty long enough.",
          privacy_policy_url: "https://example.com/privacy",
          support_url: nil
        )

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_ios_missing_support_url" }

        expect(issue).not_to be_nil
        expect(issue["required"]).to be true
        expect(issue["severity"]).to eq("error")
      end

      it "does not fire when support_url is present" do
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"] == "auto_ios_missing_support_url" }).to be true
      end
    end

    describe "#check_ios_build_not_attached" do
      it "fires when PREPARE_FOR_SUBMISSION version has no build" do
        version = create(:app_store_version,
          apple_app: apple_app,
          organization: organization,
          version_string: "4.0.0",
          app_store_state: "PREPARE_FOR_SUBMISSION",
          apple_build_id: nil
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_ios_no_build_#{version.id}" }

        expect(issue).not_to be_nil
        expect(issue["severity"]).to eq("error")
        expect(issue["required"]).to be true
      end

      it "does not fire when build is attached" do
        build = create(:apple_build, organization: organization, apple_app: apple_app)
        create(:app_store_version,
          apple_app: apple_app,
          organization: organization,
          version_string: "4.0.0",
          app_store_state: "PREPARE_FOR_SUBMISSION",
          apple_build: build
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].include?("no_build") }).to be true
      end

      it "does not fire when state is not PREPARE_FOR_SUBMISSION" do
        create(:app_store_version,
          apple_app: apple_app,
          organization: organization,
          app_store_state: "READY_FOR_SALE",
          apple_build_id: nil
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].include?("no_build") }).to be true
      end
    end

    describe "#check_ios_encryption_compliance_unset" do
      it "fires when usesNonExemptEncryption is nil" do
        build = create(:apple_build,
          organization: organization,
          apple_app: apple_app,
          raw_json: { "attributes" => {} }
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_ios_encryption_unset_#{build.id}" }

        expect(issue).not_to be_nil
        expect(issue["severity"]).to eq("warning")
        expect(issue["required"]).to be false
        expect(issue["source"]).to eq("app_store_connect")
      end

      it "fires when raw_json is empty" do
        build = create(:apple_build,
          organization: organization,
          apple_app: apple_app,
          raw_json: {}
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_ios_encryption_unset_#{build.id}" }

        expect(issue).not_to be_nil
      end

      it "does not fire when usesNonExemptEncryption is true" do
        create(:apple_build,
          organization: organization,
          apple_app: apple_app,
          raw_json: { "attributes" => { "usesNonExemptEncryption" => true } }
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].include?("encryption_unset") }).to be true
      end

      it "does not fire when usesNonExemptEncryption is false" do
        create(:apple_build,
          organization: organization,
          apple_app: apple_app,
          raw_json: { "attributes" => { "usesNonExemptEncryption" => false } }
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].include?("encryption_unset") }).to be true
      end

      it "does not fire when no apple build exists" do
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].include?("encryption_unset") }).to be true
      end
    end

    describe "#check_ios_pre_submission_validation_errors (Phase 2)" do
      it "fires one item per stored validation error" do
        version = create(:app_store_version,
          organization: organization,
          apple_app: apple_app,
          version_string: "2.5.0",
          app_store_state: "PREPARE_FOR_SUBMISSION"
        )
        version.update_columns(issues: [
          { "code" => "MISSING_METADATA", "detail" => "Screenshots are required for iPhone 6.5\" Display.", "raw" => {} },
          { "code" => "INVALID_BINARY",    "detail" => "Binary is not signed.", "raw" => {} }
        ])
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        validation_items = items.select { |i| i["key"].start_with?("auto_ios_validation_#{version.id}_") }

        expect(validation_items.size).to eq(2)
        expect(validation_items.all? { |i| i["severity"] == "error" }).to be true
        expect(validation_items.all? { |i| i["required"] == true }).to be true
        expect(validation_items.all? { |i| i["source"] == "app_store_connect" }).to be true
        expect(validation_items.map { |i| i["detail"] }).to include(
          "Screenshots are required for iPhone 6.5\" Display.",
          "Binary is not signed."
        )
      end

      it "produces deterministic keys from the error code" do
        version = create(:app_store_version,
          organization: organization,
          apple_app: apple_app,
          version_string: "2.5.0",
          app_store_state: "PREPARE_FOR_SUBMISSION"
        )
        version.update_columns(issues: [
          { "code" => "MISSING_METADATA", "detail" => "Stuff missing." }
        ])
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        validation_items = items.select { |i| i["key"].start_with?("auto_ios_validation_") }

        expect(validation_items.first["key"]).to eq("auto_ios_validation_#{version.id}_MISSING_METADATA")
      end

      it "falls back to an index-based key suffix when code is blank" do
        version = create(:app_store_version,
          organization: organization,
          apple_app: apple_app,
          version_string: "2.5.0",
          app_store_state: "PREPARE_FOR_SUBMISSION"
        )
        version.update_columns(issues: [
          { "detail" => "Something broke." }
        ])
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        validation_items = items.select { |i| i["key"].start_with?("auto_ios_validation_") }

        expect(validation_items.size).to eq(1)
        expect(validation_items.first["key"]).to eq("auto_ios_validation_#{version.id}_err0")
      end

      it "does not fire when issues is empty" do
        create(:app_store_version,
          organization: organization,
          apple_app: apple_app,
          version_string: "2.5.0",
          app_store_state: "PREPARE_FOR_SUBMISSION"
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].start_with?("auto_ios_validation_") }).to be true
      end

      it "does not fire when no versions exist" do
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].start_with?("auto_ios_validation_") }).to be true
      end

      it "handles a malformed issues entry gracefully" do
        version = create(:app_store_version,
          organization: organization,
          apple_app: apple_app,
          version_string: "2.5.0",
          app_store_state: "PREPARE_FOR_SUBMISSION"
        )
        # Non-hash entry should be silently skipped
        version.update_columns(issues: [
          "not a hash",
          { "code" => "REAL_ERROR", "detail" => "This one is real." }
        ])
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        validation_items = items.select { |i| i["key"].start_with?("auto_ios_validation_") }
        expect(validation_items.size).to eq(1)
        expect(validation_items.first["detail"]).to eq("This one is real.")
      end
    end
  end

  describe "Android rules" do
    describe "#check_android_rollout_halted" do
      it "fires when an android track has a halted release" do
        create(:android_track,
          android_app: android_app,
          track_name: "production",
          raw_json: {
            "releases" => [
              { "name" => "1.0.0 (101)", "status" => "halted", "versionCodes" => [ "101" ] }
            ]
          }
        )
        good_android_listing(android_app)

        items = build_android_detector.detect
        issue = items.find { |i| i["key"] == "auto_android_rollout_halted" }

        expect(issue).not_to be_nil
        expect(issue["severity"]).to eq("error")
        expect(issue["required"]).to be true
        expect(issue["source"]).to eq("google_play")
      end

      it "does not fire for non-halted releases" do
        create(:android_track,
          android_app: android_app,
          track_name: "production",
          raw_json: {
            "releases" => [
              { "status" => "completed", "versionCodes" => [ "100" ] },
              { "status" => "inProgress", "versionCodes" => [ "101" ] }
            ]
          }
        )
        good_android_listing(android_app)

        items = build_android_detector.detect
        expect(items.none? { |i| i["key"] == "auto_android_rollout_halted" }).to be true
      end

      it "handles tracks with empty raw_json gracefully" do
        create(:android_track,
          android_app: android_app,
          track_name: "production",
          raw_json: {}
        )
        good_android_listing(android_app)

        expect { build_android_detector.detect }.not_to raise_error
      end
    end
  end

  describe "Shared rules" do
    describe "#check_missing_description" do
      it "fires when description is blank" do
        create(:store_listing, :ios,
          organization: organization,
          listable: apple_app,
          locale: "en-US",
          description: nil,
          privacy_policy_url: "https://example.com/privacy",
          support_url: "https://example.com/support"
        )

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_missing_description" }

        expect(issue).not_to be_nil
        expect(issue["severity"]).to eq("error")
        expect(issue["required"]).to be true
        expect(issue["source"]).to eq("local_check")
      end

      it "does not fire when description is present" do
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"] == "auto_missing_description" }).to be true
      end
    end

    describe "#check_release_notes_over_char_limit" do
      it "fires when iOS rendered_text exceeds 4000 chars" do
        good_ios_listing(apple_app)
        # Use update_columns to bypass the length validation on the model
        note = create(:release_note,
          organization: organization,
          listable: apple_app,
          version_string: "1.0.0",
          template_data: {},
          rendered_text: "a" * 100
        )
        note.update_columns(rendered_text: "a" * 4001)

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_release_notes_over_limit_#{note.id}" }

        expect(issue).not_to be_nil
        expect(issue["severity"]).to eq("error")
        expect(issue["required"]).to be true
        expect(issue["label"]).to include("4000")
      end

      it "fires when Android rendered_text exceeds 500 chars" do
        good_android_listing(android_app)
        note = create(:release_note, :android,
          organization: organization,
          listable: android_app,
          version_string: "1.0.0",
          template_data: {},
          rendered_text: "a" * 100
        )
        note.update_columns(rendered_text: "a" * 501)

        items = build_android_detector.detect
        issue = items.find { |i| i["key"] == "auto_release_notes_over_limit_#{note.id}" }

        expect(issue).not_to be_nil
        expect(issue["label"]).to include("500")
      end

      it "does not fire at exactly the char limit" do
        good_ios_listing(apple_app)
        create(:release_note,
          organization: organization,
          listable: apple_app,
          version_string: "1.0.0",
          template_data: {},
          rendered_text: "a" * 4000
        )

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].include?("over_limit") }).to be true
      end
    end

    describe "#check_release_notes_missing_for_version" do
      it "fires when iOS version exists but no release note matches" do
        build = create(:apple_build, organization: organization, apple_app: apple_app)
        create(:app_store_version,
          apple_app: apple_app,
          organization: organization,
          version_string: "7.0.0",
          app_store_state: "PREPARE_FOR_SUBMISSION",
          apple_build: build
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_release_notes_missing_for_7.0.0" }

        expect(issue).not_to be_nil
        expect(issue["severity"]).to eq("warning")
        expect(issue["required"]).to be false
      end

      it "does not fire when a release note exists for that version" do
        build = create(:apple_build, organization: organization, apple_app: apple_app)
        create(:app_store_version,
          apple_app: apple_app,
          organization: organization,
          version_string: "7.0.0",
          app_store_state: "PREPARE_FOR_SUBMISSION",
          apple_build: build
        )
        create(:release_note,
          organization: organization,
          listable: apple_app,
          version_string: "7.0.0",
          rendered_text: "NEW\n- Things"
        )
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"].include?("release_notes_missing_for") }).to be true
      end
    end

    describe "#check_untranslated_locales" do
      it "fires when at least one listing has needs_review status" do
        good_ios_listing(apple_app)
        create(:store_listing, :ios,
          organization: organization,
          listable: apple_app,
          locale: "de-DE",
          description: "Eine wirklich tolle App, die Benutzern hilft, jeden Tag Erstaunliches zu tun.",
          privacy_policy_url: "https://example.com/privacy",
          support_url: "https://example.com/support",
          translation_status: "needs_review"
        )

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_untranslated_locales" }

        expect(issue).not_to be_nil
        expect(issue["severity"]).to eq("info")
        expect(issue["required"]).to be false
        expect(issue["label"]).to include("1 locale")
      end

      it "does not fire when no listings need review" do
        good_ios_listing(apple_app)

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"] == "auto_untranslated_locales" }).to be true
      end
    end

    describe "#check_description_too_short" do
      it "fires when description is shorter than 20 chars" do
        create(:store_listing, :ios,
          organization: organization,
          listable: apple_app,
          locale: "en-US",
          description: "Short description.",  # 18 chars
          privacy_policy_url: "https://example.com/privacy",
          support_url: "https://example.com/support"
        )

        items = build_apple_detector.detect
        issue = items.find { |i| i["key"] == "auto_description_too_short" }

        expect(issue).not_to be_nil
        expect(issue["severity"]).to eq("info")
        expect(issue["required"]).to be false
      end

      it "does not fire at exactly 20 chars" do
        twenty = "a" * 20
        create(:store_listing, :ios,
          organization: organization,
          listable: apple_app,
          locale: "en-US",
          description: twenty,
          privacy_policy_url: "https://example.com/privacy",
          support_url: "https://example.com/support"
        )

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"] == "auto_description_too_short" }).to be true
      end

      it "does not fire when description is blank (covered by missing_description)" do
        create(:store_listing, :ios,
          organization: organization,
          listable: apple_app,
          locale: "en-US",
          description: nil,
          privacy_policy_url: "https://example.com/privacy",
          support_url: "https://example.com/support"
        )

        items = build_apple_detector.detect
        expect(items.none? { |i| i["key"] == "auto_description_too_short" }).to be true
      end
    end
  end

  describe "rule selection by app type" do
    it "runs only iOS + shared rules for an iOS app" do
      detector = build_apple_detector
      rule_list = detector.send(:rules)

      expect(rule_list).to include(:check_ios_rejected_version)
      expect(rule_list).to include(:check_missing_description)
      expect(rule_list).not_to include(:check_android_rollout_halted)
    end

    it "runs only Android + shared rules for an Android app" do
      detector = build_android_detector
      rule_list = detector.send(:rules)

      expect(rule_list).to include(:check_android_rollout_halted)
      expect(rule_list).to include(:check_missing_description)
      expect(rule_list).not_to include(:check_ios_rejected_version)
    end
  end

  describe "primary_store_listing for non-en-US apps" do
    it "finds the en-GB listing when AppleApp.primaryLocale is en-GB" do
      apple_app_en_gb = create(:apple_app, :en_gb_primary, organization: organization)
      checklist = create(:release_checklist,
        organization: organization,
        listable: apple_app_en_gb,
        version_string: "1.0.0",
        platform: "ios"
      )
      create(:store_listing, :ios,
        organization: organization,
        listable: apple_app_en_gb,
        locale: "en-GB",
        privacy_policy_url: "https://example.com/privacy",
        support_url: "https://example.com/support",
        description: "A really great app that helps users do amazing things every day."
      )
      # No en-US listing exists; primary_store_listing MUST find en-GB.

      detector = described_class.new(
        checklist: checklist,
        organization: organization,
        app: apple_app_en_gb
      )
      items = detector.detect

      # None of the listing-related "missing" rules should fire because the
      # en-GB listing is complete. If primary_store_listing were still
      # hardcoded to en-US, it would return nil and these rules would
      # silently be skipped — or, in other cases, fire incorrectly.
      expect(items.none? { |i| i["key"] == "auto_ios_missing_privacy_url" }).to be true
      expect(items.none? { |i| i["key"] == "auto_ios_missing_support_url" }).to be true
      expect(items.none? { |i| i["key"] == "auto_missing_description" }).to be true
    end

    it "fires missing_privacy_url against the en-GB listing when privacy URL is absent" do
      apple_app_en_gb = create(:apple_app, :en_gb_primary, organization: organization)
      checklist = create(:release_checklist,
        organization: organization,
        listable: apple_app_en_gb,
        version_string: "1.0.0",
        platform: "ios"
      )
      # The en-GB listing exists but does NOT have a privacy_policy_url.
      create(:store_listing, :ios,
        organization: organization,
        listable: apple_app_en_gb,
        locale: "en-GB",
        privacy_policy_url: nil,
        support_url: "https://example.com/support",
        description: "A really great app that helps users do amazing things every day."
      )

      detector = described_class.new(
        checklist: checklist,
        organization: organization,
        app: apple_app_en_gb
      )
      items = detector.detect
      issue = items.find { |i| i["key"] == "auto_ios_missing_privacy_url" }

      expect(issue).not_to be_nil
    end

    it "finds the de-DE listing when AndroidApp.default_language is de-DE" do
      android_app_de = create(:android_app, :de_de_primary, organization: organization)
      checklist = create(:release_checklist,
        organization: organization,
        listable: android_app_de,
        version_string: "1.0.0",
        platform: "android"
      )
      create(:store_listing, :android,
        organization: organization,
        listable: android_app_de,
        locale: "de-DE",
        description: "Eine wirklich tolle App, die Benutzern hilft, jeden Tag Erstaunliches zu tun."
      )

      detector = described_class.new(
        checklist: checklist,
        organization: organization,
        app: android_app_de
      )
      items = detector.detect

      expect(items.none? { |i| i["key"] == "auto_missing_description" }).to be true
      expect(items.none? { |i| i["key"] == "auto_description_too_short" }).to be true
    end
  end

  describe "contract conformance" do
    it "every returned item conforms to the contract shape" do
      # Trigger several rules at once
      create(:app_store_version,
        apple_app: apple_app,
        organization: organization,
        version_string: "9.0.0",
        app_store_state: "REJECTED",
        apple_build_id: nil
      )
      create(:store_listing, :ios,
        organization: organization,
        listable: apple_app,
        locale: "en-US",
        description: nil,
        privacy_policy_url: nil,
        support_url: nil
      )

      items = build_apple_detector.detect

      expect(items).not_to be_empty
      items.each do |item|
        expect(item.keys).to include(
          "key", "label", "detail", "severity", "required", "checked",
          "auto_detected", "source", "action_url", "category"
        )
        expect(item["auto_detected"]).to be true
        expect(item["checked"]).to be false
        expect(item["category"]).to eq("issue")
        expect(%w[error warning info]).to include(item["severity"])
        expect(%w[app_store_connect google_play local_check]).to include(item["source"])
        expect(item["key"]).to start_with("auto_")
      end
    end

    it "all items have auto_detected: true" do
      create(:app_store_version,
        apple_app: apple_app,
        organization: organization,
        app_store_state: "REJECTED"
      )

      items = build_apple_detector.detect
      items.each do |item|
        expect(item["auto_detected"]).to be true
      end
    end
  end
end
