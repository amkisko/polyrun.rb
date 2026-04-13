require "open3"

module PolyrunCliHelpers
  def polyrun(*args)
    root = File.expand_path("../..", __dir__)
    bin = File.join(root, "bin", "polyrun")
    Open3.capture2e({"RUBYOPT" => nil}, "ruby", bin, *args)
  end
end
