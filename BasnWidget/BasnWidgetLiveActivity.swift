//
//  BasnWidgetLiveActivity.swift
//  BasnWidget
//
//  Created by Jonas Goslow on 5/30/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct BasnWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct BasnWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BasnWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension BasnWidgetAttributes {
    fileprivate static var preview: BasnWidgetAttributes {
        BasnWidgetAttributes(name: "World")
    }
}

extension BasnWidgetAttributes.ContentState {
    fileprivate static var smiley: BasnWidgetAttributes.ContentState {
        BasnWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: BasnWidgetAttributes.ContentState {
         BasnWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: BasnWidgetAttributes.preview) {
   BasnWidgetLiveActivity()
} contentStates: {
    BasnWidgetAttributes.ContentState.smiley
    BasnWidgetAttributes.ContentState.starEyes
}
