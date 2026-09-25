import SwiftUI
import WidgetKit

/// The extension's surfaces (board `5b`): two widgets — one waiting, one
/// working — and the Live Activity. Everything they render reads the shared
/// store through the Kit; the app writes, syncs, and reconciles.
@main
struct YDeliveryWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WaitingWidget()
        WorkingWidget()
        DeliveryLiveActivity()
    }
}
