# frozen_string_literal: true

# Loaded from each example app's spec/spec_helper.rb before RSpec discovers *_spec.rb files.
# Uses a lock so parallel run-shards workers serialize generation.
require "fileutils"
require "rbconfig"

module PolyrunExample
  module LatticeSuite
    MIN_LATTICE_SPECS = 100

    def self.ensure!(rails_root)
      return if ENV["POLYRUN_SKIP_LATTICE_GENERATE"] == "1"

      rails_root = File.expand_path(rails_root)
      examples_dir = File.expand_path("..", File.expand_path("..", rails_root))
      script = File.join(examples_dir, "script", "generate_lattice_spec_suite.rb")
      return unless File.file?(script)

      paths_file = File.join(rails_root, "spec", "paths.txt")
      lattice_glob = File.join(rails_root, "spec", "demo", "lattice", "cell_*_spec.rb")
      n = Dir.glob(lattice_glob).size
      return if File.file?(paths_file) && n >= MIN_LATTICE_SPECS

      FileUtils.mkdir_p(File.join(rails_root, "tmp"))
      lock_path = File.join(rails_root, "tmp", ".lattice_spec_suite.lock")
      File.open(lock_path, File::CREAT | File::RDWR) do |lock|
        lock.flock(File::LOCK_EX)
        n2 = Dir.glob(lattice_glob).size
        return if File.file?(paths_file) && n2 >= MIN_LATTICE_SPECS

        ok = system(RbConfig.ruby, script, rails_root.to_s)
        raise "lattice generator failed: #{script}" unless ok
      end
    end
  end
end
