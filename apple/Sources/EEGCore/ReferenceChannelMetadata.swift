/// Static channel vocabulary from the installed Cortex initializer, used only for
/// comparison normalization. Entries include metadata/motion channels, not 179
/// qualified electrodes or hardware configurations. Raw profile storage is unchanged.
enum ReferenceChannelMetadata {
    struct Projection: Equatable {
        let channelIDs: [UInt32]
        let usesDefaultList: Bool
        /// Nil means the vendor exporter omits eegChannels for the default list.
        let exportedNames: [String]?
    }

    static let defaultTrainingChannels: [UInt32] = [40,43,45,51,54,64,69,77,82,92,95,101,103,106]
    /// All IDs are contiguous 0...178 in this installed build. Case is significant.
    static let databaseNames: [String] = [
        "LA", // 0
        "LB", // 1
        "LC", // 2
        "LD", // 3
        "LE", // 4
        "LF", // 5
        "LG", // 6
        "LH", // 7
        "LJ", // 8
        "LK", // 9
        "LL", // 10
        "LM", // 11
        "LN", // 12
        "LO", // 13
        "LP", // 14
        "LQ", // 15
        "RA", // 16
        "RB", // 17
        "RC", // 18
        "RD", // 19
        "RE", // 20
        "RF", // 21
        "RG", // 22
        "RH", // 23
        "RJ", // 24
        "RK", // 25
        "RL", // 26
        "RM", // 27
        "RN", // 28
        "RO", // 29
        "RP", // 30
        "RQ", // 31
        "CMS", // 32
        "DRL", // 33
        "Cz", // 34
        "FCz", // 35
        "Fz", // 36
        "Afz", // 37
        "Fpz", // 38
        "Fp1", // 39
        "AF3", // 40
        "AF7", // 41
        "F9", // 42
        "F7", // 43
        "F5", // 44
        "F3", // 45
        "F1", // 46
        "FC1", // 47
        "C1", // 48
        "C3", // 49
        "FC3", // 50
        "FC5", // 51
        "FT7", // 52
        "FT9", // 53
        "T7", // 54
        "C5", // 55
        "TP9", // 56
        "TP7", // 57
        "CP5", // 58
        "CP3", // 59
        "CP1", // 60
        "P1", // 61
        "P3", // 62
        "P5", // 63
        "P7", // 64
        "P9", // 65
        "PO9", // 66
        "PO7", // 67
        "PO3", // 68
        "O1", // 69
        "O9", // 70
        "CPz", // 71
        "Pz", // 72
        "POz", // 73
        "Oz", // 74
        "Iz", // 75
        "O10", // 76
        "O2", // 77
        "PO4", // 78
        "PO8", // 79
        "PO10", // 80
        "P10", // 81
        "P8", // 82
        "P6", // 83
        "P4", // 84
        "P2", // 85
        "CP2", // 86
        "CP4", // 87
        "CP6", // 88
        "TP8", // 89
        "TP10", // 90
        "C6", // 91
        "T8", // 92
        "FT10", // 93
        "FT8", // 94
        "FC6", // 95
        "FC4", // 96
        "C4", // 97
        "C2", // 98
        "FC2", // 99
        "F2", // 100
        "F4", // 101
        "F6", // 102
        "F8", // 103
        "F10", // 104
        "AF8", // 105
        "AF4", // 106
        "Fp2", // 107
        "CTM1", // 108
        "CTM2", // 109
        "R8", // 110
        "R5", // 111
        "R4", // 112
        "R3", // 113
        "R1", // 114
        "E2", // 115
        "FP2", // 116
        "FP1", // 117
        "E1", // 118
        "L1", // 119
        "L3", // 120
        "L4", // 121
        "L5", // 122
        "L8", // 123
        "Ch-1", // 124
        "Ch-2", // 125
        "Ch-3", // 126
        "Ch-4", // 127
        "Ch-5", // 128
        "Ch-6", // 129
        "Ch-7", // 130
        "Ch-8", // 131
        "Ch-9", // 132
        "Ch-10", // 133
        "Ch-11", // 134
        "Ch-12", // 135
        "Ch-13", // 136
        "Ch-14", // 137
        "Ch-15", // 138
        "Ch-16", // 139
        "COUNTER", // 140
        "INTERPOLATED", // 141
        "PreCounterLeft", // 142
        "PreCounterRight", // 143
        "ToneLeft", // 144
        "ToneRight", // 145
        "RAW_CQ", // 146
        "OVERALL", // 147
        "FwBufferSize", // 148
        "FwClockTime", // 149
        "MARKER", // 150
        "MARKER_HARDWARE", // 151
        "TIMESTAMP", // 152
        "MarkerValueInt", // 153
        "MarkerType", // 154
        "MarkerIndex", // 155
        "RESERVED", // 156
        "HighBitFlex", // 157
        "BATTERY", // 158
        "BatteryLeftPercent", // 159
        "BatteryRightPercent", // 160
        "BATTERY_PERCENT", // 161
        "SaturationFlag", // 162
        "UNUSED", // 163
        "COUNTER_MEMS", // 164
        "INTERPOLATED_MEMS", // 165
        "Q0", // 166
        "Q1", // 167
        "Q2", // 168
        "Q3", // 169
        "GYROX", // 170
        "GYROY", // 171
        "GYROZ", // 172
        "ACCX", // 173
        "ACCY", // 174
        "ACCZ", // 175
        "MAGX", // 176
        "MAGY", // 177
        "MAGZ", // 178
    ]

    static func databaseName(for channelID: UInt32) -> String {
        guard channelID < UInt32(databaseNames.count) else { return "UNUSED" }
        return databaseNames[Int(channelID)]
    }

    static func databaseID(for name: String) -> UInt32 {
        // QString equalStrings compares UTF-16 code units, with no case folding.
        // Map iteration is ascending unsigned enum ID: first equal name wins.
        guard let index = databaseNames.firstIndex(where: { Array($0.utf16) == Array(name.utf16) }) else { return 0 }
        return UInt32(index)
    }

    /// Accepts the string-only projection exposed by ReferenceTrainingMetadata.
    /// QVariant coercion of non-string JSON values remains outside this contract.
    static func normalizeTrainingChannels(_ names: [String]?) -> Projection {
        guard let names, !names.isEmpty else {
            return Projection(channelIDs: defaultTrainingChannels, usesDefaultList: true, exportedNames: nil)
        }
        let ids = names.map { databaseID(for: $0) }
        return Projection(channelIDs: ids, usesDefaultList: false,
                          exportedNames: ids.map { databaseName(for: $0) })
    }
}
