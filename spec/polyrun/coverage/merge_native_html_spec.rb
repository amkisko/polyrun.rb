require "spec_helper"

RSpec.describe "Native HTML formatter integration" do
  before do
    skip "native extension not loaded" unless Polyrun::Coverage::Merge.native_acceleration?
  end

  def build_blob
    {
      "/project/app/models/user.rb" => {
        "lines" => [nil, 1, 0, 2, "ignored"],
        "branches" => [
          {"type" => "then", "start_line" => 2, "end_line" => 2, "coverage" => 1},
          {"type" => "else", "start_line" => 4, "end_line" => 4, "coverage" => 0}
        ]
      },
      "/project/lib/widget.rb" => {
        "lines" => [1, 1, 0],
        "branches" => [
          {"type" => "then", "start_line" => 1, "end_line" => 1, "coverage" => 2}
        ]
      }
    }
  end

  it "writes HTML line stats that match the Ruby line_counts fallback" do
    Dir.mktmpdir do |directory|
      root = File.join(directory, "project")
      app_models = File.join(root, "app", "models")
      lib_dir = File.join(root, "lib")
      FileUtils.mkdir_p(app_models)
      FileUtils.mkdir_p(lib_dir)
      File.write(File.join(app_models, "user.rb"), "x = 1\ny = 2\nz = 3\nw = 4\n")
      File.write(File.join(lib_dir, "widget.rb"), "a = 1\nb = 2\nc = 3\n")

      blob = build_blob
      result = Polyrun::Coverage::Result.new(
        blob,
        meta: {"title" => "Native HTML", "polyrun_coverage_root" => root},
        groups: {"App" => {"lines" => {"covered_percent" => 80.0}}}
      )
      formatter = Polyrun::Coverage::Formatter::HtmlFormatter.new(output_dir: directory, basename: "native")
      paths = formatter.format(result, output_dir: directory, basename: "native")
      html = File.read(paths[:html])

      blob.each do |path, entry|
        counts = Polyrun::Coverage::Merge.line_counts_ruby(entry)
        expect(html).to include(
          "#{counts[:covered]} / #{counts[:relevant]} relevant lines covered"
        )
      end
      expect(html).to include("Native HTML", "App")
    end
  end

  it "formats HTML after native merge_two matches Ruby merge output" do
    Dir.mktmpdir do |directory|
      left = build_blob
      right = build_blob.transform_values do |entry|
        merged_lines = entry["lines"].map { |hit| hit.is_a?(Integer) ? hit + 1 : hit }
        merged_branches = entry["branches"].map { |branch| branch.merge("coverage" => branch["coverage"] + 1) }
        entry.merge("lines" => merged_lines, "branches" => merged_branches)
      end

      merged = Polyrun::Coverage::Merge.merge_two(left, right)
      expect(merged).to eq(Polyrun::Coverage::Merge.merge_two_ruby(left, right))

      result = Polyrun::Coverage::Result.new(merged, meta: {"title" => "Merged"})
      formatter = Polyrun::Coverage::Formatter::HtmlFormatter.new(output_dir: directory, basename: "merged")
      paths = formatter.format(result, output_dir: directory, basename: "merged")
      html = File.read(paths[:html])

      merged.each do |_path, entry|
        counts = Polyrun::Coverage::Merge.line_counts_ruby(entry)
        expect(html).to include("#{counts[:covered]} / #{counts[:relevant]} relevant lines covered")
      end
    end
  end
end
