import CoreGraphics
import Foundation
import StarterCore
import Testing

@Suite struct NotchGeometryTests {
    // A 1512 × 982 point screen with a 38 pt menu bar and a 200 pt housing in the middle.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let left = CGRect(x: 0, y: 944, width: 656, height: 38)
    let right = CGRect(x: 856, y: 944, width: 656, height: 38)

    @Test func theHousingLiesBetweenTheTwoAreas() {
        let geometry = NotchGeometry(screen: screen, topLeftArea: left, topRightArea: right, menuBarHeight: 38)
        #expect(geometry.hasNotch)
        #expect(geometry.closed == CGRect(x: 656, y: 944, width: 200, height: 38))
    }

    @Test func openHangsFromTheTopCenteredOnTheHousing() {
        let geometry = NotchGeometry(screen: screen, topLeftArea: left, topRightArea: right, menuBarHeight: 38)
        #expect(geometry.open(CGSize(width: 480, height: 160)) == CGRect(x: 516, y: 822, width: 480, height: 160))
        // Never narrower than the housing.
        #expect(geometry.open(CGSize(width: 100, height: 80)).width == 200)
    }

    @Test func noHousingFallsBackToAPillUnderTheMenuBar() {
        let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry(screen: external, topLeftArea: nil, topRightArea: nil, menuBarHeight: 24)
        #expect(!geometry.hasNotch)
        #expect(geometry.closed.midX == external.midX)
        #expect(geometry.closed.maxY == external.maxY - 24)
        #expect(geometry.open(CGSize(width: 480, height: 160)).maxY == external.maxY - 24)
    }

    @Test func openStaysOnScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 400, height: 800)
        let geometry = NotchGeometry(screen: narrow, topLeftArea: nil, topRightArea: nil, menuBarHeight: 24)
        let frame = geometry.open(CGSize(width: 480, height: 160))
        #expect(frame.minX >= narrow.minX && frame.maxX <= narrow.maxX)
    }
}

@Suite struct ShelfTests {
    let a = URL(fileURLWithPath: "/tmp/a.txt")
    let b = URL(fileURLWithPath: "/tmp/b.txt")

    @Test func newestFirstWithoutDuplicates() {
        var shelf = Shelf()
        shelf.add([a])
        shelf.add([b])
        #expect(shelf.files == [b, a])
        shelf.add([a])
        #expect(shelf.files == [a, b])
    }

    @Test func aDropOfSeveralKeepsTheirOrder() {
        var shelf = Shelf()
        shelf.add([a, b])
        #expect(shelf.files == [a, b])
    }

    @Test func keepsAtMostCapacity() {
        var shelf = Shelf()
        shelf.add((0..<30).map { URL(fileURLWithPath: "/tmp/\($0)") })
        #expect(shelf.files.count == Shelf.capacity)
        #expect(shelf.files.first?.lastPathComponent == "0")
    }

    @Test func prunesMissingFilesAndRoundTrips() {
        var shelf = Shelf(files: [a, b])
        shelf.prune { $0 == b }
        #expect(shelf.files == [b])
        #expect(Shelf(stored: shelf.stored) == shelf)
        shelf.remove(b)
        #expect(shelf.files.isEmpty)
    }
}
