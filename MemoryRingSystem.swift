import RealityKit
import SwiftUI
import simd

/// Gestisce l'anello e le foto orbitanti nella scena RealityKit
@Observable
@MainActor
final class MemoryRingSystem {

    // ════════════════════════════════════════════════════════════════
    // MARK: - ⚙️ CONFIGURAZIONE — CAMBIA QUI TUTTE LE DIMENSIONI
    // ════════════════════════════════════════════════════════════════
    // Tutte le misure sono in METRI (1.0 = 1 metro nella stanza reale).
    // Questo è l'UNICO posto da modificare: i valori qui sotto
    // sovrascrivono i default di Anellobho.swift.
    enum Config {

        // ─── 🧊 CILINDRO DI VETRO ────────────────────────────────────
        /// Raggio interno del cilindro. Più grande ⟹ cilindro più largo.
        static let ringRadius:    Float = 1.2
        /// Spessore della parete di vetro. Più grande ⟹ vetro più spesso.
        static let ringThickness: Float = 0.01
        /// Altezza della fascia di vetro. Più grande ⟹ cilindro più alto.
        static let ringHeight:    Float = 3.0
        /// Segmenti angolari. Più alto ⟹ più liscio (96 è ottimo).
        static let ringSegments:  Int   = 96

        // ─── 📍 POSIZIONE NELLA STANZA ───────────────────────────────
        /// Distanza davanti a te. Negativo = davanti.
        /// Metti 0 per averlo TUTTO ATTORNO a te (attorno alla poltrona).
        static let ringDistance:  Float = 0.0
        /// Altezza del CENTRO del cilindro da terra.
        static let ringCenterY:   Float = 2.0

        // ─── 💍 ANELLI DECORATIVI (bordo alto e basso) ───────────────
        /// Quanto gli anelli luminosi sporgono oltre il vetro.
        static let rimOverhang:   Float = 0.04
        /// Spessore verticale di ogni anello.
        static let rimHeight:     Float = 0.05

        // ─── 🖼️ ORBITA DELLE FOTO ────────────────────────────────────
        /// Raggio dell'orbita delle foto (tienilo < ringRadius
        /// così le foto restano DENTRO il vetro).
        static let orbitRadius:   Float = 1.1
        /// Altezza delle foto rispetto al centro del cilindro
        /// (0 = esattamente a metà altezza del vetro).
        static let orbitHeight:   Float = 0.0

        // ─── 🪄 OLOGRAMMA 3D (la foto che diventa tridimensionale) ────
        /// Distanza dell'ologramma davanti a te (negativo = davanti).
        static let hologramDistance: Float = -1.0
        /// Altezza dell'ologramma da terra.
        static let hologramHeight:   Float = 1.4
        /// Scala dell'ologramma 3D generato (regola quanto è grande).
        static let hologramScale:    Float = 0.6

        // ─── 🌍 AMBIENTE (pavimento reale + mondo bianco) ────────────
        /// Se true, la BASE del cilindro è appoggiata sul pavimento.
        /// Su Vision Pro reale il pavimento viene rilevato da ARKit;
        /// nel Simulatore resta a y = 0.
        static let ringSitsOnFloor:  Bool  = true
        /// Raggio della sfera bianca attorno al cilindro. Deve CONTENERE il
        /// cilindro (≈ 2.0 o più). Più piccolo ⟹ bianco più vicino e copertura
        /// più sicura; più grande ⟹ ambiente più arioso.
        static let whiteRadius:      Float = 2.2
        /// TEST: metti true per tenere il bianco SEMPRE acceso (per verificare
        /// che la sfera bianca si veda, senza dover entrare nel cilindro).
        static let forceWhiteWorld:  Bool  = false
    }

    // Entità principali
    var ringRoot:     Entity?          // radice spostabile (trascina per riposizionare)
    var ringEntity:   ModelEntity?
    var orbitRows:    [Entity] = []    // un nodo rotante per RIGA (sensi alternati)
    var worldRoot:    Entity?          // nodo fisso all'origine per le carte "staccate"
    var photoCards:   [PhotoCardEntity] = []

    // Carta selezionata
    private(set) var selectedCard: PhotoCardEntity?

    // Orbita
    private var isOrbiting  = true
    private var orbitAngle: Float = 0
    private let orbitSpeed: Float = 0.02// rad/s (lento, cinematografico)

