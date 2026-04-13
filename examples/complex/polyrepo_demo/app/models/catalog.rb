# Demo catalog shared by REST, GraphQL, and docs (no extra tables — keeps parallel CI cheap).
module Catalog
  module_function

  def items
    [
      { id: 1, slug: "widget", title: "Widget" },
      { id: 2, slug: "gadget", title: "Gadget" }
    ]
  end

  def find_by_slug(slug)
    items.find { |i| i[:slug] == slug.to_s }
  end
end
