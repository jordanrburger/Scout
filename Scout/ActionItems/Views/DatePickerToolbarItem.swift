import SwiftUI

struct DatePickerToolbarItem: View {
    @Binding var date: Date
    let todayET: Date

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if let d = Calendar(identifier: .iso8601).date(byAdding: .day, value: -1, to: date) {
                    date = d
                }
            } label: { Image(systemName: "chevron.left") }

            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()

            Button {
                if let d = Calendar(identifier: .iso8601).date(byAdding: .day, value: 1, to: date) {
                    date = d
                }
            } label: { Image(systemName: "chevron.right") }

            if !Calendar.current.isDate(date, inSameDayAs: todayET) {
                Button("Today") { date = todayET }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
