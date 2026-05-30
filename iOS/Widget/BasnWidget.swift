import SwiftUI
import WidgetKit

// MARK: - Timeline

struct BasnWidgetEntry: TimelineEntry {
    let date: Date
}

struct BasnWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BasnWidgetEntry {
        BasnWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (BasnWidgetEntry) -> Void) {
        completion(BasnWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BasnWidgetEntry>) -> Void) {
        completion(Timeline(entries: [BasnWidgetEntry(date: Date())], policy: .never))
    }
}

// MARK: - Views

struct BasnWidgetEntryView: View {
    var entry: BasnWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(Color(.systemBackground))

            switch family {
            case .systemSmall:
                smallLayout
            default:
                mediumLayout
            }
        }
        .widgetURL(URL(string: "basin://capture")!)
    }

    private var smallLayout: some View {
        VStack(spacing: 10) {
            Image(systemName: "drop.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.blue)
            Text("Capture")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text("Tap to record")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 20) {
            Image(systemName: "drop.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Basn")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Tap to start a capture")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.date, format: .dateTime.weekday(.wide).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Widget

struct BasnWidget: Widget {
    let kind = "BasnWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BasnWidgetProvider()) { entry in
            BasnWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Basn")
        .description("Tap to start a capture.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Bundle

@main
struct BasnWidgetBundle: WidgetBundle {
    var body: some Widget {
        BasnWidget()
    }
}
