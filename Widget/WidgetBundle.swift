import SwiftUI
import WidgetKit

@main
struct GymNoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        GymWidget()
        DailyWidget()
        RestLiveActivity()
    }
}
