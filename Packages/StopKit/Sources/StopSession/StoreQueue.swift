/// Runs store writes one at a time, in order, so a final clear can't be overtaken by an earlier save.
@MainActor
final class StoreQueue {
    let store: any GameStore
    private var tail: Task<Void, Never>?

    init(_ store: any GameStore) {
        self.store = store
    }

    func enqueue(_ operation: @escaping @MainActor (any GameStore) async -> Void) {
        let previous = tail
        let store = store
        tail = Task {
            await previous?.value
            await operation(store)
        }
    }
}
