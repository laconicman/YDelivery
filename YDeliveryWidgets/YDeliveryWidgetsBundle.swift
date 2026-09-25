import SwiftUI
import WidgetKit

/// The extension's surfaces (board `5b`): two widgets — one waiting, one
/// working — and the Live Activity. Widgets render the app's snapshot file
/// (the schema's contract — never the live database); the activity renders
/// the `ContentState` the app pushes. The app writes, syncs, reconciles.
@main
struct YDeliveryWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WaitingWidget()
        WorkingWidget()
        DeliveryLiveActivity()
    }
}
