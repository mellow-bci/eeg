import Foundation

/// Body-derived metadata wire schema, separate from trained profile properties.
/// Dates/channel names remain raw wire values. The separately traced date and
/// channel adapters normalize only when explicitly requested by their caller.
enum ReferenceTrainingMetadata {
    typealias Value = ReferenceProfileCodec.Value
    enum InputError: Error, Equatable {
        case unsupportedBoolean(String), unsupportedChannels, identifierMismatch
    }
    enum BooleanConversion {
        case strictNative
        /// Installed Qt6.8.3 scalar conversion, explicitly comparison-only.
        case qtBounded
    }
    struct Profile: Equatable {
        let uuid: String
        let name: String
        let ownerId: String
        let deleted: Bool
        let loaded: Bool
        let originalUuid: String
        let originalProfileURL: String
        let createdDatetime: String
        let modifiedDatetime: String
        /// nil means absent, [] means present empty. Kept distinguishable even
        /// though the vendor normalizes missing/empty arrays to a default list.
        let eegChannels: [String]?
        /// Our preservation policy; vendor constructor does not retain extras.
        let unknownFields: [String: Value]
        /// Original missing/non-string cases remain inspectable after toString's
        /// empty-string projection. They are not evidence of a valid date/UUID.
        let stringFieldsWithoutStringInput: Set<String>
    }
    private static let strings = ["uuid","name","ownerId","originalUuid",
                                  "originalProfileURL","createdDatetime","modifiedDatetime"]
    static let keys = Set(strings + ["deleted","loaded","eegChannels"])

    /// Strict native Boolean validation stays the repository default. Optional
    /// scalar Qt comparison mode is backed by installed-library oracle vectors.
    static func decode(_ object: [String: Value],
                       booleanConversion: BooleanConversion = .strictNative) throws -> Profile {
        func string(_ key: String) -> String {
            if case .string(let value) = object[key] { return value }
            return "" // QJsonValue::toString's empty default; no number coercion.
        }
        func boolean(_ key: String) throws -> Bool {
            guard let value = object[key], value != .null else { return false }
            if case .bool(let result) = value { return result }
            guard case .qtBounded = booleanConversion else { throw InputError.unsupportedBoolean(key) }
            switch value {
            case .string(let string):
                // ASCII comparison domain avoids unqualified Unicode case-folding parity.
                guard string.utf8.count <= 4096, string.utf8.allSatisfy({ $0 < 128 }) else {
                    throw InputError.unsupportedBoolean(key)
                }
                // No whitespace trimming. Qt converter lowercases before comparing.
                return !string.isEmpty && string != "0" && string.lowercased() != "false"
            case .number(let number):
                // JSON-finite exact-integer range is our supported comparison domain.
                // Qt converts Double through qRound64, not directly via number!=0.
                guard number.isFinite, abs(number) <= 9_007_199_254_740_991 else {
                    throw InputError.unsupportedBoolean(key)
                }
                return abs(number) >= 0.5
            default: throw InputError.unsupportedBoolean(key)
            }
        }
        let channels: [String]?
        if let value = object["eegChannels"] {
            guard case .array(let array) = value else { throw InputError.unsupportedChannels }
            channels = try array.map { item in
                guard case .string(let name) = item else { throw InputError.unsupportedChannels }
                return name
            }
        } else { channels = nil }
        let nonStrings = Set(strings.filter { key in
            if case .string = object[key] { return false }; return true
        })
        return Profile(uuid: string("uuid"),name: string("name"),ownerId: string("ownerId"),
            deleted: try boolean("deleted"),loaded: try boolean("loaded"),
            originalUuid: string("originalUuid"),originalProfileURL: string("originalProfileURL"),
            createdDatetime: string("createdDatetime"),modifiedDatetime: string("modifiedDatetime"),
            eegChannels: channels,unknownFields: object.filter { !keys.contains($0.key) },
            stringFieldsWithoutStringInput: nonStrings)
    }

    /// Our wire-preserving metadata serializer. It emits the observed types but
    /// does not pretend to perform QDateTime/channel enum normalization.
    /// Unknown keys are retained by our explicit independent storage policy.
    static func encode(_ profile: Profile) -> [String: Value] {
        var object = profile.unknownFields.filter { !keys.contains($0.key) }
        object.merge(["uuid":.string(profile.uuid),"name":.string(profile.name),"ownerId":.string(profile.ownerId),
            "deleted":.bool(profile.deleted),"loaded":.bool(profile.loaded),
            "originalUuid":.string(profile.originalUuid),"originalProfileURL":.string(profile.originalProfileURL),
            "createdDatetime":.string(profile.createdDatetime),"modifiedDatetime":.string(profile.modifiedDatetime)],
                     uniquingKeysWith: { _, value in value })
        if let channels = profile.eegChannels { object["eegChannels"] = .array(channels.map(Value.string)) }
        return object
    }

    /// Identity match is our repository consistency rule, not vendor UUID syntax.
    static func requireIdentity(_ profile: Profile, profileID: String) throws {
        guard profile.uuid == profileID else { throw InputError.identifierMismatch }
    }

    /// TrainingProfileAttributesInternal::toJsonObject exports only identity.
    /// The trained-properties QJsonObject is a separate store payload and is not
    /// nested under an invented metadata key.
    static func attributesIdentity(uuid: String) -> [String: Value] { ["uuid":.string(uuid)] }
}
