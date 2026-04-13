require "spec_helper"

RSpec.describe Polyrun::Coverage::Merge do
  it "merges two large overlapping suites (100+ files, 300+ LOC each) without choking" do
    files = 110
    lines_per = 310
    a = {}
    b = {}
    files.times do |i|
      path = "/project/app/component_#{i}.rb"
      a[path] = {"lines" => Array.new(lines_per) { |j| j % 11 }}
      b[path] = {"lines" => Array.new(lines_per) { |j| j % 7 }}
    end

    merged = described_class.merge_two(a, b)
    expect(merged.size).to eq(files)
    expect(merged.keys).to match_array(files.times.map { |i| "/project/app/component_#{i}.rb" })
    expect(merged["/project/app/component_0.rb"]["lines"].size).to eq(lines_per)
    expect(merged["/project/app/component_0.rb"]["lines"][100]).to eq(100 % 11 + 100 % 7)
    expect(merged["/project/app/component_53.rb"]["lines"][200]).to eq(200 % 11 + 200 % 7)
    expect(merged["/project/app/component_109.rb"]["lines"][309]).to eq(309 % 11 + 309 % 7)
  end
end
