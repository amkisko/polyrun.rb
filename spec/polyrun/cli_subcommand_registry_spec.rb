require "spec_helper"

RSpec.describe "CLI subcommand registry" do
  it "builds IMPLICIT_PATH_EXCLUSION_TOKENS from dispatch names, CI shard commands, help, and version" do
    expected = (
      Polyrun::CLI::DISPATCH_SUBCOMMAND_NAMES +
        Polyrun::CLI::CI_SHARD_COMMANDS.keys +
        %w[help version]
    )
    expect(Polyrun::CLI::IMPLICIT_PATH_EXCLUSION_TOKENS.sort).to eq(expected.uniq.sort)
  end

  it "lists each dispatch subcommand in lib/polyrun/cli.rb (dispatch_cli_command_subcommands)" do
    cli_rb = File.expand_path("../../lib/polyrun/cli.rb", __dir__)
    source = File.read(cli_rb)
    Polyrun::CLI::DISPATCH_SUBCOMMAND_NAMES.each do |name|
      expect(source).to include(%(when "#{name}"))
    end
    expect(source).to include("when *CI_SHARD_COMMANDS.keys")
  end
end
