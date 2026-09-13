import MapKit
import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension PointPickerView {
    /// The refine stage — «Уточните точку» (board `2a`): the map, the pin, the
    /// editable address, and Continue. Door details and the person moved one push
    /// on, to Describe (Round 5, decision #40). Camera position is view state (R7);
    /// everything the screen decides arrives as values and closures.
    struct RefineContent: View {
        let pin: PickedPlace?
        @Binding var pinAddress: String
        let isResolving: Bool
        let isApproximate: Bool
        let errorText: String?
        /// Where an empty map starts — the Settings start city when set; the built-in
        /// anchor otherwise.
        let fallbackRegion: MKCoordinateRegion?
        let onTap: (_ latitude: Double, _ longitude: Double) -> Void
        let onVisibleRegionChange: (MKCoordinateRegion) -> Void
        let continueToDescribe: () -> Void

        @State private var camera: MapCameraPosition
        /// Whether the sender has driven this map themselves. Counting camera settles
        /// was inference and got it wrong: if a pan lands before the seeding callback,
        /// the first settle *is* the sender's, and a late start city would overwrite it
        /// (review, PR #19). A gesture on the map is direct evidence instead.
        @State private var senderDroveTheMap = false

        /// What the map shows before any interaction — reported on appear so the first
        /// search is region-biased too; `.onMapCameraChange(.onEnd)` only fires after a move.
        private let initialRegion: MKCoordinateRegion

        /// A tap places the pin exactly where the user is already looking — recentering
        /// (and worse, snap-zooming) would fight their framing. Search results arrive from
        /// off-screen and do deserve the camera. The gesture and the camera are both view
        /// state, so the view reconciles them.
        @State private var suppressNextRecenter = false

        init(
            pin: PickedPlace?,
            pinAddress: Binding<String>,
            isResolving: Bool,
            isApproximate: Bool = false,
            errorText: String?,
            fallbackRegion: MKCoordinateRegion? = nil,
            onTap: @escaping (_ latitude: Double, _ longitude: Double) -> Void,
            onVisibleRegionChange: @escaping (MKCoordinateRegion) -> Void,
            continueToDescribe: @escaping () -> Void = {}
        ) {
            self.pin = pin
            _pinAddress = pinAddress
            self.isResolving = isResolving
            self.isApproximate = isApproximate
            self.errorText = errorText
            self.fallbackRegion = fallbackRegion
            self.onTap = onTap
            self.onVisibleRegionChange = onVisibleRegionChange
            self.continueToDescribe = continueToDescribe
            // Always a concrete region, never `.automatic`: automatic follows content, so
            // editing would reframe on every tap-moved marker, defeating the suppression
            // below. A fresh picker starts over the service's home market; editing starts
            // on the place being edited.
            let region = pin.map { MKCoordinateRegion(center: $0.coordinate, span: .addressLevel) }
                ?? fallbackRegion
                ?? .moscow
            initialRegion = region
            _camera = State(initialValue: .region(region))
        }

        var body: some View {
            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        // Marker has no SFSafeSymbols overload; the raw value keeps the
                        // name compile-checked all the same.
                        Marker(pin.displayAddress, systemImage: SFSymbol.mappin.rawValue, coordinate: pin.coordinate)
                    }
                }
                .simultaneousGesture(
                    // Any pan or pinch on the map is the sender taking it over. Recorded
                    // before the camera moves, so a late fallback cannot beat it.
                    DragGesture(minimumDistance: 1).onChanged { _ in senderDroveTheMap = true }
                )
                .simultaneousGesture(
                    MagnifyGesture(minimumScaleDelta: 0.01).onChanged { _ in senderDroveTheMap = true }
                )
                .onTapGesture { screenPoint in
                    if let coordinate = proxy.convert(screenPoint, from: .local) {
                        // Suppress only when this tap will actually move the pin — a tap on
                        // the identical coordinate fires no change, and a lingering flag
                        // would wrongly swallow the next search arrival's recenter.
                        if pin?.latitude != coordinate.latitude || pin?.longitude != coordinate.longitude {
                            suppressNextRecenter = true
                        }
                        onTap(coordinate.latitude, coordinate.longitude)
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                onVisibleRegionChange(context.region)
            }
            .onAppear {
                onVisibleRegionChange(initialRegion)
            }
            .onChange(of: fallbackRegion?.centerOnly) { _, _ in
                // The start city is resolved by a search, so it can land after this map
                // is already open — and then the sender is looking at a default nobody
                // chose, with the completer biased to it too. An empty map they have not
                // driven yet follows the answer when it arrives; a placed pin or a moved
                // camera is theirs and is left alone (review, PR #19).
                guard let region = fallbackRegion, pin == nil, !senderDroveTheMap else { return }
                camera = .region(region)
                onVisibleRegionChange(region)
            }
            .onChange(of: pin?.coordinateOnly) { previous, current in
                // Recenter when the pin arrives from search — not on address-only edits
                // (hence comparing coordinates, not places), and not on taps (suppressed
                // above, since the tapped point is already on screen).
                guard let current, previous != current else { return }
                if suppressNextRecenter {
                    suppressNextRecenter = false
                } else {
                    camera = .region(
                        MKCoordinateRegion(center: current.coordinate, span: .addressLevel)
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                ConfirmBar(
                    hasPin: pin != nil,
                    address: $pinAddress,
                    isResolving: isResolving,
                    isApproximate: isApproximate,
                    errorText: errorText,
                    continueToDescribe: continueToDescribe
                )
            }
        }
    }
}

extension PointPickerView.RefineContent {
    /// The bottom bar: resolved address (editable), progress, or the invitation to
    /// tap — and Continue. Progress and errors render regardless of a pin — a search
    /// launched from a fresh picker has no pin yet, and silence there reads as a dead
    /// search box.
    struct ConfirmBar: View {
        let hasPin: Bool
        @Binding var address: String
        let isResolving: Bool
        let isApproximate: Bool
        let errorText: String?
        let continueToDescribe: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Layout.Spacing.unit) {
                if hasPin {
                    HStack {
                        TextField("Address", text: $address, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.fullStreetAddress)
                        if isResolving {
                            ProgressView()
                        }
                    }
                } else if isResolving {
                    HStack(spacing: Layout.Spacing.unit) {
                        ProgressView()
                        Text("Finding the place…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Tap the map or search to choose the point.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isApproximate {
                    Text("The position is approximate — within a kilometre or so. Move the pin so the courier arrives at the right door.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(action: continueToDescribe) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasPin || isResolving)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}

#Preview("Confirm bar: searching from an empty picker") {
    @Previewable @State var address = ""
    PointPickerView.RefineContent.ConfirmBar(
        hasPin: false,
        address: $address,
        isResolving: true,
        isApproximate: false,
        errorText: nil,
        continueToDescribe: {}
    )
}

#Preview("Confirm bar: search failed, still no pin") {
    @Previewable @State var address = ""
    PointPickerView.RefineContent.ConfirmBar(
        hasPin: false,
        address: $address,
        isResolving: false,
        isApproximate: false,
        errorText: "No address found.",
        continueToDescribe: {}
    )
}

#Preview("Confirm bar: approximate fix") {
    @Previewable @State var address = "Москва, ул Москворечье, 6"
    PointPickerView.RefineContent.ConfirmBar(
        hasPin: true,
        address: $address,
        isResolving: false,
        isApproximate: true,
        errorText: nil,
        continueToDescribe: {}
    )
}

private extension MKCoordinateRegion {
    /// The fallback start for an empty picker. Yandex Delivery's Express API serves Russia;
    /// Moscow is the densest market and a familiar anchor to pan away from.
    static let moscow = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
        span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
    )
}

private extension MKCoordinateSpan {
    /// Tight enough to read house numbers, loose enough to keep the block in view.
    static let addressLevel = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
}

private extension MKCoordinateRegion {
    /// `MKCoordinateRegion` is not `Equatable` and `onChange` needs it to be. The centre
    /// is the whole of what changes here — the start city's span is fixed where it is
    /// resolved — so it is the identity worth watching.
    var centerOnly: PickedPlace.Coordinate {
        PickedPlace.Coordinate(latitude: center.latitude, longitude: center.longitude)
    }
}

private extension PickedPlace {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The place without its address — the identity the camera follows.
    var coordinateOnly: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }

    struct Coordinate: Hashable {
        let latitude: Double
        let longitude: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}

#Preview("No pin yet") {
    @Previewable @State var address = ""
    PointPickerView.RefineContent(
        pin: nil,
        pinAddress: $address,
        isResolving: false,
        errorText: nil,
        onTap: { _, _ in },
        onVisibleRegionChange: { _ in }
    )
}

#Preview("Pin resolving") {
    @Previewable @State var address = ""
    PointPickerView.RefineContent(
        pin: PickedPlace(latitude: 55.7558, longitude: 37.6173, address: ""),
        pinAddress: $address,
        isResolving: true,
        errorText: nil,
        onTap: { _, _ in },
        onVisibleRegionChange: { _ in }
    )
}

#Preview("Pin resolved") {
    @Previewable @State var address = "Москва, Красная площадь, 1"
    PointPickerView.RefineContent(
        pin: PickedPlace(latitude: 55.7539, longitude: 37.6208, address: "Москва, Красная площадь, 1"),
        pinAddress: $address,
        isResolving: false,
        errorText: nil,
        onTap: { _, _ in },
        onVisibleRegionChange: { _ in }
    )
}
