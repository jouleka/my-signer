require "rails_helper"

RSpec.describe OrgSyncRun, type: :model do
  let(:organization) { create(:organization) }

  describe "validations" do
    it "requires job_name" do
      run = described_class.new(organization: organization, job_name: nil, status: "ok")
      expect(run).not_to be_valid
      expect(run.errors[:job_name]).to be_present
    end

    it "rejects unknown job_name" do
      run = described_class.new(organization: organization, job_name: "nope", status: "ok")
      expect(run).not_to be_valid
      expect(run.errors[:job_name]).to be_present
    end

    it "requires status in the allowed list" do
      run = described_class.new(organization: organization, job_name: "asc", status: "bogus")
      expect(run).not_to be_valid
      expect(run.errors[:status]).to be_present
    end

    it "enforces unique (organization_id, job_name)" do
      described_class.create!(organization: organization, job_name: "asc", status: "ok")
      dup = described_class.new(organization: organization, job_name: "asc", status: "running")
      expect(dup).not_to be_valid
      expect(dup.errors[:job_name]).to be_present
    end
  end

  describe ".record_started!" do
    it "upserts a row with status running and started_at set" do
      described_class.record_started!(organization: organization, job_name: "asc")
      row = described_class.find_by(organization: organization, job_name: "asc")
      expect(row.status).to eq("running")
      expect(row.started_at).to be_within(5.seconds).of(Time.current)
      expect(row.finished_at).to be_nil
      expect(row.error_message).to be_nil
    end

    it "resets finished_at/error_message when a previous run had failed" do
      described_class.create!(
        organization: organization, job_name: "asc", status: "error",
        started_at: 1.hour.ago, finished_at: 30.minutes.ago, error_message: "boom"
      )
      described_class.record_started!(organization: organization, job_name: "asc")
      row = described_class.find_by(organization: organization, job_name: "asc")
      expect(row.status).to eq("running")
      expect(row.finished_at).to be_nil
      expect(row.error_message).to be_nil
    end

    it "accepts job_name as a symbol" do
      described_class.record_started!(organization: organization, job_name: :reviews)
      expect(described_class.find_by(organization: organization, job_name: "reviews")).to be_present
    end

    it "recovers from a TOCTOU insert race without raising or duplicating (L-18)" do
      # Simulate a concurrent process inserting the (org, job_name) row between
      # our find_or_initialize_by and save!: the first save! raises
      # RecordNotUnique, and we must re-find + update the existing row instead.
      existing = described_class.create!(
        organization: organization, job_name: "asc", status: "error",
        started_at: 2.hours.ago, finished_at: 1.hour.ago, error_message: "boom"
      )

      raised = false
      allow_any_instance_of(described_class).to receive(:save!).and_wrap_original do |orig, *args|
        unless raised
          raised = true
          raise ActiveRecord::RecordNotUnique, "duplicate key"
        end
        orig.call(*args)
      end

      result = nil
      expect {
        result = described_class.record_started!(organization: organization, job_name: "asc")
      }.not_to change(described_class, :count)

      expect(result.id).to eq(existing.id)
      existing.reload
      expect(existing.status).to eq("running")
      expect(existing.finished_at).to be_nil
      expect(existing.error_message).to be_nil
    end
  end

  describe ".record_finished!" do
    before do
      described_class.record_started!(organization: organization, job_name: "asc")
    end

    it "marks status ok and sets finished_at when given :ok" do
      described_class.record_finished!(organization: organization, job_name: "asc", status: :ok)
      row = described_class.find_by(organization: organization, job_name: "asc")
      expect(row.status).to eq("ok")
      expect(row.finished_at).to be_within(5.seconds).of(Time.current)
    end

    it "stores a truncated error_message when given :error" do
      described_class.record_finished!(
        organization: organization, job_name: "asc",
        status: :error, error_message: "x" * 1000
      )
      row = described_class.find_by(organization: organization, job_name: "asc")
      expect(row.status).to eq("error")
      expect(row.error_message.length).to eq(500)
    end

    it "is a no-op when no prior started row exists" do
      other_org = create(:organization)
      expect(
        described_class.record_finished!(organization: other_org, job_name: "asc", status: :ok)
      ).to be_nil
    end
  end

  describe ".running?" do
    it "returns true when a row for that job has status running" do
      described_class.record_started!(organization: organization, job_name: "reviews")
      expect(described_class.running?(organization_id: organization.id, job_name: "reviews")).to be true
    end

    it "returns false when no row exists" do
      expect(described_class.running?(organization_id: organization.id, job_name: "reviews")).to be false
    end

    it "returns false after record_finished! is called" do
      described_class.record_started!(organization: organization, job_name: "reviews")
      described_class.record_finished!(organization: organization, job_name: "reviews", status: :ok)
      expect(described_class.running?(organization_id: organization.id, job_name: "reviews")).to be false
    end
  end
end
