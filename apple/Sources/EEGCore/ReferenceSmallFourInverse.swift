import Foundation

/// Scalar-order 4x4 reference arithmetic. Addresses identify each rounded/FMA
/// operation in the pinned Cortex body; not a vendor asset or trained model.
/// Register-like slots intentionally expose evaluation order for auditability.
enum ReferenceSmallFourInverse {
    static func determinant(_ a: [Double]) -> Double {
        var v = [Double](repeating: 0, count: 30)
        v[2] = a[8]; v[1] = a[9] // 100b58c18
        v[3] = a[12]; v[4] = a[13] // 100b58c1c
        v[5] = v[3] * v[1] // 100b58c20
        v[0] = a[6]; v[6] = a[7] // 100b58c24
        v[7] = v[5] * v[0] // 100b58c28
        v[16] = v[2] * v[4] // 100b58c2c
        v[17] = -(v[16] * v[0]) // 100b58c30
        v[19] = a[2]; v[18] = a[3] // 100b58c34
        v[17] = v[18] * v[17] // 100b58c38
        v[7] = v[17].addingProduct(v[7], v[18]) // 100b58c3c
        v[20] = a[4]; v[17] = a[5] // 100b58c40
        v[21] = v[3] * v[17] // 100b58c44
        v[22] = a[10]; v[23] = a[11] // 100b58c48
        v[24] = -(v[21] * v[22]) // 100b58c4c
        v[7] = v[7].addingProduct(v[24], v[18]) // 100b58c50
        v[24] = v[4] * v[20] // 100b58c54
        v[25] = v[22] * v[24] // 100b58c58
        v[7] = v[7].addingProduct(v[25], v[18]) // 100b58c5c
        v[25] = v[2] * v[17] // 100b58c60
        v[26] = a[14]; v[27] = a[15] // 100b58c64
        v[28] = v[25] * v[26] // 100b58c68
        v[7] = v[7].addingProduct(v[28], v[18]) // 100b58c6c
        v[28] = v[1] * v[20] // 100b58c70
        v[29] = -(v[28] * v[26]) // 100b58c74
        v[7] = v[7].addingProduct(v[29], v[18]) // 100b58c78
        v[5] = -(v[5] * v[19]) // 100b58c7c
        v[5] = v[7].addingProduct(v[5], v[6]) // 100b58c80
        v[7] = v[16] * v[19] // 100b58c84
        v[5] = v[5].addingProduct(v[7], v[6]) // 100b58c88
        v[16] = a[0]; v[7] = a[1] // 100b58c8c
        v[3] = v[3] * v[7] // 100b58c90
        v[18] = v[22] * v[3] // 100b58c94
        v[5] = v[5].addingProduct(v[18], v[6]) // 100b58c98
        v[4] = v[4] * v[16] // 100b58c9c
        v[18] = -(v[4] * v[22]) // 100b58ca0
        v[5] = v[5].addingProduct(v[18], v[6]) // 100b58ca4
        v[2] = v[2] * v[7] // 100b58ca8
        v[18] = -(v[2] * v[26]) // 100b58cac
        v[5] = v[5].addingProduct(v[18], v[6]) // 100b58cb0
        v[1] = v[1] * v[16] // 100b58cb4
        v[18] = v[26] * v[1] // 100b58cb8
        v[5] = v[5].addingProduct(v[18], v[6]) // 100b58cbc
        v[6] = v[21] * v[19] // 100b58cc0
        v[5] = v[5].addingProduct(v[6], v[23]) // 100b58cc4
        v[6] = -(v[24] * v[19]) // 100b58cc8
        v[5] = v[5].addingProduct(v[6], v[23]) // 100b58ccc
        v[3] = -(v[3] * v[0]) // 100b58cd0
        v[3] = v[5].addingProduct(v[3], v[23]) // 100b58cd4
        v[4] = v[0] * v[4] // 100b58cd8
        v[3] = v[3].addingProduct(v[4], v[23]) // 100b58cdc
        v[4] = v[20] * v[7] // 100b58ce0
        v[5] = v[26] * v[4] // 100b58ce4
        v[3] = v[3].addingProduct(v[5], v[23]) // 100b58ce8
        v[5] = v[17] * v[16] // 100b58cec
        v[6] = -(v[5] * v[26]) // 100b58cf0
        v[3] = v[3].addingProduct(v[6], v[23]) // 100b58cf4
        v[6] = -(v[25] * v[19]) // 100b58cf8
        v[3] = v[3].addingProduct(v[6], v[27]) // 100b58cfc
        v[6] = v[28] * v[19] // 100b58d00
        v[3] = v[3].addingProduct(v[6], v[27]) // 100b58d04
        v[2] = v[0] * v[2] // 100b58d08
        v[2] = v[3].addingProduct(v[2], v[27]) // 100b58d0c
        v[0] = -(v[1] * v[0]) // 100b58d10
        v[0] = v[2].addingProduct(v[0], v[27]) // 100b58d14
        v[1] = -(v[4] * v[22]) // 100b58d18
        v[0] = v[0].addingProduct(v[1], v[27]) // 100b58d1c
        v[1] = v[22] * v[5] // 100b58d20
        v[0] = v[0].addingProduct(v[1], v[27]) // 100b58d24
        return v[0]
    }
    /// Caller validates shape/finiteness; nil requests the traced LU fallback.
    static func attempt(_ a: [Double]) -> [Double]? {
        let determinant = determinant(a)
        guard abs(determinant) >= ReferenceInverseDispatch.smallDeterminantThreshold else { return nil }
        var v = [Double](repeating: 0, count: 30)
        v[0] = determinant
        var result = [Double](repeating: 0, count: 16)
        v[2] = a[13]; v[1] = a[14] // 100b57a78
        v[3] = a[9]; v[4] = a[10] // 100b57a7c
        v[5] = v[3] * v[1] // 100b57a80
        v[6] = a[7] // 100b57a84
        v[7] = -(v[2] * v[4]) // 100b57a88
        v[7] = v[6] * v[7] // 100b57a8c
        v[5] = v[7].addingProduct(v[5], v[6]) // 100b57a90
        v[7] = a[5]; v[6] = a[6] // 100b57a94
        v[2] = v[2] * v[6] // 100b57a98
        v[16] = a[11] // 100b57a9c
        v[2] = v[5].addingProduct(v[2], v[16]) // 100b57aa0
        v[1] = -(v[7] * v[1]) // 100b57aa4
        v[1] = v[2].addingProduct(v[1], v[16]) // 100b57aa8
        v[2] = a[15] // 100b57aac
        v[3] = -(v[3] * v[6]) // 100b57ab0
        v[1] = v[1].addingProduct(v[3], v[2]) // 100b57ab4
        v[3] = v[4] * v[7] // 100b57ab8
        v[1] = v[1].addingProduct(v[3], v[2]) // 100b57abc
        v[1] = v[1] / v[0] // 100b57ac0
        result[0] = v[1] // 100b57ac4
        v[3] = a[9]; v[2] = a[10] // 100b57ac8
        v[4] = a[13]; v[5] = a[14] // 100b57acc
        v[6] = v[4] * v[2] // 100b57ad0
        v[7] = a[3] // 100b57ad4
        v[16] = -(v[3] * v[5]) // 100b57ad8
        v[16] = v[7] * v[16] // 100b57adc
        v[6] = v[16].addingProduct(v[6], v[7]) // 100b57ae0
        v[7] = a[11] // 100b57ae4
        v[17] = a[1]; v[16] = a[2] // 100b57ae8
        v[4] = -(v[4] * v[16]) // 100b57aec
        v[4] = v[6].addingProduct(v[4], v[7]) // 100b57af0
        v[5] = v[5] * v[17] // 100b57af4
        v[4] = v[4].addingProduct(v[5], v[7]) // 100b57af8
        v[3] = v[3] * v[16] // 100b57afc
        v[5] = a[15] // 100b57b00
        v[3] = v[4].addingProduct(v[3], v[5]) // 100b57b04
        v[2] = -(v[17] * v[2]) // 100b57b08
        v[2] = v[3].addingProduct(v[2], v[5]) // 100b57b0c
        v[2] = v[2] / v[0] // 100b57b10
        result[1] = v[2] // 100b57b14
        v[4] = a[13]; v[3] = a[14] // 100b57b18
        v[5] = a[5]; v[6] = a[6] // 100b57b1c
        v[7] = v[5] * v[3] // 100b57b20
        v[16] = a[3] // 100b57b24
        v[17] = -(v[4] * v[6]) // 100b57b28
        v[17] = v[16] * v[17] // 100b57b2c
        v[7] = v[17].addingProduct(v[7], v[16]) // 100b57b30
        v[17] = a[1]; v[16] = a[2] // 100b57b34
        v[4] = v[4] * v[16] // 100b57b38
        v[18] = a[7] // 100b57b3c
        v[4] = v[7].addingProduct(v[4], v[18]) // 100b57b40
        v[3] = -(v[17] * v[3]) // 100b57b44
        v[3] = v[4].addingProduct(v[3], v[18]) // 100b57b48
        v[4] = a[15] // 100b57b4c
        v[5] = -(v[5] * v[16]) // 100b57b50
        v[3] = v[3].addingProduct(v[5], v[4]) // 100b57b54
        v[5] = v[6] * v[17] // 100b57b58
        v[3] = v[3].addingProduct(v[5], v[4]) // 100b57b5c
        v[3] = v[3] / v[0] // 100b57b60
        result[2] = v[3] // 100b57b64
        v[5] = a[5]; v[4] = a[6] // 100b57b68
        v[6] = a[9]; v[7] = a[10] // 100b57b6c
        v[16] = v[6] * v[4] // 100b57b70
        v[17] = a[3] // 100b57b74
        v[18] = -(v[5] * v[7]) // 100b57b78
        v[18] = v[17] * v[18] // 100b57b7c
        v[16] = v[18].addingProduct(v[16], v[17]) // 100b57b80
        v[17] = a[7] // 100b57b84
        v[19] = a[1]; v[18] = a[2] // 100b57b88
        v[6] = -(v[6] * v[18]) // 100b57b8c
        v[6] = v[16].addingProduct(v[6], v[17]) // 100b57b90
        v[7] = v[7] * v[19] // 100b57b94
        v[6] = v[6].addingProduct(v[7], v[17]) // 100b57b98
        v[5] = v[5] * v[18] // 100b57b9c
        v[7] = a[11] // 100b57ba0
        v[5] = v[6].addingProduct(v[5], v[7]) // 100b57ba4
        v[4] = -(v[19] * v[4]) // 100b57ba8
        v[4] = v[5].addingProduct(v[4], v[7]) // 100b57bac
        v[4] = v[4] / v[0] // 100b57bb0
        result[3] = v[4] // 100b57bb4
        v[7] = a[11]; v[5] = a[12] // 100b57bb8
        v[6] = a[10] // 100b57bbc
        v[16] = v[5] * v[6] // 100b57bc0
        v[21] = a[7]; v[17] = a[8] // 100b57bc4
        v[18] = a[14]; v[19] = a[15] // 100b57bc8
        v[20] = -(v[17] * v[18]) // 100b57bcc
        v[22] = a[6] // 100b57bd0
        v[20] = v[21] * v[20] // 100b57bd4
        v[16] = v[20].addingProduct(v[16], v[21]) // 100b57bd8
        v[5] = -(v[5] * v[22]) // 100b57bdc
        v[5] = v[16].addingProduct(v[5], v[7]) // 100b57be0
        v[16] = a[4] // 100b57be4
        v[18] = v[18] * v[16] // 100b57be8
        v[5] = v[5].addingProduct(v[18], v[7]) // 100b57bec
        v[7] = v[17] * v[22] // 100b57bf0
        v[5] = v[5].addingProduct(v[7], v[19]) // 100b57bf4
        v[6] = -(v[16] * v[6]) // 100b57bf8
        v[5] = v[5].addingProduct(v[6], v[19]) // 100b57bfc
        v[5] = v[5] / v[0] // 100b57c00
        result[4] = v[5] // 100b57c04
        v[5] = a[8] // 100b57c08
        v[6] = a[14]; v[7] = a[15] // 100b57c0c
        v[16] = v[5] * v[6] // 100b57c10
        v[19] = a[11]; v[17] = a[12] // 100b57c14
        v[18] = a[10] // 100b57c18
        v[20] = -(v[17] * v[18]) // 100b57c1c
        v[22] = a[2]; v[21] = a[3] // 100b57c20
        v[20] = v[21] * v[20] // 100b57c24
        v[16] = v[20].addingProduct(v[16], v[21]) // 100b57c28
        v[17] = v[17] * v[22] // 100b57c2c
        v[16] = v[16].addingProduct(v[17], v[19]) // 100b57c30
        v[17] = a[0] // 100b57c34
        v[6] = -(v[17] * v[6]) // 100b57c38
        v[6] = v[16].addingProduct(v[6], v[19]) // 100b57c3c
        v[5] = -(v[5] * v[22]) // 100b57c40
        v[5] = v[6].addingProduct(v[5], v[7]) // 100b57c44
        v[6] = v[18] * v[17] // 100b57c48
        v[5] = v[5].addingProduct(v[6], v[7]) // 100b57c4c
        v[5] = v[5] / v[0] // 100b57c50
        result[5] = v[5] // 100b57c54
        v[5] = a[12] // 100b57c58
        v[6] = a[6]; v[7] = a[7] // 100b57c5c
        v[16] = v[5] * v[6] // 100b57c60
        v[21] = a[3]; v[17] = a[4] // 100b57c64
        v[18] = a[14]; v[19] = a[15] // 100b57c68
        v[20] = -(v[17] * v[18]) // 100b57c6c
        v[22] = a[2] // 100b57c70
        v[20] = v[21] * v[20] // 100b57c74
        v[16] = v[20].addingProduct(v[16], v[21]) // 100b57c78
        v[5] = -(v[5] * v[22]) // 100b57c7c
        v[5] = v[16].addingProduct(v[5], v[7]) // 100b57c80
        v[16] = a[0] // 100b57c84
        v[18] = v[18] * v[16] // 100b57c88
        v[5] = v[5].addingProduct(v[18], v[7]) // 100b57c8c
        v[7] = v[17] * v[22] // 100b57c90
        v[5] = v[5].addingProduct(v[7], v[19]) // 100b57c94
        v[6] = -(v[16] * v[6]) // 100b57c98
        v[5] = v[5].addingProduct(v[6], v[19]) // 100b57c9c
        v[5] = v[5] / v[0] // 100b57ca0
        result[6] = v[5] // 100b57ca4
        v[21] = a[3]; v[5] = a[4] // 100b57ca8
        v[6] = a[10]; v[7] = a[11] // 100b57cac
        v[16] = v[5] * v[6] // 100b57cb0
        v[19] = a[7]; v[17] = a[8] // 100b57cb4
        v[18] = a[6] // 100b57cb8
        v[20] = -(v[17] * v[18]) // 100b57cbc
        v[22] = a[2] // 100b57cc0
        v[20] = v[21] * v[20] // 100b57cc4
        v[16] = v[20].addingProduct(v[16], v[21]) // 100b57cc8
        v[17] = v[17] * v[22] // 100b57ccc
        v[16] = v[16].addingProduct(v[17], v[19]) // 100b57cd0
        v[17] = a[0] // 100b57cd4
        v[6] = -(v[17] * v[6]) // 100b57cd8
        v[6] = v[16].addingProduct(v[6], v[19]) // 100b57cdc
        v[5] = -(v[5] * v[22]) // 100b57ce0
        v[5] = v[6].addingProduct(v[5], v[7]) // 100b57ce4
        v[6] = v[18] * v[17] // 100b57ce8
        v[5] = v[5].addingProduct(v[6], v[7]) // 100b57cec
        v[5] = v[5] / v[0] // 100b57cf0
        result[7] = v[5] // 100b57cf4
        v[18] = a[12]; v[5] = a[13] // 100b57cf8
        v[7] = a[7]; v[6] = a[8] // 100b57cfc
        v[16] = v[6] * v[5] // 100b57d00
        v[17] = a[9] // 100b57d04
        v[19] = a[11] // 100b57d08
        v[20] = -(v[18] * v[17]) // 100b57d0c
        v[20] = v[7] * v[20] // 100b57d10
        v[7] = v[20].addingProduct(v[16], v[7]) // 100b57d14
        v[20] = a[4]; v[16] = a[5] // 100b57d18
        v[18] = v[18] * v[16] // 100b57d1c
        v[7] = v[7].addingProduct(v[18], v[19]) // 100b57d20
        v[5] = -(v[20] * v[5]) // 100b57d24
        v[5] = v[7].addingProduct(v[5], v[19]) // 100b57d28
        v[7] = a[15] // 100b57d2c
        v[6] = -(v[6] * v[16]) // 100b57d30
        v[5] = v[5].addingProduct(v[6], v[7]) // 100b57d34
        v[6] = v[17] * v[20] // 100b57d38
        v[5] = v[5].addingProduct(v[6], v[7]) // 100b57d3c
        v[5] = v[5] / v[0] // 100b57d40
        result[8] = v[5] // 100b57d44
        v[6] = a[8]; v[5] = a[9] // 100b57d48
        v[16] = a[11]; v[7] = a[12] // 100b57d4c
        v[17] = v[7] * v[5] // 100b57d50
        v[18] = a[3] // 100b57d54
        v[19] = a[13] // 100b57d58
        v[20] = -(v[6] * v[19]) // 100b57d5c
        v[20] = v[18] * v[20] // 100b57d60
        v[17] = v[20].addingProduct(v[17], v[18]) // 100b57d64
        v[20] = a[0]; v[18] = a[1] // 100b57d68
        v[7] = -(v[7] * v[18]) // 100b57d6c
        v[7] = v[17].addingProduct(v[7], v[16]) // 100b57d70
        v[17] = v[19] * v[20] // 100b57d74
        v[7] = v[7].addingProduct(v[17], v[16]) // 100b57d78
        v[6] = v[6] * v[18] // 100b57d7c
        v[16] = a[15] // 100b57d80
        v[6] = v[7].addingProduct(v[6], v[16]) // 100b57d84
        v[5] = -(v[20] * v[5]) // 100b57d88
        v[5] = v[6].addingProduct(v[5], v[16]) // 100b57d8c
        v[5] = v[5] / v[0] // 100b57d90
        result[9] = v[5] // 100b57d94
        v[6] = a[3]; v[5] = a[4] // 100b57d98
        v[16] = a[12]; v[7] = a[13] // 100b57d9c
        v[17] = v[5] * v[7] // 100b57da0
        v[18] = a[5] // 100b57da4
        v[19] = -(v[16] * v[18]) // 100b57da8
        v[19] = v[6] * v[19] // 100b57dac
        v[6] = v[19].addingProduct(v[17], v[6]) // 100b57db0
        v[19] = a[0]; v[17] = a[1] // 100b57db4
        v[16] = v[16] * v[17] // 100b57db8
        v[20] = a[7] // 100b57dbc
        v[6] = v[6].addingProduct(v[16], v[20]) // 100b57dc0
        v[7] = -(v[19] * v[7]) // 100b57dc4
        v[6] = v[6].addingProduct(v[7], v[20]) // 100b57dc8
        v[7] = a[15] // 100b57dcc
        v[5] = -(v[5] * v[17]) // 100b57dd0
        v[5] = v[6].addingProduct(v[5], v[7]) // 100b57dd4
        v[6] = v[18] * v[19] // 100b57dd8
        v[5] = v[5].addingProduct(v[6], v[7]) // 100b57ddc
        v[5] = v[5] / v[0] // 100b57de0
        result[10] = v[5] // 100b57de4
        v[18] = a[4]; v[5] = a[5] // 100b57de8
        v[7] = a[7]; v[6] = a[8] // 100b57dec
        v[16] = v[6] * v[5] // 100b57df0
        v[17] = a[3] // 100b57df4
        v[19] = a[9] // 100b57df8
        v[20] = -(v[18] * v[19]) // 100b57dfc
        v[20] = v[17] * v[20] // 100b57e00
        v[16] = v[20].addingProduct(v[16], v[17]) // 100b57e04
        v[20] = a[0]; v[17] = a[1] // 100b57e08
        v[6] = -(v[6] * v[17]) // 100b57e0c
        v[6] = v[16].addingProduct(v[6], v[7]) // 100b57e10
        v[16] = v[19] * v[20] // 100b57e14
        v[6] = v[6].addingProduct(v[16], v[7]) // 100b57e18
        v[7] = v[18] * v[17] // 100b57e1c
        v[16] = a[11] // 100b57e20
        v[6] = v[6].addingProduct(v[7], v[16]) // 100b57e24
        v[5] = -(v[20] * v[5]) // 100b57e28
        v[5] = v[6].addingProduct(v[5], v[16]) // 100b57e2c
        v[5] = v[5] / v[0] // 100b57e30
        result[11] = v[5] // 100b57e34
        v[6] = a[8]; v[5] = a[9] // 100b57e38
        v[7] = a[12]; v[16] = a[13] // 100b57e3c
        v[17] = v[7] * v[5] // 100b57e40
        v[18] = a[6] // 100b57e44
        v[19] = -(v[6] * v[16]) // 100b57e48
        v[19] = v[18] * v[19] // 100b57e4c
        v[17] = v[19].addingProduct(v[17], v[18]) // 100b57e50
        v[18] = a[10] // 100b57e54
        v[20] = a[4]; v[19] = a[5] // 100b57e58
        v[7] = -(v[7] * v[19]) // 100b57e5c
        v[7] = v[17].addingProduct(v[7], v[18]) // 100b57e60
        v[16] = v[16] * v[20] // 100b57e64
        v[7] = v[7].addingProduct(v[16], v[18]) // 100b57e68
        v[6] = v[6] * v[19] // 100b57e6c
        v[16] = a[14] // 100b57e70
        v[6] = v[7].addingProduct(v[6], v[16]) // 100b57e74
        v[5] = -(v[20] * v[5]) // 100b57e78
        v[5] = v[6].addingProduct(v[5], v[16]) // 100b57e7c
        v[5] = v[5] / v[0] // 100b57e80
        result[12] = v[5] // 100b57e84
        v[6] = a[12]; v[5] = a[13] // 100b57e88
        v[7] = a[8]; v[16] = a[9] // 100b57e8c
        v[17] = v[7] * v[5] // 100b57e90
        v[18] = a[2] // 100b57e94
        v[19] = -(v[6] * v[16]) // 100b57e98
        v[19] = v[18] * v[19] // 100b57e9c
        v[17] = v[19].addingProduct(v[17], v[18]) // 100b57ea0
        v[19] = a[0]; v[18] = a[1] // 100b57ea4
        v[6] = v[6] * v[18] // 100b57ea8
        v[20] = a[10] // 100b57eac
        v[6] = v[17].addingProduct(v[6], v[20]) // 100b57eb0
        v[5] = -(v[19] * v[5]) // 100b57eb4
        v[5] = v[6].addingProduct(v[5], v[20]) // 100b57eb8
        v[6] = a[14] // 100b57ebc
        v[7] = -(v[7] * v[18]) // 100b57ec0
        v[5] = v[5].addingProduct(v[7], v[6]) // 100b57ec4
        v[7] = v[16] * v[19] // 100b57ec8
        v[5] = v[5].addingProduct(v[7], v[6]) // 100b57ecc
        v[5] = v[5] / v[0] // 100b57ed0
        result[13] = v[5] // 100b57ed4
        v[6] = a[4]; v[5] = a[5] // 100b57ed8
        v[7] = a[12]; v[16] = a[13] // 100b57edc
        v[17] = v[7] * v[5] // 100b57ee0
        v[18] = a[2] // 100b57ee4
        v[19] = -(v[6] * v[16]) // 100b57ee8
        v[19] = v[18] * v[19] // 100b57eec
        v[17] = v[19].addingProduct(v[17], v[18]) // 100b57ef0
        v[18] = a[6] // 100b57ef4
        v[20] = a[0]; v[19] = a[1] // 100b57ef8
        v[7] = -(v[7] * v[19]) // 100b57efc
        v[7] = v[17].addingProduct(v[7], v[18]) // 100b57f00
        v[16] = v[16] * v[20] // 100b57f04
        v[7] = v[7].addingProduct(v[16], v[18]) // 100b57f08
        v[6] = v[6] * v[19] // 100b57f0c
        v[16] = a[14] // 100b57f10
        v[6] = v[7].addingProduct(v[6], v[16]) // 100b57f14
        v[5] = -(v[20] * v[5]) // 100b57f18
        v[5] = v[6].addingProduct(v[5], v[16]) // 100b57f1c
        v[5] = v[5] / v[0] // 100b57f20
        result[14] = v[5] // 100b57f24
        v[6] = a[8]; v[5] = a[9] // 100b57f28
        v[7] = a[4]; v[16] = a[5] // 100b57f2c
        v[17] = v[7] * v[5] // 100b57f30
        v[18] = a[2] // 100b57f34
        v[19] = -(v[6] * v[16]) // 100b57f38
        v[19] = v[18] * v[19] // 100b57f3c
        v[17] = v[19].addingProduct(v[17], v[18]) // 100b57f40
        v[19] = a[0]; v[18] = a[1] // 100b57f44
        v[6] = v[6] * v[18] // 100b57f48
        v[20] = a[6] // 100b57f4c
        v[6] = v[17].addingProduct(v[6], v[20]) // 100b57f50
        v[5] = -(v[19] * v[5]) // 100b57f54
        v[5] = v[6].addingProduct(v[5], v[20]) // 100b57f58
        v[6] = a[10] // 100b57f5c
        v[7] = -(v[7] * v[18]) // 100b57f60
        v[5] = v[5].addingProduct(v[7], v[6]) // 100b57f64
        v[7] = v[16] * v[19] // 100b57f68
        v[5] = v[5].addingProduct(v[7], v[6]) // 100b57f6c
        v[0] = v[5] / v[0] // 100b57f70
        result[15] = v[0] // 100b57f74
        v[0] = a[0] // 100b57f78
        v[5] = a[4] // 100b57f7c
        v[2] = v[2] * v[5] // 100b57f80
        v[0] = v[2].addingProduct(v[0], v[1]) // 100b57f84
        v[1] = a[8] // 100b57f88
        v[0] = v[0].addingProduct(v[1], v[3]) // 100b57f8c
        v[1] = a[12] // 100b57f90
        v[0] = v[0].addingProduct(v[1], v[4]) // 100b57f94
        guard abs(1-v[0]) < 1e-10 else { return nil }
        return result
    }
}
