require "rails_helper"

RSpec.describe Aso::RateLimiter do
  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }
  before { allow(Rails).to receive(:cache).and_return(memory_store) }

  describe ".acquire" do
    it "returns true on first call (no prior request)" do
      expect(described_class.acquire).to be true
    end

    it "writes the current timestamp to cache on success" do
      # travel_to truncates sub-seconds (stubs Time.now via Time.at(t.to_i)),
      # so freeze on a whole-second instant to keep the 0.1s tolerance meaningful.
      t0 = Time.at(Time.current.to_i)
      travel_to(t0) do
        described_class.acquire
        expect(Rails.cache.read(described_class::KEY).to_f).to be_within(0.1).of(t0.to_f)
      end
    end

    it "returns true after MIN_INTERVAL has elapsed" do
      described_class.acquire
      travel(described_class::MIN_INTERVAL + 1.second) do
        expect(described_class.acquire).to be true
      end
    end

    it "sleeps the remainder and returns true when wait is within MAX_WAIT" do
      described_class.acquire
      allow(described_class).to receive(:sleep)
      expect(described_class.acquire).to be true
      expect(described_class).to have_received(:sleep).with(a_value_between(0, described_class::MIN_INTERVAL))
    end

    it "returns false when required wait exceeds MAX_WAIT" do
      # Make MIN_INTERVAL temporarily > MAX_WAIT so any synchronous wait fails.
      stub_const("Aso::RateLimiter::MIN_INTERVAL", 20.seconds)
      described_class.acquire  # populates cache so next call needs a full wait
      expect(described_class.acquire).to be false
    end

    it "multiple acquires in sequence eventually succeed" do
      allow(described_class).to receive(:sleep)
      results = Array.new(3) { described_class.acquire }
      expect(results.count(true)).to be >= 1
    end

    it "clamps negative elapsed time (clock regression) at zero" do
      future = Time.current.to_f + 10_000  # clock was 10,000s in the future
      Rails.cache.write(described_class::KEY, future)
      # Now we appear to be 10,000s "behind" last
      allow(described_class).to receive(:sleep)
      expect(described_class.acquire).to be true  # should sleep at most MIN_INTERVAL, not 10,004s
      expect(described_class).to have_received(:sleep).with(a_value_between(0, described_class::MIN_INTERVAL.to_f))
    end
  end

  describe "Exhausted error" do
    it "is a distinct StandardError subclass" do
      expect(Aso::RateLimiter::Exhausted.ancestors).to include(StandardError)
    end

    it "can be raised and rescued" do
      expect { raise Aso::RateLimiter::Exhausted, "test" }
        .to raise_error(Aso::RateLimiter::Exhausted, "test")
    end
  end

  describe "constants" do
    it "MIN_INTERVAL is 4 seconds" do
      expect(described_class::MIN_INTERVAL).to eq(4.seconds)
    end

    it "MAX_WAIT is 10 seconds" do
      expect(described_class::MAX_WAIT).to eq(10.seconds)
    end

    it "KEY is namespaced" do
      expect(described_class::KEY).to match(%r{^aso/ratelimit/})
    end
  end
end
