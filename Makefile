.PHONY: trunk-fmt trunk-check lint native-extension release test test-coverage clean

trunk-fmt:
	trunk fmt

trunk-check:
	trunk check

lint:
	bundle exec rubocop
	bundle exec rbs -I sig validate

native-extension:
	cd ext/polyrun_coverage_merge && ruby extconf.rb && make
	bundle exec ruby -r polyrun/coverage/merge -e 'abort("native extension failed to load") unless Polyrun::Coverage::Merge.native_acceleration?'

release:
	ruby usr/bin/release.rb

test:
	rm -rf coverage
	bundle exec polyrun parallel-rspec --workers 5 --merge-failures

clean:
	-rm -f *.gem
	-rm -rf coverage tmp .bundle vendor/bundle .pray/cache
	-rm -f gemfiles/*.lock
	-find examples -depth -type d \
		\( -name log -o -name tmp -o -name storage -o -name node_modules -o -name coverage \) \
		-exec rm -rf {} +
	-find examples -depth -type d -path '*/vendor/bundle' -exec rm -rf {} +
	-find examples -depth -type d \
		\( -path '*/lib/demo/lattice' -o -path '*/spec/demo/lattice' \) \
		-exec rm -rf {} +
	-find examples -type f -path '*/spec/paths.txt' -delete
	-rm -rf examples/*/*/public/vite*
