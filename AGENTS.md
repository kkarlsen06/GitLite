# Development Instructions

Always install the newest build to /Applications after making changes.

## Tab performance benchmark

Run `Scripts/benchmark-tabs.sh` after changes to repository tabs, workspace
restoration, lazy repository loading, loading and empty states, tab switching,
repository watcher ownership, or tab-related task cancellation. The benchmark
uses 20 isolated temporary repositories and checks unopened and loaded switch
latency, rapid cycling, memory growth, main-thread stalls, idle use, and orphan
watchers, processes, or tasks.
