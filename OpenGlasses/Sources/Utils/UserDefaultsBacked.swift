import Foundation

/// A `UserDefaults`-backed value with an explicit default (Plan BG P5).
///
/// Replaces the repeated `static var x: Bool { UserDefaults.standard.bool(forKey: "x") }` getter +
/// `setX(_:)` setter boilerplate that `Config` carries hundreds of times. For a `Bool` toggle the
/// default is `false`, matching `UserDefaults.bool(forKey:)` for an absent key; the stored value is
/// an `NSNumber`, so `object(forKey:) as? Bool` reads back exactly what the old getter did.
///
/// `Config` keeps its `setX(_:)` functions as thin façades over the wrapped property, so existing
/// call sites (which use `Config.setX(v)`) are unchanged and any side effects in those setters are
/// preserved.
@propertyWrapper
struct UserDefaultsBacked<Value> {
    let key: String
    let defaultValue: Value
    let store: UserDefaults

    init(_ key: String, default defaultValue: Value, store: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.store = store
    }

    var wrappedValue: Value {
        get { store.object(forKey: key) as? Value ?? defaultValue }
        set { store.set(newValue, forKey: key) }
    }
}
