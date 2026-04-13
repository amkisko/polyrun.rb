#!/usr/bin/env ruby
require "fileutils"
require "pathname"

# Generates lib/demo/lattice/cell_NNN.rb + spec/demo/lattice/cell_NNN_spec.rb + spec/paths.txt for Polyrun demo apps.
# Output is gitignored under examples/. Invoked from spec/spec_helper.rb via ensure_lattice_spec_suite.rb (before RSpec
# runs). script/ci_prepare does not need to call this. Skip: POLYRUN_SKIP_LATTICE_GENERATE=1
# Usage: ruby examples/script/generate_lattice_spec_suite.rb examples/simple/simple_demo [COUNT]
# Default COUNT=120 (>= 100 per demo for partition/timing demos).

abort "usage: ruby #{$PROGRAM_NAME} <path/to/demo_rails_root> [count]" if ARGV.empty?

root = File.expand_path(ARGV[0])
count = (ARGV[1] || 120).to_i
abort "count must be >= 100" if count < 100

lib_dir = File.join(root, "lib", "demo", "lattice")
spec_dir = File.join(root, "spec", "demo", "lattice")
FileUtils.mkdir_p(lib_dir)
FileUtils.mkdir_p(spec_dir)

(1..count).each do |i|
  n = format("%03d", i)
  name = "Cell#{n}"
  lib_path = File.join(lib_dir, "cell_#{n}.rb")
  spec_path = File.join(spec_dir, "cell_#{n}_spec.rb")

  File.write(lib_path, <<~RUBY)
        # Demo lattice unit #{i} — pure Ruby for meaningful coverage in partition demos.
    module Demo
      module Lattice
        class #{name}
          INDEX = #{i}.freeze

          def self.value
            INDEX * INDEX + #{i % 7}
          end

          def self.pair
            [INDEX, value]
          end
        end
      end
    end
  RUBY

  File.write(spec_path, <<~RUBY)
        require "rails_helper"

    RSpec.describe Demo::Lattice::#{name} do
      it "returns a stable value for partition demos" do
        expect(described_class::INDEX).to eq(#{i})
        expect(described_class.value).to eq(#{i} * #{i} + #{i % 7})
      end

      it "returns a pair" do
        expect(described_class.pair).to eq([#{i}, described_class.value])
      end
    end
  RUBY
end

paths_file = File.join(root, "spec", "paths.txt")
root_pn = Pathname.new(root)
all_specs = Dir.glob(File.join(root, "spec", "**", "*_spec.rb")).sort
non_lattice = all_specs.reject { |p| p.include?("#{File::SEPARATOR}demo#{File::SEPARATOR}lattice#{File::SEPARATOR}") }
lines = non_lattice.map { |p| Pathname.new(p).relative_path_from(root_pn).to_s }
lines.concat((1..count).map { |i| format("spec/demo/lattice/cell_%03d_spec.rb", i) })
File.write(paths_file, lines.join("\n") + "\n")

puts "Wrote #{count} lattice pairs under #{root}"
puts "Updated #{paths_file}"
