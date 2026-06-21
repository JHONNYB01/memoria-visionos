import RealityKit
import simd

extension MeshResource {

    /// Cilindro cavo (anello a sezione rettangolare):
    /// l'utente ci entra dentro e vede i quadri dall'interno.
    /// - ringRadius:   raggio interno dell'anello
    /// - thickness:    spessore della parete (default 0.03 m)
    /// - height:       altezza della fascia (default 0.12 m)
    /// - segments:     divisioni angolari (default 64)
    static func generateHollowCylinder(
        ringRadius: Float,
        thickness: Float = 0.000001,
        height: Float = 6.0,
        segments: Int = 64
    ) -> MeshResource {

        var positions: [SIMD3<Float>] = []
        var normals:   [SIMD3<Float>] = []
        var uvs:       [SIMD2<Float>] = []
        var indices:   [UInt32]       = []

        let outerR = ringRadius + thickness / 2
        let innerR = ringRadius - thickness / 2
        let halfH  = height / 2

        // Genera vertici per le 4 superfici:
        // 0 = parete esterna, 1 = parete interna,
        // 2 = corona superiore, 3 = corona inferiore

        func addRing(radius: Float, y: Float, normalDir: SIMD3<Float>,
                     uOffset: Float) {
            for i in 0...segments {
                let angle = Float(i) / Float(segments) * 2 * .pi
                let x = cos(angle) * radius
                let z = sin(angle) * radius
                positions.append(SIMD3<Float>(x, y, z))
                normals.append(normalDir)
                uvs.append(SIMD2<Float>(Float(i) / Float(segments) + uOffset,
                                        (y + halfH) / height))
            }
        }

        let step = UInt32(segments + 1)

        // ── Parete esterna (normale verso fuori) ──────────────────
        let extBase = UInt32(positions.count)
        addRing(radius: outerR, y: -halfH,
                normalDir: SIMD3<Float>(cos(0), 0, sin(0)), uOffset: 0)
        addRing(radius: outerR, y:  halfH,
                normalDir: SIMD3<Float>(cos(0), 0, sin(0)), uOffset: 0)
        for i in 0..<UInt32(segments) {
            let b = extBase + i
            let t = extBase + step + i
            indices += [b, t, b+1, b+1, t, t+1]
        }
        // ricalcola normali radiali per la parete esterna
        let extCount = Int(step) * 2
        for k in Int(extBase)..<Int(extBase) + extCount {
            let p = positions[k]
            normals[k] = normalize(SIMD3<Float>(p.x, 0, p.z))
        }

        // ── Parete interna (normale verso dentro) ──────────────────
        let intBase = UInt32(positions.count)
        addRing(radius: innerR, y: -halfH,
                normalDir: SIMD3<Float>(0, 0, 0), uOffset: 0.5)
        addRing(radius: innerR, y:  halfH,
                normalDir: SIMD3<Float>(0, 0, 0), uOffset: 0.5)
        for i in 0..<UInt32(segments) {
            let b = intBase + i
            let t = intBase + step + i
            // triangoli invertiti → normale verso centro
            indices += [b, b+1, t, b+1, t+1, t]
        }
        let intCount = Int(step) * 2
        for k in Int(intBase)..<Int(intBase) + intCount {
            let p = positions[k]
            normals[k] = -normalize(SIMD3<Float>(p.x, 0, p.z))
        }

        // ── Corona superiore ──────────────────────────────────────
        let topBase = UInt32(positions.count)
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            let xo = cos(angle) * outerR
            let zo = sin(angle) * outerR
            let xi = cos(angle) * innerR
            let zi = sin(angle) * innerR
            positions.append(SIMD3<Float>(xo, halfH, zo))
            normals.append(SIMD3<Float>(0, 1, 0))
            uvs.append(SIMD2<Float>(Float(i) / Float(segments), 1.0))
            positions.append(SIMD3<Float>(xi, halfH, zi))
            normals.append(SIMD3<Float>(0, 1, 0))
            uvs.append(SIMD2<Float>(Float(i) / Float(segments), 0.0))
        }
        for i in 0..<UInt32(segments) {
            let o0 = topBase + i * 2
            let i0 = topBase + i * 2 + 1
            let o1 = topBase + (i + 1) * 2
            let i1 = topBase + (i + 1) * 2 + 1
            indices += [o0, i0, o1, i0, i1, o1]
        }

        // ── Corona inferiore ──────────────────────────────────────
        let botBase = UInt32(positions.count)
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            let xo = cos(angle) * outerR
            let zo = sin(angle) * outerR
            let xi = cos(angle) * innerR
            let zi = sin(angle) * innerR
            positions.append(SIMD3<Float>(xo, -halfH, zo))
            normals.append(SIMD3<Float>(0, -1, 0))
            uvs.append(SIMD2<Float>(Float(i) / Float(segments), 1.0))
            positions.append(SIMD3<Float>(xi, -halfH, zi))
            normals.append(SIMD3<Float>(0, -1, 0))
            uvs.append(SIMD2<Float>(Float(i) / Float(segments), 0.0))
        }
        for i in 0..<UInt32(segments) {
            let o0 = botBase + i * 2
            let i0 = botBase + i * 2 + 1
            let o1 = botBase + (i + 1) * 2
            let i1 = botBase + (i + 1) * 2 + 1
            // invertiti rispetto al top
            indices += [o0, o1, i0, i0, o1, i1]
        }

        var desc = MeshDescriptor(name: "hollowCylinder")
        desc.positions  = MeshBuffer(positions)
        desc.normals    = MeshBuffer(normals)
        desc.textureCoordinates = MeshBuffer(uvs)
        desc.primitives = .triangles(indices)
        return try! MeshResource.generate(from: [desc])
    }
}

