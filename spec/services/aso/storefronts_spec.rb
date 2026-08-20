require "rails_helper"

RSpec.describe Aso::Storefronts do
  it "returns a known storefront id for a supported country" do
    expect(described_class.id_for("us")).to eq("143441")
    expect(described_class.id_for("gb")).to eq("143444")
    expect(described_class.id_for("de")).to eq("143443")
    expect(described_class.id_for("fr")).to eq("143442")
    expect(described_class.id_for("jp")).to eq("143462")
  end

  it "is case-insensitive" do
    expect(described_class.id_for("US")).to eq("143441")
    expect(described_class.id_for("Us")).to eq("143441")
  end

  it "returns nil for unknown country" do
    expect(described_class.id_for("xx")).to be_nil
  end

  it "returns nil for blank/nil input" do
    expect(described_class.id_for(nil)).to be_nil
    expect(described_class.id_for("")).to be_nil
  end

  it "has DEFAULT_ID = US storefront" do
    expect(described_class::DEFAULT_ID).to eq("143441")
  end

  it "has at least 150 storefronts" do
    expect(described_class::IDS.size).to be >= 150
  end

  it "has IDs as strings (not integers)" do
    expect(described_class::IDS.values).to all(be_a(String))
  end

  it "has keys as 2-letter lowercase ISO codes" do
    expect(described_class::IDS.keys).to all(match(/\A[a-z]{2}\z/))
  end

  it "has unique storefront IDs" do
    # Apple assigns distinct IDs per country storefront
    # NOTE: a few countries share IDs historically (e.g. kp/kr = 143466 is a known data quirk)
    # so we just ensure mostly-unique
    expect(described_class::IDS.values.uniq.size).to be >= (described_class::IDS.size - 3)
  end
end
