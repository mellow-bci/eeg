import Foundation

/// Body-derived metadata wire schema, separate from trained profile properties.
/// Dates/channel names remain raw wire values: Qt date normalization and the
/// runtime-initialized channel enum/default-list map are not replaced by guesses.
enum ReferenceTrainingMetadata {
    typealias Value = ReferenceProfileCodec.Value
    enum InputError: Error, Equatable {
        case unsupportedBoolean(String), unsupportedChannels, identifierMismatch
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

    /// Bounded native Bool domain. Numeric/string QVariant::toBool coercion is
    /// deliberately unsupported until its Qt implementation is traced.
    static func decode(_ object: [String: Value]) throws -> Profile {
        func string(_ key: String) -> String {
            if case .string(let value) = object[key] { return value }
            return "" // QJsonValue::toString's empty default; no number coercion.
        }
        func boolean(_ key: String) throws -> Bool {
            guard let value = object[key], value != .null else { return false }
            guard case .bool(let result) = value else { throw InputError.unsupportedBoolean(key) }
            return result
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
