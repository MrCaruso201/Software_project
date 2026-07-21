import Foundation

let str = "2026-07-21T16:45:47.123456"
let df3 = DateFormatter()
df3.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
if let d = df3.date(from: str) {
    print("Parsed df3: \(d)")
} else {
    print("Failed df3")
}

let df4 = DateFormatter()
df4.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
if let d = df4.date(from: str) {
    print("Parsed df4: \(d)")
} else {
    print("Failed df4")
}

let isoFull = ISO8601DateFormatter()
isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
if let d = isoFull.date(from: str) {
    print("Parsed isoFull: \(d)")
} else {
    print("Failed isoFull")
}
