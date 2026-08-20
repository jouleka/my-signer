require "rails_helper"

RSpec.describe ReleaseChecklist, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }

  describe "validations" do
    it "is valid with valid attributes" do
      checklist = build(:release_checklist, organization: organization, listable: apple_app)
      expect(checklist).to be_valid
    end

    it "validates platform inclusion" do
      checklist = build(:release_checklist, organization: organization, listable: apple_app, platform: "invalid")
      expect(checklist).not_to be_valid
      expect(checklist.errors[:platform]).to include("is not included in the list")
    end

    it "allows nil platform" do
      checklist = build(:release_checklist, organization: organization, listable: apple_app, platform: nil)
      expect(checklist).to be_valid
    end

    it "allows all valid platforms" do
      ReleaseChecklist::PLATFORMS.each do |platform|
        checklist = build(:release_checklist, organization: organization, listable: apple_app, platform: platform)
        expect(checklist).to be_valid, "Expected platform '#{platform}' to be valid"
      end
    end

    describe "items structure" do
      it "accepts valid items" do
        checklist = build(:release_checklist, organization: organization, listable: apple_app)
        expect(checklist).to be_valid
      end

      it "accepts empty items array" do
        checklist = build(:release_checklist, organization: organization, listable: apple_app, items: [])
        expect(checklist).to be_valid
      end

      it "rejects non-array items" do
        checklist = build(:release_checklist, organization: organization, listable: apple_app, items: "not an array")
        expect(checklist).not_to be_valid
        expect(checklist.errors[:items]).to include("must be an array")
      end

      it "rejects items without key" do
        checklist = build(:release_checklist, organization: organization, listable: apple_app,
          items: [ { "label" => "Missing key" } ])
        expect(checklist).not_to be_valid
        expect(checklist.errors[:items].first).to include("must have 'key' and 'label'")
      end

      it "rejects items without label" do
        checklist = build(:release_checklist, organization: organization, listable: apple_app,
          items: [ { "key" => "missing_label" } ])
        expect(checklist).not_to be_valid
        expect(checklist.errors[:items].first).to include("must have 'key' and 'label'")
      end

      it "rejects non-hash items" do
        checklist = build(:release_checklist, organization: organization, listable: apple_app,
          items: [ "not a hash" ])
        expect(checklist).not_to be_valid
        expect(checklist.errors[:items].first).to include("must have 'key' and 'label'")
      end
    end
  end

  describe "#check_item!" do
    let(:checklist) { create(:release_checklist, organization: organization, listable: apple_app) }

    it "checks the item by key" do
      checklist.check_item!("release_notes_written", user)

      item = checklist.items.find { |i| i["key"] == "release_notes_written" }
      expect(item["checked"]).to be true
    end

    it "records the user who checked" do
      checklist.check_item!("release_notes_written", user)

      item = checklist.items.find { |i| i["key"] == "release_notes_written" }
      expect(item["checked_by_id"]).to eq(user.id)
    end

    it "records the timestamp" do
      checklist.check_item!("release_notes_written", user)

      item = checklist.items.find { |i| i["key"] == "release_notes_written" }
      expect(item["checked_at"]).to be_present
    end

    it "persists the change" do
      checklist.check_item!("release_notes_written", user)

      checklist.reload
      item = checklist.items.find { |i| i["key"] == "release_notes_written" }
      expect(item["checked"]).to be true
    end

    it "returns false for unknown key" do
      result = checklist.check_item!("nonexistent_key", user)
      expect(result).to be false
    end

    it "handles nil user" do
      checklist.check_item!("release_notes_written", nil)

      item = checklist.items.find { |i| i["key"] == "release_notes_written" }
      expect(item["checked"]).to be true
      expect(item["checked_by_id"]).to be_nil
    end

    it "checks custom items by key" do
      checklist.add_custom_item!(label: "Review with QA", user: user)
      custom_key = checklist.custom_items.first["key"]

      result = checklist.check_item!(custom_key, user)
      expect(result).to be true

      checklist.reload
      item = checklist.custom_items.find { |i| i["key"] == custom_key }
      expect(item["checked"]).to be true
      expect(item["checked_by_id"]).to eq(user.id)
      expect(item["checked_at"]).to be_present
    end
  end

  describe "#uncheck_item!" do
    let(:checklist) { create(:release_checklist, :all_checked, organization: organization, listable: apple_app) }

    it "unchecks the item by key" do
      checklist.uncheck_item!("release_notes_written")

      item = checklist.items.find { |i| i["key"] == "release_notes_written" }
      expect(item["checked"]).to be false
    end

    it "clears checked_by_id and checked_at" do
      checklist.uncheck_item!("release_notes_written")

      item = checklist.items.find { |i| i["key"] == "release_notes_written" }
      expect(item["checked_by_id"]).to be_nil
      expect(item["checked_at"]).to be_nil
    end

    it "persists the change" do
      checklist.uncheck_item!("release_notes_written")

      checklist.reload
      item = checklist.items.find { |i| i["key"] == "release_notes_written" }
      expect(item["checked"]).to be false
    end

    it "returns false for unknown key" do
      result = checklist.uncheck_item!("nonexistent_key")
      expect(result).to be false
    end
  end

  describe "#completion_percentage" do
    it "returns correct percentage when no items checked" do
      checklist = create(:release_checklist, organization: organization, listable: apple_app)
      expect(checklist.completion_percentage).to eq(0)
    end

    it "returns correct percentage when some items checked" do
      checklist = create(:release_checklist, :partially_checked, organization: organization, listable: apple_app)
      # 1 out of 6 default items checked = 17% (rounded)
      expect(checklist.completion_percentage).to eq(17)
    end

    it "returns 100 when all items checked" do
      checklist = create(:release_checklist, :all_checked, organization: organization, listable: apple_app)
      expect(checklist.completion_percentage).to eq(100)
    end

    it "returns 0 for empty items" do
      checklist = build(:release_checklist, organization: organization, listable: apple_app, items: [], custom_items: [])
      expect(checklist.completion_percentage).to eq(0)
    end

    it "includes custom_items in calculation" do
      checklist = create(:release_checklist, organization: organization, listable: apple_app,
        custom_items: [ { "key" => "custom_1", "label" => "Custom check", "checked" => true } ])
      # 1 checked out of 7 total (6 default + 1 custom) = 14%
      expect(checklist.completion_percentage).to eq(14)
    end
  end

  describe "#ready_for_submission?" do
    it "returns true when all required items are checked" do
      checklist = create(:release_checklist, :all_checked, organization: organization, listable: apple_app)
      expect(checklist.ready_for_submission?).to be true
    end

    it "returns false when not all required items are checked" do
      checklist = create(:release_checklist, organization: organization, listable: apple_app)
      expect(checklist.ready_for_submission?).to be false
    end

    it "returns false when only optional items are checked" do
      checklist = create(:release_checklist, organization: organization, listable: apple_app)
      # screenshots_updated and description_reviewed are optional
      checklist.check_item!("screenshots_updated")
      checklist.check_item!("description_reviewed")
      expect(checklist.ready_for_submission?).to be false
    end

    it "returns true when all required items are checked but optional are not" do
      checklist = create(:release_checklist, organization: organization, listable: apple_app)
      # Check only the required items
      checklist.check_item!("release_notes_written", user)
      checklist.check_item!("all_locales_translated", user)
      checklist.check_item!("build_tested", user)
      expect(checklist.ready_for_submission?).to be true
    end
  end

  describe "compute_all_required_complete callback" do
    it "sets all_required_complete to true when all required items checked" do
      checklist = create(:release_checklist, organization: organization, listable: apple_app)
      checklist.check_item!("release_notes_written", user)
      checklist.check_item!("all_locales_translated", user)
      checklist.check_item!("build_tested", user)

      expect(checklist.reload.all_required_complete).to be true
    end

    it "sets all_required_complete to false when required items unchecked" do
      checklist = create(:release_checklist, :all_checked, organization: organization, listable: apple_app)
      checklist.uncheck_item!("release_notes_written")

      expect(checklist.reload.all_required_complete).to be false
    end
  end

  describe "#add_custom_item!" do
    let(:checklist) { create(:release_checklist, organization: organization, listable: apple_app) }

    it "adds a custom item with valid label" do
      result = checklist.add_custom_item!(label: "Review with QA team", user: user)

      expect(result).to be true
      checklist.reload
      expect(checklist.custom_items.size).to eq(1)

      item = checklist.custom_items.first
      expect(item["label"]).to eq("Review with QA team")
      expect(item["checked"]).to be false
      expect(item["required"]).to be false
      expect(item["category"]).to eq("custom")
      expect(item["created_by_id"]).to eq(user.id)
      expect(item["created_at"]).to be_present
      expect(item["key"]).to be_present
    end

    it "honors the required flag" do
      checklist.add_custom_item!(label: "Security review", required: true, user: user)

      item = checklist.custom_items.first
      expect(item["required"]).to be true
    end

    it "strips whitespace from label" do
      checklist.add_custom_item!(label: "   Trim me   ", user: user)

      item = checklist.custom_items.first
      expect(item["label"]).to eq("Trim me")
    end

    it "returns false for blank label" do
      result = checklist.add_custom_item!(label: "", user: user)

      expect(result).to be false
      expect(checklist.reload.custom_items).to be_empty
    end

    it "returns false for whitespace-only label" do
      result = checklist.add_custom_item!(label: "   ", user: user)

      expect(result).to be false
      expect(checklist.reload.custom_items).to be_empty
    end

    it "rejects duplicate labels (case insensitive)" do
      checklist.add_custom_item!(label: "Review docs", user: user)
      result = checklist.add_custom_item!(label: "REVIEW DOCS", user: user)

      expect(result).to be false
      expect(checklist.reload.custom_items.size).to eq(1)
    end

    it "rejects duplicate labels with extra whitespace" do
      checklist.add_custom_item!(label: "Review docs", user: user)
      result = checklist.add_custom_item!(label: "  Review docs  ", user: user)

      expect(result).to be false
      expect(checklist.reload.custom_items.size).to eq(1)
    end

    it "generates unique keys for items with similar labels" do
      # Pre-seed a custom item with key "custom_foo" and a non-matching label
      checklist.custom_items = [
        { "key" => "custom_foo", "label" => "Existing label", "checked" => false, "required" => false, "category" => "custom" }
      ]
      checklist.save!

      # Now adding "Foo" should not collide on label, but WOULD collide on key without counter
      checklist.add_custom_item!(label: "Foo", user: user)
      keys = checklist.reload.custom_items.map { |i| i["key"] }
      expect(keys).to include("custom_foo")
      expect(keys.uniq.size).to eq(keys.size)
      # The new item should have a suffix appended
      expect(keys.last).to eq("custom_foo_1")
    end

    it "generates sequential keys when same base already exists" do
      # Create items whose parameterized label collides
      checklist.custom_items = [
        { "key" => "custom_foo", "label" => "Existing A", "checked" => false, "required" => false, "category" => "custom" },
        { "key" => "custom_foo_1", "label" => "Existing B", "checked" => false, "required" => false, "category" => "custom" }
      ]
      checklist.save!

      checklist.add_custom_item!(label: "Foo", user: user)
      new_item = checklist.reload.custom_items.last
      expect(new_item["key"]).to eq("custom_foo_2")
    end

    it "works when custom_items is an empty array" do
      checklist.update_column(:custom_items, [])

      result = checklist.add_custom_item!(label: "First item", user: user)
      expect(result).to be true
      expect(checklist.reload.custom_items.size).to eq(1)
    end

    it "allows nil user" do
      result = checklist.add_custom_item!(label: "Solo item")

      expect(result).to be true
      item = checklist.reload.custom_items.first
      expect(item["created_by_id"]).to be_nil
    end
  end

  describe "#remove_custom_item!" do
    let(:checklist) { create(:release_checklist, organization: organization, listable: apple_app) }

    before do
      checklist.add_custom_item!(label: "Item A", user: user)
      checklist.add_custom_item!(label: "Item B", user: user)
    end

    it "removes the item with the given key" do
      key = checklist.custom_items.first["key"]

      result = checklist.remove_custom_item!(key)
      expect(result).to be true

      checklist.reload
      expect(checklist.custom_items.size).to eq(1)
      expect(checklist.custom_items.any? { |i| i["key"] == key }).to be false
    end

    it "returns false for unknown key" do
      result = checklist.remove_custom_item!("does_not_exist")

      expect(result).to be false
      expect(checklist.reload.custom_items.size).to eq(2)
    end

    it "returns false when custom_items is blank" do
      checklist.update_column(:custom_items, [])

      result = checklist.remove_custom_item!("custom_item_a")
      expect(result).to be false
    end

    it "persists the change" do
      key = checklist.custom_items.first["key"]
      checklist.remove_custom_item!(key)

      # fresh load
      fresh = ReleaseChecklist.find(checklist.id)
      expect(fresh.custom_items.size).to eq(1)
    end
  end

  describe "completion and required tracking with custom items" do
    let(:checklist) { create(:release_checklist, organization: organization, listable: apple_app) }

    it "includes custom items in completion_percentage" do
      checklist.add_custom_item!(label: "Custom one", user: user)
      # 0/7 = 0%
      expect(checklist.reload.completion_percentage).to eq(0)

      custom_key = checklist.custom_items.first["key"]
      checklist.check_item!(custom_key, user)
      # 1/7 = 14%
      expect(checklist.reload.completion_percentage).to eq(14)
    end

    it "considers custom required items in all_required_complete" do
      # All default required items checked
      checklist.check_item!("release_notes_written", user)
      checklist.check_item!("all_locales_translated", user)
      checklist.check_item!("build_tested", user)
      expect(checklist.reload.all_required_complete).to be true

      # Adding a required custom item should flip to false
      checklist.add_custom_item!(label: "Legal sign-off", required: true, user: user)
      expect(checklist.reload.all_required_complete).to be false

      # Checking it should flip back to true
      custom_key = checklist.custom_items.first["key"]
      checklist.check_item!(custom_key, user)
      expect(checklist.reload.all_required_complete).to be true
    end

    it "ignores non-required custom items for required completion" do
      checklist.check_item!("release_notes_written", user)
      checklist.check_item!("all_locales_translated", user)
      checklist.check_item!("build_tested", user)

      checklist.add_custom_item!(label: "Optional custom", required: false, user: user)
      expect(checklist.reload.all_required_complete).to be true
    end
  end

  describe "#auto_detected_items" do
    let(:checklist) { create(:release_checklist, organization: organization, listable: apple_app) }

    it "delegates to AutoDetector and returns its result" do
      fake_items = [ {
        "key" => "auto_test",
        "label" => "Test issue",
        "detail" => "Some detail",
        "severity" => "warning",
        "required" => false,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue"
      } ]

      expect(ReleaseChecklist::AutoDetector).to receive(:new).with(
        checklist: checklist,
        organization: organization,
        app: apple_app
      ).and_return(instance_double(ReleaseChecklist::AutoDetector, detect: fake_items))

      expect(checklist.auto_detected_items).to eq(fake_items)
    end

    it "returns empty array when listable is missing" do
      checklist_without_app = build(:release_checklist, organization: organization, listable: nil)
      expect(checklist_without_app.auto_detected_items).to eq([])
    end

    it "returns empty array and logs warning on error" do
      allow_any_instance_of(ReleaseChecklist::AutoDetector).to receive(:detect).and_raise(StandardError, "boom")
      expect(Rails.logger).to receive(:warn).with(/auto_detected_items failed/)

      # Reset memoization with a fresh instance
      result = checklist.auto_detected_items
      expect(result).to eq([])
    end

    it "memoizes the result" do
      detector = instance_double(ReleaseChecklist::AutoDetector, detect: [])
      expect(ReleaseChecklist::AutoDetector).to receive(:new).once.and_return(detector)

      checklist.auto_detected_items
      checklist.auto_detected_items
    end
  end

  describe "#all_items_merged" do
    let(:checklist) { create(:release_checklist, organization: organization, listable: apple_app) }

    it "returns items + custom_items + auto_detected_items" do
      checklist.add_custom_item!(label: "Custom A", user: user)
      auto_item = {
        "key" => "auto_xyz",
        "label" => "Auto",
        "detail" => "auto issue",
        "severity" => "warning",
        "required" => false,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue"
      }
      allow(checklist).to receive(:auto_detected_items).and_return([ auto_item ])

      merged = checklist.all_items_merged
      keys = merged.map { |i| i["key"] }
      expect(keys).to include("release_notes_written") # default
      expect(keys.any? { |k| k.start_with?("custom_") }).to be true
      expect(keys).to include("auto_xyz")
    end

    it "handles empty items and custom_items gracefully" do
      checklist.update_columns(items: [], custom_items: [])
      allow(checklist).to receive(:auto_detected_items).and_return([])
      expect(checklist.all_items_merged).to eq([])
    end
  end

  describe "#completion_percentage with auto-detected items" do
    let(:checklist) { create(:release_checklist, organization: organization, listable: apple_app) }

    it "includes auto-detected items in the denominator" do
      auto_item = {
        "key" => "auto_xyz",
        "label" => "Auto",
        "detail" => "auto issue",
        "severity" => "error",
        "required" => true,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue",
        "checked" => false
      }
      allow(checklist).to receive(:auto_detected_items).and_return([ auto_item ])

      # 0 checked / 7 total (6 default + 1 auto) = 0%
      expect(checklist.completion_percentage).to eq(0)

      checklist.check_item!("release_notes_written", user)
      # 1 checked / 7 total = 14%
      expect(checklist.completion_percentage).to eq(14)
    end
  end

  describe "compute_all_required_complete with auto-detected items" do
    let(:checklist) { create(:release_checklist, organization: organization, listable: apple_app) }

    it "ignores auto-detected items when computing all_required_complete" do
      blocking_auto_item = {
        "key" => "auto_blocker",
        "label" => "Auto blocker",
        "detail" => "an auto issue",
        "severity" => "error",
        "required" => true,
        "auto_detected" => true,
        "source" => "local_check",
        "action_url" => nil,
        "category" => "issue",
        "checked" => false
      }
      allow(checklist).to receive(:auto_detected_items).and_return([ blocking_auto_item ])

      # Check all default required items
      checklist.check_item!("release_notes_written", user)
      checklist.check_item!("all_locales_translated", user)
      checklist.check_item!("build_tested", user)

      # Even though there is a blocking auto-detected item, the persisted
      # callback ignores it.
      expect(checklist.reload.all_required_complete).to be true
    end
  end

  describe ".build_from_defaults" do
    it "builds a checklist with default items" do
      checklist = described_class.build_from_defaults(
        organization: organization,
        listable: apple_app,
        version_string: "2.0.0",
        platform: "ios"
      )

      expect(checklist).to be_a(ReleaseChecklist)
      expect(checklist.organization).to eq(organization)
      expect(checklist.items.size).to eq(ReleaseChecklist::DEFAULT_ITEMS.size)
      expect(checklist.version_string).to eq("2.0.0")
      expect(checklist.platform).to eq("ios")
    end

    it "returns an unsaved record" do
      checklist = described_class.build_from_defaults(organization: organization)
      expect(checklist).to be_new_record
    end

    it "deep copies default items so mutations are isolated" do
      checklist = described_class.build_from_defaults(organization: organization)
      checklist.items.first["checked"] = true

      expect(ReleaseChecklist::DEFAULT_ITEMS.first["checked"]).to be false
    end
  end
end
