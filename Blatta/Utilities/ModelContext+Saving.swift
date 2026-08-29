import SwiftData

extension ModelContext {
    /// Saves pending changes. A failed save is rolled back so a later save
    /// cannot commit part of the failed operation.
    @discardableResult
    func saveOrRollback(reason: String) -> Bool {
        do {
            try save()
            return true
        } catch {
            rollback()
            AppLogger.dataStore.error(
                "Failed to \(reason); rolled back: \(error.localizedDescription)"
            )
            return false
        }
    }
}
