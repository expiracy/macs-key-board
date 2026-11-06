import Foundation

/// Decides what passthrough does from the profiles and what is in front: the first switched-on
/// profile that covers the front app and whose conditions hold acts; with none, or while paused,
/// macOS keeps all its shortcuts.
public enum PassthroughPlanner {
    public static func plan(profiles: [PassthroughProfile], context: AppContext,
                            paused: Bool = false) -> PassthroughPlan {
        guard !paused,
              let profile = profiles.first(where: {
                  $0.isEnabled && $0.covers(bundleID: context.bundleID) && $0.conditions.isSatisfied(by: context)
              })
        else { return .inactive }
        return PassthroughPlan(profileID: profile.id, profileName: profile.name, processID: context.processID,
                               disabledHotKeys: profile.systemShortcuts.hotKeyIDs,
                               captureAllKeys: profile.captureAllKeys, modifierLayout: profile.modifierLayout)
    }
}
