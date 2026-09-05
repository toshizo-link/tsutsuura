import Foundation

enum PersonalMarkRequirement {
    static func hasDrawing(_ mark: String?) -> Bool {
        guard let mark else { return false }
        return mark.utf8.count == 256
            && mark.utf8.allSatisfy { $0 == 48 || $0 == 49 }
            && mark.utf8.contains(49)
    }

    static func requiresSetup(for profile: UserProfile) -> Bool {
        !hasDrawing(profile.avatarMark)
    }
}