    // 🤚 Carta tenuta in mano (cartolina). Staccata dall'orbita.
    private(set) var heldCard: PhotoCardEntity?

    // 🔍 Pinch-to-scale
    private var pinchCard:      PhotoCardEntity?
    private var pinchBaseScale: Float = 1.0

    // 🌫️ Mondo bianco sterile (sfera opaca che avvolge il cilindro quando entri)
    private var whiteDome:    ModelEntity?
    private var whiteOpacity: Float = 0
    private var whiteTarget:  Float = 0
    private var isInside      = false   // con isteresi, per non "sfarfallare" sul bordo

    // 🛰️ Tracker dell'ambiente (posizione testa + pavimento reale)
    let environment = EnvironmentTracker()
    private var floorHeight: Float = 0

    /// Y del CENTRO del cilindro. Se appoggiato a terra, la base tocca il pavimento.
    private var ringBaseY: Float {
        Config.ringSitsOnFloor ? (floorHeight + Config.ringHeight / 2) : Config.ringCenterY
    }

    /// Posizione del centro del cilindro nella stanza (calcolata dalla Config).
    var ringCenter: SIMD3<Float> {
        SIMD3<Float>(0, ringBaseY, Config.ringDistance)
    }

    // MARK: - Setup

    func setup(content: RealityViewContent, memories: [MemoryItem]) async {
        let root = Entity()
        root.name  = "ringRoot"
        root.position = ringCenter
        content.add(root)
        ringRoot = root

        // 🌐 Nodo "mondo" all'origine (transform identità). Le carte staccate
        //    dall'orbita (prese in mano o messe a fuoco) vanno parentate QUI,
        //    NON con parent = nil: un'entità senza genitore esce dalla scena e
        //    sparisce / non è più toccabile (era questo a far "sparire" le foto).
        //    Stando all'origine, le coordinate locali coincidono con quelle mondo.
        let world = Entity()
        world.name = "worldRoot"
        content.add(world)
        worldRoot = world

        // ── Cilindro cavo di vetro (Anellobho) ────────────────────────
        let ring = buildRing()
        root.addChild(ring)
        ringEntity = ring

        // ── Anelli decorativi luminosi sopra e sotto ──────────────────
        for rim in buildAccentRings() {
            root.addChild(rim)
        }

        // ── Carte foto su PIÙ RIGHE (orbite sovrapposte, sensi alternati) ─
        // Le foto si dispongono su righe impilate (centrale + sopra/sotto) e
        // ogni riga ruota nel verso OPPOSTO a quella adiacente.
        buildPhotoCards(memories: memories, parent: root)

        // ── 🌫️ Sfera bianca sterile attorno al cilindro (nascosta finché ──────
        //     non entri). È FIGLIA del cilindro: lo avvolge tutto e lo segue se
        //     lo sposti. Opaca ⟹ da dentro NON vedi nulla oltre il vetro.
        let dome = buildWhiteDome()
        root.addChild(dome)
        dome.position = .zero          // centrata sul centro del cilindro
        whiteDome = dome

        // ── 🛰️ Tracker ambiente: pavimento reale + posizione testa ───────────
        // Quando ARKit rileva il pavimento (solo device), riallinea il cilindro.
        environment.onFloorUpdate = { [weak self] y in
            guard let self, Config.ringSitsOnFloor else { return }
            self.floorHeight = y
            self.ringRoot?.position.y = self.ringBaseY
        }
        Task { await environment.start() }
    }

    // MARK: - 🧊 Cilindro cavo di vetro (Anellobho.swift)

    private func buildRing() -> ModelEntity {
        // Usa il TUO mesh identico, con le dimensioni della Config qui sopra.
        let mesh = MeshResource.generateHollowCylinder(
            ringRadius: Config.ringRadius,
            thickness:  Config.ringThickness,
            height:     Config.ringHeight,
            segments:   Config.ringSegments
        )

        // Materiale vetro: trasparente, lucido, con un filo di emissione per
        // restare visibile anche senza illuminazione forte nel simulatore.
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: UIColor(red: 0.82, green: 0.90, blue: 1.0, alpha: 1.0))
        glass.roughness = .init(floatLiteral: 0.05)
        glass.metallic  = .init(floatLiteral: 0.0)
        glass.blending  = .transparent(opacity: .init(floatLiteral: 0.22))
        glass.clearcoat = .init(floatLiteral: 1.0)
        glass.clearcoatRoughness = .init(floatLiteral: 0.0)
        glass.emissiveColor = .init(color: UIColor(red: 0.70, green: 0.85, blue: 1.0, alpha: 1.0))
        glass.emissiveIntensity = 0.12

