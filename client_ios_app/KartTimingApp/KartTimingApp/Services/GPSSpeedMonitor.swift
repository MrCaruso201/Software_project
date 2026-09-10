import CoreLocation
import Combine

/// Misura locale, attiva soltanto mentre la vista pilota è visibile.
final class GPSSpeedMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var speedKmh: Double?
    @Published private(set) var status = "In attesa GPS"
    private let manager = CLLocationManager()
    private var active = false
    private var lastSample: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        active = true
        updateAuthorization()
    }

    func stop() {
        active = false
        manager.stopUpdatingLocation()
        speedKmh = nil
        lastSample = nil
    }

    func expireSample() {
        if let lastSample, Date().timeIntervalSince(lastSample) > 5 {
            speedKmh = nil
            status = "In attesa GPS"
        }
    }

    private func updateAuthorization() {
        guard active else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Consenti posizione"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            status = "In attesa GPS"
            manager.startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            speedKmh = nil
            status = "GPS non autorizzato"
        @unknown default:
            speedKmh = nil
            status = "GPS non disponibile"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active, let location = locations.last else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) <= 5,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              location.speed >= 0, location.speedAccuracy >= 0 else {
            speedKmh = nil
            status = "In attesa GPS"
            return
        }
        lastSample = location.timestamp
        speedKmh = location.speed * 3.6
        status = "GPS"
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard active else { return }
        speedKmh = nil
        status = "GPS non disponibile"
    }
}
