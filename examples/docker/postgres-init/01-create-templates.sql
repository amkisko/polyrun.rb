-- Template databases for bin/polyrun db:setup-template / db:setup-shard (see examples/script/docker_polyrun_provision_demo.sh).
-- Runs once on first volume init. Names must match each demo's polyrun.yml databases.template_db.

CREATE DATABASE simple_demo_template;
CREATE DATABASE multi_demo_template;
CREATE DATABASE polyrepo_template;
