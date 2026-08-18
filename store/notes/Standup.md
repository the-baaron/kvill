# Standup, Thursday

Kept short on purpose. Anything that needs a discussion gets a line here and a meeting later, never the other way around.

## Yesterday

Finished the retry logic in the sync worker. It now backs off exponentially and gives up after an hour instead of hammering a dead endpoint all night.

```swift
// Every command has a key. The insert menu opens on /
func delay(for attempt: Int) -> Duration {
    .seconds(min(3600, 1 << attempt))
}
```

## Today

Writing the migration note. Blocked on nothing.

## In the way

The staging certificate expires on Sunday and nobody owns renewing it.
