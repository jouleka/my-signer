require "rails_helper"

RSpec.describe Pricing::UsageBar do
  it "is a value struct with label, current, max, unit, is_projection, multiplier" do
    bar = described_class.new(
      label: "Media",
      current: 148,
      max: 300,
      unit: "MB",
      is_projection: false,
      multiplier: nil
    )

    expect(bar.label).to eq("Media")
    expect(bar.current).to eq(148)
    expect(bar.max).to eq(300)
    expect(bar.unit).to eq("MB")
    expect(bar.is_projection).to be(false)
    expect(bar.multiplier).to be_nil
  end

  it "computes percent for non-projection bars, clamped to 100" do
    expect(described_class.new(label: "x", current: 50, max: 100, unit: "MB", is_projection: false, multiplier: nil).percent).to eq(50)
    expect(described_class.new(label: "x", current: 200, max: 100, unit: "MB", is_projection: false, multiplier: nil).percent).to eq(100)
    expect(described_class.new(label: "x", current: 0, max: 0, unit: "MB", is_projection: false, multiplier: nil).percent).to eq(0)
  end

  it "returns nil percent for projection bars" do
    bar = described_class.new(label: "x", current: nil, max: 2048, unit: "MB", is_projection: true, multiplier: 6.7)
    expect(bar.percent).to be_nil
  end
end
