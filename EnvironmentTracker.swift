import ARKit
import RealityKit
import QuartzCore
import simd

/// Traccia l'ambiente per due cose:
///  1. Sapere se la TESTA dell'utente è dentro il cilindro (→ mondo bianco).
///  2. Rilevare il PAVIMENTO reale per appoggiarci il cilindro.
///
/// • World tracking (posizione testa): funziona anche nel Simulatore.
/// • Plane detection (pavimento): SOLO su Apple Vision Pro reale.
///   Nel Simulatore viene saltato e il pavimento resta a y = 0.
@MainActor
final class EnvironmentTracker {

    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private var planeProvider: PlaneDetectionProvider?

    /// Altezza del pavimento rilevato (0 = pavimento dello spazio immersivo).
    private(set) var floorHeight: Float = 0
    /// Chiamata quando il pavimento reale viene rilevato/aggiornato.
    var onFloorUpdate: ((Float) -> Void)?

    /// Avvia la sessione ARKit. Ritorna subito; gli update girano in background.
    func start() async {
        var providers: [any DataProvider] = []

        if WorldTrackingProvider.isSupported {
            providers.append(worldTracking)
        }

        // Plane detection solo dove supportata (device reale) e autorizzata.
        if PlaneDetectionProvider.isSupported {
            let auth = await session.requestAuthorization(for: [.worldSensing])
            if auth[.worldSensing] == .allowed {
                let plane = PlaneDetectionProvider(alignments: [.horizontal])
                planeProvider = plane
                providers.append(plane)
            }
        }

        guard !providers.isEmpty else {
            print("ℹ️ Nessun provider ARKit supportato (Simulatore): pavimento a y=0.")
            return
        }

        do {
            try await session.run(providers)
        } catch {
            print("⚠️ ARKitSession non avviata: \(error.localizedDescription)")
            return
        }

        if let plane = planeProvider {
            Task { await self.consumePlaneUpdates(plane) }
        }
    }

    /// Posizione della testa nel mondo (nil se non disponibile).
    func headPosition() -> SIMD3<Float>? {
        guard worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
        else { return nil }
        let c = anchor.originFromAnchorTransform.columns.3
        return SIMD3<Float>(c.x, c.y, c.z)
    }

    /// Direzione in cui GUARDA la testa, nel mondo (nil se non disponibile).
    /// Il device guarda lungo il proprio asse −Z, quindi la "avanti" nel mondo
    /// è la terza colonna del transform negata.
    func headForward() -> SIMD3<Float>? {
        guard worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
        else { return nil }
        let m = anchor.originFromAnchorTransform
        let f = SIMD3<Float>(-m.columns.2.x, -m.columns.2.y, -m.columns.2.z)
        return simd_length(f) > 0.0001 ? simd_normalize(f) : nil
    }

    /// Ascolta i piani rilevati e tiene l'altezza del PAVIMENTO.
    private func consumePlaneUpdates(_ provider: PlaneDetectionProvider) async {
        for await update in provider.anchorUpdates {
            guard update.event != .removed else { continue }
            let anchor = update.anchor
            guard anchor.classification == .floor else { continue }
            let y = anchor.originFromAnchorTransform.columns.3.y
            if abs(y - floorHeight) > 0.001 {
                floorHeight = y
                onFloorUpdate?(y)
            }
        }
    }
}