        let entity = ModelEntity(mesh: mesh, materials: [glass])
        entity.name = "glassRing"
        return entity
    }

    // MARK: - 💍 Anelli decorativi luminosi (bordo alto e basso)

    /// Due anelli sottili che incorniciano il bordo superiore e inferiore
    /// del cilindro. Usano un materiale Unlit (sempre visibile nel simulatore)
    /// così "brillano" come un neon attorno al vetro.
    private func buildAccentRings() -> [ModelEntity] {
        let halfH = Config.ringHeight / 2

        // Stesso mesh del cilindro ma bassissimo (una fascia sottile) e
        // un po' più largo del vetro, così sporge come un bordo.
        let mesh = MeshResource.generateHollowCylinder(
            ringRadius: Config.ringRadius,
            thickness:  Config.ringThickness + Config.rimOverhang * 2,
            height:     Config.rimHeight,
            segments:   Config.ringSegments
        )

        // Unlit = colore pieno, sempre luminoso, indipendente dalle luci.
        let glow = UnlitMaterial(color: UIColor(red: 0.62, green: 0.90, blue: 1.0, alpha: 1.0))

        let top = ModelEntity(mesh: mesh, materials: [glow])
        top.name = "accentRingTop"
        top.position.y = halfH

        // L'anello inferiore fa anche da MANIGLIA: afferralo e trascinalo
        // per spostare tutto il cilindro nella stanza.
        let bottom = ModelEntity(mesh: mesh, materials: [glow])
        bottom.name = "ringHandle"
        bottom.position.y = -halfH
        let grab = (Config.ringRadius + Config.ringThickness + Config.rimOverhang) * 2
        bottom.collision = CollisionComponent(shapes: [
            ShapeResource.generateBox(size: SIMD3<Float>(grab, Config.rimHeight + 0.06, grab))
        ])
        bottom.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        bottom.components.set(HoverEffectComponent())

        return [top, bottom]
    }

    // MARK: - Carte foto

    /// Costruisce le carte distribuendole su PIÙ RIGHE impilate verticalmente:
    /// una riga centrale e altre sopra/sotto man mano che le foto aumentano.
    /// Ogni riga è un nodo che ruota (i sensi si alternano in `startOrbiting`).
    /// Il numero di righe è limitato: con TANTE foto le righe si infittiscono,
    /// non escono dal cilindro.
    private func buildPhotoCards(memories: [MemoryItem], parent: Entity) {
        let count = memories.count
        guard count > 0 else { return }

        // Quante righe: ~10 foto per riga come obiettivo, massimo 7 righe.
        let targetPerRow = 10
        let maxRows = 7
        let rows = min(maxRows, max(1, Int(ceil(Double(count) / Double(targetPerRow)))))

        // Spaziatura verticale tra le righe, centrata su y = 0 e contenuta
        // nell'altezza del cilindro (con un margine).
        let usableHeight = Config.ringHeight * 0.8
        let dY: Float = rows > 1 ? min(0.42, usableHeight / Float(rows - 1)) : 0

        // Un nodo rotante per riga, tutti centrati sull'asse del cilindro.
        orbitRows.removeAll()
        for _ in 0..<rows {
            let row = Entity()
            row.name = "orbitRow"
            parent.addChild(row)
            orbitRows.append(row)
        }

        // Quante foto per riga (round-robin → righe bilanciate).
        var counts = [Int](repeating: 0, count: rows)
        for i in 0..<count { counts[i % rows] += 1 }

        // Posiziona ogni foto nella sua riga, ad angoli uguali. Un piccolo
        // sfasamento per riga evita che le foto si impilino esattamente sopra.
        var placed = [Int](repeating: 0, count: rows)
        for (i, memory) in memories.enumerated() {
            let r        = i % rows
            let idxInRow = placed[r]
            placed[r] += 1
            let inRow    = max(counts[r], 1)
            let angle    = Float(idxInRow) / Float(inRow) * 2 * .pi + Float(r) * 0.6

            // Altezza della riga: centrata su 0 (…, -dY, 0, +dY, …)
            let y = (Float(r) - Float(rows - 1) / 2) * dY + Config.orbitHeight

            let card = PhotoCardEntity(
                memory: memory,
                angle: angle,
                orbitRadius: Config.orbitRadius,
                orbitHeight: y,
                rowIndex: r
            )
            orbitRows[r].addChild(card.entity)
            photoCards.append(card)
        }
    }

    // MARK: - Animazione orbita (chiamata da .task in ImmersiveView)

    func startOrbiting() async {
        while isOrbiting {
            try? await Task.sleep(for: .milliseconds(16))   // ~60 fps
            orbitAngle += orbitSpeed / 60.0

            // Ogni RIGA ruota; i sensi si ALTERNANO (riga pari in un verso,
            // dispari nell'altro) → righe contro-rotanti.
            for (r, row) in orbitRows.enumerated() {
                let dir: Float = (r % 2 == 0) ? 1 : -1
                row.transform.rotation = simd_quatf(
                    angle: orbitAngle * dir,
                    axis:  SIMD3<Float>(0, 1, 0)
                )
            }

            // Bob verticale leggero (ogni carta oscilla su/giù indipendentemente).
            // Salta le carte staccate dall'orbita (selezionata o tenuta in mano):
            // sono "in orbita" solo se il loro genitore è una delle righe.
            let now = Float(Date().timeIntervalSince1970)
            for (i, card) in photoCards.enumerated() {
                guard let parent = card.entity.parent,
                      orbitRows.contains(where: { $0 === parent }) else { continue }
                let phase = Float(i) / Float(max(photoCards.count, 1)) * 2 * .pi
                let bob   = sin(now * 0.45 + phase) * 0.035
                card.entity.position.y = card.baseY + bob
            }

            // 🌫️ Mondo bianco: appare quando entri nel cilindro, sfuma quando esci
            updateWhiteWorld()

            // 🤚 La carta in mano resta sempre rivolta verso di te (cartolina)
            if let held = heldCard { faceHeld(held) }
        }
    }

    // MARK: - 🌫️ Mondo bianco sterile (quando entri nel cilindro)

    /// Crea la cupola bianca che ti avvolge dall'interno. Parte invisibile.
    private func buildWhiteDome() -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: Config.whiteRadius)
        let mat  = UnlitMaterial(color: .white)
        let dome = ModelEntity(mesh: mesh, materials: [mat])
        dome.name = "whiteDome"
        // Normali invertite: vedi la sfera dall'INTERNO (ti avvolge).
        dome.scale = SIMD3<Float>(-1, 1, 1)
        dome.components.set(OpacityComponent(opacity: 0))
        dome.isEnabled = false
        return dome
    }

    /// Mostra il bianco quando la TESTA entra nel cilindro e lo dissolve quando
    /// esci. La sfera è ancorata al cilindro (non alla testa) e — quando è piena —
    /// diventa OPACA VERA (senza OpacityComponent) così NON sfarfalla mai.
    private func updateWhiteWorld() {
        guard let dome = whiteDome, let root = ringRoot else { return }

        // 1) Dentro o fuori? Con ISTERESI: una soglia per entrare e una (più
        //    larga) per uscire, così sul bordo non lampeggia avanti/indietro.
        if Config.forceWhiteWorld {
            isInside = true
        } else if let head = environment.headPosition() {
            let dx = head.x - root.position.x
            let dz = head.z - root.position.z
            let h  = sqrt(dx * dx + dz * dz)
            if isInside {
                if h > Config.ringRadius + 0.15 { isInside = false }   // esci col margine
            } else {
                if h < Config.ringRadius - 0.05 { isInside = true }    // entri ben dentro
            }
        } else {
            return   // niente posizione testa ⟹ non decido, lascio com'è
        }
        whiteTarget = isInside ? 1.0 : 0.0

        // 2) Dissolvenza morbida, agganciata agli estremi.
        whiteOpacity += (whiteTarget - whiteOpacity) * 0.12
        if whiteTarget > 0.5, whiteOpacity > 0.97 { whiteOpacity = 1.0 }
        if whiteTarget < 0.5, whiteOpacity < 0.03 { whiteOpacity = 0.0 }

        // 3) Applica. A pieno bianco TOLGO l'OpacityComponent ⟹ la sfera entra
        //    nel passo di rendering OPACO (test di profondità per-pixel): niente
        //    flicker con il vetro trasparente. L'OpacityComponent serve solo
        //    durante la breve dissolvenza.
        if whiteOpacity <= 0.0 {
            dome.isEnabled = false
            dome.components.remove(OpacityComponent.self)
        } else if whiteOpacity >= 1.0 {
            dome.isEnabled = true
            dome.components.remove(OpacityComponent.self)
        } else {
            dome.isEnabled = true
            dome.components.set(OpacityComponent(opacity: whiteOpacity))
        }
    }

    // MARK: - 🤚 Prendi una carta e tienila in mano (cartolina)

    /// Afferra una carta col pinch-drag: la stacca dall'orbita e la "tiene in mano".
    /// Se stavi guardando un ologramma (o un'altra carta a fuoco), quello stato
    /// viene chiuso pulito così la foto presa in mano non "sparisce" dietro al 3D.
    func grabCard(_ card: PhotoCardEntity, toWorld pos: SIMD3<Float>) {
        if heldCard !== card {
            // Se un'altra carta era a fuoco, rimandala in orbita
            if let prev = selectedCard, prev !== card {
                prev.entity.isEnabled = true
                returnCardToOrbit(prev)
            }
            selectedCard = nil
            // Stacca dall'orbita preservando la posizione nel mondo (NON nil:
            // con nil l'entità esce dalla scena e sparisce)
            card.entity.setParent(worldRoot, preservingWorldTransform: true)
            card.entity.isEnabled = true
            card.entity.scale = SIMD3<Float>(repeating: 1.5)
            heldCard = card
        }
        card.entity.position = pos
        faceHeld(card)
    }

    /// Rilascia la carta: resta sospesa dove l'hai lasciata.
    func releaseCard() {
        heldCard = nil
    }

    // MARK: - 🔍 Pinch-to-scale

    /// Aggiorna la scala mentre il pinch è attivo.
    func scaleCard(_ card: PhotoCardEntity, magnification: Float) {
        if pinchCard !== card {
            pinchBaseScale = card.entity.scale.x
            pinchCard = card
        }
        let s = max(0.3, min(4.0, pinchBaseScale * magnification))
        card.entity.scale = SIMD3<Float>(repeating: s)
    }

    /// Finalizza la scala al rilascio del pinch.
    func commitScale(for card: PhotoCardEntity, magnification: Float) {
        let s = max(0.3, min(4.0, pinchBaseScale * magnification))
        card.entity.scale = SIMD3<Float>(repeating: s)
        pinchCard = nil
    }

    /// Orienta la carta tenuta in mano così che la FOTO sia rivolta verso di te.
    private func faceHeld(_ card: PhotoCardEntity) {
        guard let head = environment.headPosition() else { return }
        let pos = card.entity.position(relativeTo: nil)
        // Guardando il punto "oltre" la carta (lontano dalla testa),
        // il fronte (+Z) della carta resta rivolto verso di te.
        let away = pos + (pos - head)
        card.entity.look(at: away, from: pos, relativeTo: nil)
    }

    // MARK: - 🤚 Sposta il cilindro (trascina la base luminosa)

    /// True se l'entità è la maniglia (anello inferiore) per spostare il cilindro.
    func isHandle(_ entity: Entity) -> Bool {
        entity.name == "ringHandle"
    }

    /// Sposta tutto il cilindro su una nuova posizione X/Z (resta a terra).
    func moveRing(toWorldX x: Float, z: Float) {
        ringRoot?.position = SIMD3<Float>(x, ringBaseY, z)
    }

    // MARK: - Selezione carta (tap = portala vicino, poi diventa ologramma 3D)

    /// Tap su una foto: la stacca dall'orbita e la porta DAVANTI a te, ingrandita
    /// (feedback immediato, la foto resta SEMPRE visibile). In sottofondo genera
    /// l'ologramma 3D nativo: quando è pronto, sostituisce la carta nello stesso
    /// punto. Tap di nuovo sulla stessa → chiude e torna in orbita.
    func selectCard(_ card: PhotoCardEntity) {
        // Tap sulla stessa carta già a fuoco → chiudi
        if selectedCard === card {
            deselectAll()
            return
        }

        // Se un'altra era a fuoco, rimandala in orbita
        if let prev = selectedCard {
            returnCardToOrbit(prev)
        }
        // Questa non è più "in mano"
        if heldCard === card { heldCard = nil }

        selectedCard = card
        // Stacca dall'orbita verso worldRoot (NON nil: con nil uscirebbe dalla
        // scena e sparirebbe) e portala davanti a te.
        card.entity.setParent(worldRoot, preservingWorldTransform: true)
        card.entity.isEnabled = true
        placeInFrontOfUser(card, scale: 1.8)
    }

    /// Chiude lo stato corrente: rimette la carta a fuoco nell'orbita.
    /// NON tocca `heldCard` (la carta in mano è uno stato a parte,
    /// gestito da grab/release) per non farla cadere se chiudi dal pannello.
    func deselectAll() {
        if let card = selectedCard {
            card.entity.isEnabled = true
            returnCardToOrbit(card)
        }
        selectedCard = nil
    }

    /// Porta una carta davanti all'utente: ingrandita, in piedi, con la FOTO
    /// rivolta verso di lui. Indipendente da dove sia il cilindro.
    private func placeInFrontOfUser(_ card: PhotoCardEntity, scale: Float) {
        placeInFront(card.entity, distance: 0.6)
        // Ingrandisci DOPO il look (che potrebbe normalizzare la scala).
        card.entity.scale = SIMD3<Float>(repeating: scale)
    }

    /// Mette una qualsiasi entità DAVANTI all'utente, rivolta verso di lui, a
    /// `distance` metri dagli occhi. Ritorna la posizione usata (per il bob).
    /// È il cuore del "compare dritto davanti a te": usa la direzione dello
    /// SGUARDO, così vale per la carta piatta e per l'ologramma 3D.
    @discardableResult
    private func placeInFront(_ entity: Entity, distance: Float) -> SIMD3<Float> {
        let head = environment.headPosition() ?? SIMD3<Float>(0, 1.4, 0.8)

        // Direzione in cui l'utente sta GUARDANDO (orizzontale): così appare
        // SEMPRE davanti agli occhi, ovunque tu sia girato. Fallback: verso il
        // centro del cilindro; poi semplicemente davanti (-Z).
        var dir = environment.headForward() ?? .zero
        dir.y = 0
        if length(dir) < 0.0001 {
            let center = ringRoot?.position ?? .zero
            dir = SIMD3<Float>(center.x - head.x, 0, center.z - head.z)
        }
        if length(dir) < 0.0001 { dir = SIMD3<Float>(0, 0, -1) }
        dir = normalize(dir)

        // Poco davanti agli occhi, leggermente più in basso
        var pos = head + dir * distance
        pos.y = head.y - 0.05

        // Orienta così che il fronte (+Z) guardi verso di te.
        let away = pos + (pos - head)
        entity.look(at: away, from: pos, relativeTo: nil)
        return pos
    }

    /// Rimette una carta nell'orbita: la ri-attacca all'orbitRoot, scala 1, e la
    /// riposiziona nel suo slot rivolta verso il centro.
    private func returnCardToOrbit(_ card: PhotoCardEntity) {
        card.entity.isEnabled = true
        // Riattacca alla SUA riga (fallback: la prima riga disponibile).
        let row = orbitRows.indices.contains(card.rowIndex) ? orbitRows[card.rowIndex] : orbitRows.first
        row?.addChild(card.entity, preservingWorldTransform: false)
        card.entity.scale = SIMD3<Float>(repeating: 1.0)
        let r = card.orbitRadius
        card.entity.position = SIMD3<Float>(
            cos(card.angle) * r,
            card.baseY,
            sin(card.angle) * r
        )
        card.entity.look(at: SIMD3<Float>(0, card.baseY, 0),
                         from: card.entity.position,
                         relativeTo: card.entity.parent)
    }

    // MARK: - Trova carta da entità (cerca nella gerarchia)

    func card(for entity: Entity) -> PhotoCardEntity? {
        // Cerca sia sull'entity diretta sia sui discendenti
        return photoCards.first { card in
            entity == card.entity ||
            isDescendant(entity, of: card.entity)
        }
    }

    private func isDescendant(_ candidate: Entity, of ancestor: Entity) -> Bool {
        var current: Entity? = candidate.parent
        while let c = current {
            if c == ancestor { return true }
            current = c.parent
        }
        return false
    }
}
