import Foundation

/// One-shot migration of the stored `viewMode` UserDefaults Int from the
/// legacy 5-case enum to the new 9-case enum.
///
/// Legacy layout: editor=0, preview=1, split=2, gallery=3, carousel=4
/// New layout:    editor=0, preview=1, splitGallery=2, gallery=3,
///                splitList=4, list=5, splitLinks=6, links=7, carousel=8
///
/// The only raw-value shift is carousel (4 → 8). `split` renames to
/// `splitGallery` but keeps raw=2, so the stored Int is already correct
/// for everything except legacy carousel.
///
/// Because new raw=4 means `splitList` — colliding with legacy raw=4
/// (carousel) — the migration must run exactly once. A sticky flag
/// `viewModeMigratedToV2` gates it.
enum ViewModeMigration {
    static func migrate(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: "viewModeMigratedToV2") else { return }

        if let legacy = defaults.object(forKey: "viewMode") as? Int {
            let migrated: Int
            switch legacy {
            case 0: migrated = 0  // editor
            case 1: migrated = 1  // preview
            case 2: migrated = 2  // split → splitGallery
            case 3: migrated = 3  // gallery
            case 4: migrated = 8  // carousel (was 4, now 8)
            default: migrated = 0
            }
            defaults.set(migrated, forKey: "viewMode")
        }
        defaults.set(true, forKey: "viewModeMigratedToV2")
    }
}
