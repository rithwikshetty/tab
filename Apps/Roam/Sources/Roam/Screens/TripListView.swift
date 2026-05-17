import SwiftUI

struct TripListView: View {
    var onSelect: (DemoTrip) -> Void = { _ in }

    private var activeTrips: [DemoTrip] { SampleData.trips.filter { !$0.isCompleted } }
    private var completedTrips: [DemoTrip] { SampleData.trips.filter { $0.isCompleted } }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LargeTitle(title: "Trips")

                SectionHeaderText(title: "Active")
                Card {
                    ForEach(Array(activeTrips.enumerated()), id: \.element.id) { index, trip in
                        Button { onSelect(trip) } label: {
                            TripCardRow(trip: trip)
                        }
                        .buttonStyle(.plain)
                        if index < activeTrips.count - 1 { RowDivider() }
                    }
                }

                SectionHeaderText(title: "Completed")
                Card {
                    ForEach(Array(completedTrips.enumerated()), id: \.element.id) { index, trip in
                        Button { onSelect(trip) } label: {
                            TripCardRow(trip: trip)
                        }
                        .buttonStyle(.plain)
                        if index < completedTrips.count - 1 { RowDivider() }
                    }
                }

                Spacer(minLength: 120)
            }
            .scrollIndicators(.hidden)

            Fab(systemImage: "plus")
                .padding(.trailing, 18)
                .padding(.bottom, 100)
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    NavigationStack {
        TripListView()
    }
    .background(Sage.bg)
}
