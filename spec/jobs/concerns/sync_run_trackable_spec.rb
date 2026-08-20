require "rails_helper"

class SyncRunTrackableDummyJob < ActiveJob::Base
  include SyncRunTrackable

  def perform(organization_id:, raise_with: nil, raise_class: StandardError)
    organization = Organization.find(organization_id)
    track_sync_run(organization: organization, job_name: :asc) do
      raise raise_class, raise_with if raise_with
      :ok_block_return
    end
  end
end

RSpec.describe SyncRunTrackable, type: :job do
  let(:organization) { create(:organization) }

  it "records a running row before the block runs and an ok row after" do
    SyncRunTrackableDummyJob.perform_now(organization_id: organization.id)

    run = OrgSyncRun.find_by(organization: organization, job_name: "asc")
    expect(run.status).to eq("ok")
    expect(run.started_at).to be_present
    expect(run.finished_at).to be_present
    expect(run.finished_at).to be >= run.started_at
  end

  it "records an error row and re-raises on block failure" do
    expect {
      SyncRunTrackableDummyJob.perform_now(organization_id: organization.id, raise_with: "kaboom")
    }.to raise_error(StandardError, "kaboom")

    run = OrgSyncRun.find_by(organization: organization, job_name: "asc")
    expect(run.status).to eq("error")
    expect(run.error_message).to eq("kaboom")
    expect(run.finished_at).to be_present
  end

  # Regression: the old inline sanitizer used `[^"]*`, which terminates at
  # the first escaped quote inside a JSON value and leaves the tail of the
  # secret unredacted. SyncRunTrackable must reuse the shared sanitizer so
  # escaped-quote payloads (inlined PEM bodies, nested error JSON) stay
  # redacted when the error is persisted to last_sync_error-style columns.
  it "redacts JSON values that contain escaped double-quotes" do
    msg = '{"private_key":"pre\"escaped\"tail","project_id":"ok"}'
    expect {
      SyncRunTrackableDummyJob.perform_now(organization_id: organization.id, raise_with: msg)
    }.to raise_error(StandardError)

    run = OrgSyncRun.find_by(organization: organization, job_name: "asc")
    expect(run.error_message).to include('"private_key":"[REDACTED]"')
    expect(run.error_message).not_to include("tail")
    expect(run.error_message).to include('"project_id":"ok"')
  end

  it "returns the block's return value on success" do
    dummy = Class.new do
      include SyncRunTrackable
    end.new

    value = dummy.send(:track_sync_run, organization: organization, job_name: :reviews) { :computed }
    expect(value).to eq(:computed)
  end

  # Regression: a non-StandardError exit (signal, SystemExit, graceful
  # thread kill during dev reload) used to leave the row stranded at
  # status=running because rescue StandardError didn't catch it. The ensure
  # block now finalizes the row before the exception propagates.
  it "finalizes the row as error when the block raises a non-StandardError" do
    expect {
      SyncRunTrackableDummyJob.perform_now(
        organization_id: organization.id,
        raise_with: "interrupted",
        raise_class: Interrupt
      )
    }.to raise_error(Interrupt)

    run = OrgSyncRun.find_by(organization: organization, job_name: "asc")
    expect(run.status).to eq("error")
    expect(run.finished_at).to be_present
    expect(run.error_message).to eq(SyncRunTrackable::ABORTED_ERROR_MESSAGE)
  end

  it "does not mask the original exception if the ensure-path write fails" do
    # Make the ensure-path record_finished! blow up. The original Interrupt
    # must still surface to the caller, not the swallowed secondary error.
    allow(OrgSyncRun).to receive(:record_finished!).and_wrap_original do |m, **kwargs|
      raise ActiveRecord::StatementInvalid, "db gone" if kwargs[:error_message] == SyncRunTrackable::ABORTED_ERROR_MESSAGE
      m.call(**kwargs)
    end

    expect {
      SyncRunTrackableDummyJob.perform_now(
        organization_id: organization.id,
        raise_with: "interrupted",
        raise_class: Interrupt
      )
    }.to raise_error(Interrupt)
  end
end
