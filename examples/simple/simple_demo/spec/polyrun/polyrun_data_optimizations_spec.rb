require "rails_helper"

RSpec.describe "Polyrun data helpers (demo)" do
  describe "CachedFixtures" do
    after(:all) { Polyrun::Data::CachedFixtures.reset! }

    it "builds once per process per key (memoized register)" do
      builds = 0
      a = Polyrun::Data::CachedFixtures.fetch(:polyrun_demo_counter) do
        builds += 1
        {built: true}
      end
      b = Polyrun::Data::CachedFixtures.fetch(:polyrun_demo_counter) do
        builds += 1
        {built: true}
      end
      expect(a.object_id).to eq(b.object_id)
      expect(builds).to eq(1)
    end
  end

  describe "ParallelProvisioning" do
    it "exposes shard index / total from Polyrun env" do
      expect(Polyrun::Data::ParallelProvisioning.shard_total).to be >= 1
      expect(Polyrun::Data::ParallelProvisioning.shard_index).to be >= 0
    end
  end
end
