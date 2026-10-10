/// Numeric installed Cortex native C4 error-domain adapter, comparison only.
/// These are not SQLite errors or portable C4 enum names. Body/table evidence:
/// native-database-continuation-20261011, errorFromCouchbaseLiteCore101f00374.
enum ReferenceNativeDatabaseError {
    static func map(domain: Int32, code: Int32) -> Int32 {
        guard code > 0 else { return 0 }
        switch domain {
        case 1: return code < 33 ? code : 65535
        case 2: return 35
        case 3: return 33
        case 4: return 34
        case 7: return 36
        default: return 65535
        }
    }
}
