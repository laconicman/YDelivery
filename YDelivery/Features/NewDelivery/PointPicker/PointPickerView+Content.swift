import MapKit
import SwiftUI

extension PointPickerView {
    /// Pure presentation: the map, the pin, and the confirm bar. Camera position is view
    /// state (R7); everything the screen decides arrives as values and closures.
    struct Content: View {
        let pin: PickedPlace?
        @Binding var pinAddress: String
        let isResolving: Bool
        let errorText: String?
        let onTap: (_ latitude: Double, _ longitude: Double) -> Void
        let onVisibleRegionChange: (MKCoordinateRegion) -> Void

        @State private var camera: MapCameraPosition

        /// A tap places the pin exactly where the user is already looking — recentering
        /// (and worse, snap-zooming) would fight their framing. Search results arrive from
        /// off-screen and do deserve the camera. The gesture and the camera are both view
        /// state, so the view reconciles them.
        @State private var suppressNextRecenter = false

        init(
            pin: PickedPlace?,
            pinAddress: Binding<String>,
            isResolving: Bool,
            errorText: String?,
            onTap: @escaping (_ latitude: Double, _ longitude: Double) -> Void,
            onVisibleRegionChange: @escaping (MKCoordinateRegion) -> Void
        ) {
            self.pin = pin
            _pinAddress = pinAddress
            self.isResolving = isResolving
            self.errorText = errorText
            self.onTap = onTap
            self.onVisibleRegionChange = onVisibleRegionChange
            // Always a concrete region, never `.automatic`: automatic follows content, so
            // editing would reframe on every tap-moved marker, defeating the suppression
            // below. A fresh picker starts over the service's home market; editing starts
            // on the place being edited.
            _camera = State(initialValue: .region(
                pin.map { MKCoordinateRegion(center: $0.coordinate, span: .addressLevel) } ?? .moscow
            ))
        }

        var body: some View {
            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        Marker(
                            pin.address.isEmpty ? String(localized: "Selected point") : pin.address,
                            systemImage: "mappin",
                            coordinate: pin.coordinate
                        )
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
                    errorText: errorText
                )
            }
        }
    }
}

extension PointPickerView.Content {
    /// The bottom bar: resolved address (editable), progress, or the invitation to tap.
    struct ConfirmBar: View {
        let hasPin: Bool
        @Binding var address: String
        let isResolving: Bool
        let errorText: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if hasPin {
                    HStack {
                        TextField("Address", text: $address, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        if isResolving {
                            ProgressView()
                        }
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("Tap the map or search to choose the point.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
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
    PointPickerView.Content(
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
    PointPickerView.Content(
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
    PointPickerView.Content(
        pin: PickedPlace(latitude: 55.7539, longitude: 37.6208, address: "Москва, Красная площадь, 1"),
        pinAddress: $address,
        isResolving: false,
        errorText: nil,
        onTap: { _, _ in },
        onVisibleRegionChange: { _ in }
    )
}
