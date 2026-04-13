# Demo wiring for Polyrun::Data (see examples/fixtures_and_parallel_data.md).
Polyrun::Data::ParallelProvisioning.configure do |c|
  c.serial do
    # Single-process run: e.g. truncate + seeds, or one big DB setup.
    # Left empty in this demo — hook still runs so you can set breakpoints.
  end

  c.parallel_worker do
    # POLYRUN_SHARD_TOTAL > 1: lighter work per worker (e.g. seeds only).
    # Left empty — compare with serial when you add real DB setup.
  end
end
