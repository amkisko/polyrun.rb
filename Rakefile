require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = %w[--parallel]
end

task default: :spec
task ci: %i[spec rubocop]

desc "Run coverage merge benchmark (see benchmark/merge_coverage.rb for MERGE_FILES, MERGE_LINES, MERGE_REPS, …)"
task :bench_merge do
  ruby = Gem.ruby
  script = File.expand_path("benchmark/merge_coverage.rb", __dir__)
  exec(ruby, script)
end
