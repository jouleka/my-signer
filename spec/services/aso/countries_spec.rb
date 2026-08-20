require "rails_helper"

RSpec.describe Aso::Countries do
  it "SUPPORTED includes major countries" do
    %w[us gb de fr jp cn in br au ca].each do |cc|
      expect(described_class::SUPPORTED).to include(cc)
    end
  end

  it "SUPPORTED contains only valid 2-letter lowercase ISO codes" do
    expect(described_class::SUPPORTED).to all(match(/\A[a-z]{2}\z/))
  end

  it "SUPPORTED is derived from Storefronts::IDS.keys" do
    expect(described_class::SUPPORTED.sort).to eq(Aso::Storefronts::IDS.keys.sort)
  end

  it "SUPPORTED is frozen" do
    expect(described_class::SUPPORTED).to be_frozen
  end
end
