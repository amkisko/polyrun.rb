.PHONY: trunk-fmt trunk-check lint release test clean

trunk-fmt:
	trunk fmt

trunk-check:
	trunk check

lint:
	bundle exec rubocop
	bundle exec rbs -I sig validate

release:
	ruby usr/bin/release.rb

test:
	bundle exec polyrun parallel-rspec --workers 5 --merge-failures

clean:
	rm -f *.gem
