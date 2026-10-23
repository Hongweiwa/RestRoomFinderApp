import Foundation

/// Fictional fixtures around New York City, not verified public facilities.
enum SampleRestrooms {
    static let all: [Restroom] = [
        Restroom(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Central Park North Gate", latitude: 40.7536, longitude: -73.9832,
            address: "89 E 42nd St", cleanlinessRating: 4.8,
            overallRating: 4.8, reviewCount: 128, distance: 160.934,
            openingHours: "Daily, 8:00 AM–8:00 PM", accessibility: true,
            babyChangingStation: true, genderNeutral: true, free: true,
            imageName: "leaf.fill", isOpenNow: true
        ),
        Restroom(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Main Street Plaza", latitude: 40.7532, longitude: -73.9822,
            address: "200 Example Street, New York, NY", cleanlinessRating: 4.5,
            overallRating: 4.2, reviewCount: 76, distance: 321.869,
            openingHours: "Mon–Sat, 10:00 AM–6:00 PM", accessibility: true,
            babyChangingStation: false, genderNeutral: true, free: true,
            imageName: "books.vertical.fill", isOpenNow: true
        ),
        Restroom(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Bryant Park Pavilion", latitude: 40.7580, longitude: -73.9900,
            address: "300 Demo Road, New York, NY", cleanlinessRating: 4.9,
            overallRating: 4.9, reviewCount: 42, distance: 643.738,
            openingHours: "Opens at 8 AM", accessibility: true,
            babyChangingStation: false, genderNeutral: false, free: false,
            imageName: "water.waves", isOpenNow: false
        ),
        Restroom(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                 name: "Public Library Branch", latitude: 40.754, longitude: -73.980,
                 address: "400 Demo Street, New York, NY", cleanlinessRating: 4.0,
                 overallRating: 4.0, reviewCount: 24, distance: 965.606,
                 openingHours: "Daily, 9 AM–6 PM", accessibility: true,
                 babyChangingStation: false, genderNeutral: true, free: true,
                 imageName: "books.vertical.fill", isOpenNow: true)
    ]
}
