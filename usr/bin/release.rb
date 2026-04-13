#!/usr/bin/env ruby

require "shellwords"

def execute_command(command)
  green = "\033[0;32m"
  red = "\033[1;31m"
  nc = "\033[0m"

  puts "#{green}#{command}#{nc}"
  unless system(command)
    puts "#{red}Command failed: #{command}#{nc}"
    exit 1
  end
end

root_dir = File.expand_path(File.join(File.dirname(__FILE__), "../.."))
root_q = Shellwords.escape(root_dir)

execute_command("cd #{root_q} && bundle")
execute_command("cd #{root_q} && bundle exec appraisal generate")
execute_command("cd #{root_q} && bundle exec rubocop -a 2>&1 | tee tmp/rubocop.log")
execute_command("cd #{root_q} && bundle exec rspec 2>&1 | tee tmp/rspec.log")

puts "Tests passed. Checking git status..."

git_status = `git diff --shortstat 2>/dev/null`.strip
unless git_status.empty?
  puts "\033[1;31mgit working directory not clean, please commit your changes first \033[0m"
  puts "\033[1;33mNote: rubocop -a may have modified files. Review and commit changes before releasing.\033[0m"
  exit 1
end

gem_name = "polyrun"
version_file = File.join(root_dir, "lib/polyrun/version.rb")
version_content = File.read(version_file)
version = version_content.match(/VERSION\s*=\s*"([0-9.]+)"/)[1]
gem_file = "#{gem_name}-#{version}.gem"

execute_command("cd #{root_q} && gem build #{gem_name}.gemspec")

puts "Ready to release #{gem_file} #{version}"
print "Continue? [Y/n] "
answer = $stdin.gets.chomp
unless answer == "Y" || answer.empty?
  puts "Exiting"
  exit 1
end

execute_command("cd #{root_q} && gem push #{gem_file}")
execute_command("cd #{root_q} && git tag #{version} && git push --tags")
execute_command("cd #{root_q} && gh release create #{version} --generate-notes")
