import MapKit
import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension PointPickerView {
    /// The refine stage — «Уточните точку», the one Done (board `2a`). Pure
    /// presentation: the map, the pin, the editable address with its parts, and the
    /// confirm bar. Camera position is view state (R7); everything the screen decides
    /// arrives as values and closures.
    struct RefineContent: View {
        let pin: PickedPlace?
        @Binding var pinAddress: String
        @Binding var parts: AddressParts
        let isResolving: Bool
        let isApproximate: Bool
        let errorText: String?
        let canSavePlace: Bool
        let onTap: (_ latitude: Double, _ longitude: Double) -> Void
        let onVisibleRegionChange: (MKCoordinateRegion) -> Void
        let savePlace: () -> Void
        let done: () -> Void

        @State private var camera: MapCameraPosition

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
            parts: Binding<AddressParts>,
            isResolving: Bool,
            isApproximate: Bool = false,
            errorText: String?,
            canSavePlace: Bool = false,
            onTap: @escaping (_ latitude: Double, _ longitude: Double) -> Void,
            onVisibleRegionChange: @escaping (MKCoordinateRegion) -> Void,
            savePlace: @escaping () -> Void = {},
            done: @escaping () -> Void = {}
        ) {
            self.pin = pin
            _pinAddress = pinAddress
            _parts = parts
            self.isResolving = isResolving
            self.isApproximate = isApproximate
            self.errorText = errorText
            self.canSavePlace = canSavePlace
            self.onTap = onTap
            self.onVisibleRegionChange = onVisibleRegionChange
            self.savePlace = savePlace
            self.done = done
            // Always a concrete region, never `.automatic`: automatic follows content, so
            // editing would reframe on every tap-moved marker, defeating the suppression
            // below. A fresh picker starts over the service's home market; editing starts
            // on the place being edited.
            let region = pin.map { MKCoordinateRegion(center: $0.coordinate, span: .addressLevel) } ?? .moscow
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
                    parts: $parts,
                    isResolving: isResolving,
                    isApproximate: isApproximate,
                    errorText: errorText,
                    canSavePlace: canSavePlace,
                    savePlace: savePlace,
                    done: done
                )
            }
        }
    }
}

extension PointPickerView.RefineContent {
    /// The bottom bar: resolved address (editable), its parts, progress, or the
    /// invitation to tap — and the one Done (board `2a`, «Уточните точку»). Progress and
    /// errors render regardless of a pin — a search launched from a fresh picker has no
    /// pin yet, and silence there reads as a dead search box.
    struct ConfirmBar: View {
        let hasPin: Bool
        @Binding var address: String
        @Binding var parts: AddressParts
        let isResolving: Bool
        let isApproximate: Bool
        let errorText: String?
        let canSavePlace: Bool
        let savePlace: () -> Void
        let done: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if hasPin {
                    HStack {
                        TextField("Address", text: $address, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.fullStreetAddress)
                        if isResolving {
                            ProgressView()
                        }
                    }
                    PartsFields(parts: $parts)
                } else if isResolving {
                    HStack(spacing: 8) {
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

                HStack(spacing: 8) {
                    Button(action: done) {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!hasPin || isResolving)

                    if canSavePlace {
                        Button(action: savePlace) {
                            Image(systemSymbol: .bookmark)
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!hasPin || isResolving)
                        .accessibilityLabel(Text("Save as a place"))
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }

    /// The parts of the address the pin cannot know, as compact typed fields — entrance
    /// is text («со двора», «А»), floor and apartment take the number pad, the intercom
    /// code is its own field (DesignSystem → "Field taxonomy").
    struct PartsFields: View {
        @Binding var parts: AddressParts

        var body: some View {
            HStack(spacing: 6) {
                partField("entrance", text: $parts.entrance)
                partField("floor", text: $parts.floor)
                    .keyboardType(.numberPad)
                partField("apt.", text: $parts.apartment)
                    .keyboardType(.numberPad)
                partField("intercom", text: $parts.intercom)
            }
            .font(.footnote)
        }

        private func partField(_ prompt: LocalizedStringKey, text: Binding<String>) -> some View {
            TextField(prompt, text: text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
    }
}

#Preview("Confirm bar: searching from an empty picker") {
    @Previewable @State var address = ""
    @Previewable @State var parts = AddressParts()
    PointPickerView.RefineContent.ConfirmBar(
        hasPin: false,
        address: $address,
        parts: $parts,
        isResolving: true,
        isApproximate: false,
        errorText: nil,
        canSavePlace: false,
        savePlace: {},
        done: {}
    )
}

#Preview("Confirm bar: search failed, still no pin") {
    @Previewable @State var address = ""
    @Previewable @State var parts = AddressParts()
    PointPickerView.RefineContent.ConfirmBar(
        hasPin: false,
        address: $address,
        parts: $parts,
        isResolving: false,
        isApproximate: false,
        errorText: "No address found.",
        canSavePlace: false,
        savePlace: {},
        done: {}
    )
}

#Preview("Confirm bar: approximate fix, parts filled") {
    @Previewable @State var address = "Москва, ул Москворечье, 6"
    @Previewable @State var parts = AddressParts(entrance: "А", floor: "3", apartment: "301")
    PointPickerView.RefineContent.ConfirmBar(
        hasPin: true,
        address: $address,
        parts: $parts,
        isResolving: false,
        isApproximate: true,
        errorText: nil,
        canSavePlace: true,
        savePlace: {},
        done: {}
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
    @Previewable @State var parts = AddressParts()
    PointPickerView.RefineContent(
        pin: nil,
        pinAddress: $address,
        parts: $parts,
        isResolving: false,
        errorText: nil,
        onTap: { _, _ in },
        onVisibleRegionChange: { _ in }
    )
}

#Preview("Pin resolving") {
    @Previewable @State var address = ""
    @Previewable @State var parts = AddressParts()
    PointPickerView.RefineContent(
        pin: PickedPlace(latitude: 55.7558, longitude: 37.6173, address: ""),
        pinAddress: $address,
        parts: $parts,
        isResolving: true,
        errorText: nil,
        onTap: { _, _ in },
        onVisibleRegionChange: { _ in }
    )
}

#Preview("Pin resolved") {
    @Previewable @State var address = "Москва, Красная площадь, 1"
    @Previewable @State var parts = AddressParts()
    PointPickerView.RefineContent(
        pin: PickedPlace(latitude: 55.7539, longitude: 37.6208, address: "Москва, Красная площадь, 1"),
        pinAddress: $address,
        parts: $parts,
        isResolving: false,
        errorText: nil,
        canSavePlace: true,
        onTap: { _, _ in },
        onVisibleRegionChange: { _ in }
    )
}
