# RFC 0009: Quick lifecycle and DSL

- Feature Name: quick-lifecycle-dsl
- Type: Standards Track
- Status: Stable
- Created: 2026-11-12
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0008

## Summary

Extend `Polyrun::Quick` with suite config hooks, `around`, error-aware `after`, `with` / `subject`, richer predicates (`be`, `be_a`, `raise_exception`), and per-example timing in the summary. Stdlib only.

## Motivation

Quick lacks suite wiring and wrap/cleanup hooks that parallel runners need for isolated resources. Predicates and `subject` reduce friction for Sus-style examples without adding gems.

## Guide-level explanation

```ruby
# config/polyrun_quick.rb
before_suite { add_load_path "fixtures" }
after_suite { |status| }
```

```ruby
describe String do
  subject { "hi" }

  with "length" do
    around do |run|
      run.call
    ensure
      # cleanup
    end

    after do |error|
      # error is nil on pass
    end

    it "is short" do
      expect(subject).to be_a(String)
      expect(subject.length).to be == 2
      expect { raise "x" }.to raise_exception(RuntimeError)
    end
  end
end
```

Summary prints slowest examples when any example ran.

## Reference-level explanation

- Load `config/polyrun_quick.rb` from the process cwd when present; DSL: `before_suite`, `after_suite`, `add_load_path`
- `around` hooks nest outer-to-inner; each receives a callable that runs the rest; failing to call it fails the example
- Example order: before hooks → around chain → example body → after hooks (always); after receives the example error or nil
- `with` aliases `describe`
- `subject` / `subject { }` memoized like `let(:subject)`; describing a Module/Class sets a default subject constructor when no explicit subject
- Matchers: `be ==` / comparisons via `be`, `be_a` / `be_kind_of`, `raise_exception` for block expectations
- Reporter records wall seconds per example; summary lists up to 5 slowest when verbose or when any failure (always list if any example >= 0.05s, else omit)

## Drawbacks

Richer DSL is more surface to maintain. Around that forgets `run.call` fails closed.

## Rationale and alternatives

- Copy Sus wholesale: rejected; Quick stays embedded and stdlib-only
- Only document Polyrun orchestration hooks: does not help per-example cleanup inside Quick
- pytest-style yield-only: Ruby blocks favor explicit `run.call` like Sus around

## Prior art

Sus around/after(error)/config; pytest yield teardown; Jest afterEach on failure; Go t.Cleanup; Spectator/behave around continuation.

## Unresolved questions

Whether suite config should also accept YAML under `polyrun.yml`.

## Future possibilities

Shared examples; before_all/after_all per group; fixtures auto-discovery beyond `add_load_path`.
