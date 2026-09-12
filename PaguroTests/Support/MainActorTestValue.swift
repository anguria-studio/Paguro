/// Mutable fixture state shared by main-actor test callbacks.
@MainActor
final class MainActorTestValue<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
