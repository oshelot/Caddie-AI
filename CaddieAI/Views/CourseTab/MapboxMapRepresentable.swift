//
//  MapboxMapRepresentable.swift
//  CaddieAI
//
//  UIViewRepresentable wrapping Mapbox MapView with satellite base map
//  and 7 GeoJSON overlay layers for golf course rendering.
//

import SwiftUI
import MapboxMaps
import CoreLocation

struct MapboxMapRepresentable: UIViewRepresentable {
    let course: NormalizedCourse?
    var selectedHole: Int?
    var onHoleTapped: ((Int) -> Void)?

    // MARK: - Layer & Source IDs

    private enum LayerID {
        static let source = "course-source"
        static let boundary = "layer-boundary"
        static let water = "layer-water"
        static let bunkers = "layer-bunkers"
        static let holeLines = "layer-hole-lines"
        static let greens = "layer-greens"
        static let tees = "layer-tees"
        static let holeLabels = "layer-hole-labels"
    }

    // MARK: - Make

    func makeUIView(context: Context) -> MapView {
        let center = course.map {
            CLLocationCoordinate2D(latitude: $0.centroid.latitude, longitude: $0.centroid.longitude)
        } ?? CLLocationCoordinate2D(latitude: 36.5625, longitude: -121.9486)

        let cameraOptions = CameraOptions(
            center: center,
            zoom: 15.5,
            bearing: 0,
            pitch: 0
        )

        let mapInitOptions = MapInitOptions(
            cameraOptions: cameraOptions,
            styleURI: .satelliteStreets
        )

        let mapView = MapView(frame: .zero, mapInitOptions: mapInitOptions)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.ornaments.compassView.isHidden = true
        TelemetryService.shared.recordMapboxCall()

        context.coordinator.mapView = mapView
        mapView.mapboxMap.onStyleLoaded.observe { _ in
            if let course = self.course {
                context.coordinator.addCourseLayers(course: course)
            }
        }.store(in: &context.coordinator.cancelBag)

        return mapView
    }

    // MARK: - Update

    func updateUIView(_ mapView: MapView, context: Context) {
        guard let course = course else { return }

        context.coordinator.course = course

        if context.coordinator.currentCourseId != course.id {
            context.coordinator.currentCourseId = course.id
            context.coordinator.currentlyZoomedHole = nil

            let center = CLLocationCoordinate2D(
                latitude: course.centroid.latitude,
                longitude: course.centroid.longitude
            )
            mapView.camera.fly(to: CameraOptions(center: center, zoom: 15.5), duration: 1.0)
            context.coordinator.addCourseLayers(course: course)
        }

        context.coordinator.highlightHole(selectedHole)
        context.coordinator.zoomToHole(selectedHole)
    }

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(onHoleTapped: onHoleTapped)
    }

    class Coordinator {
        weak var mapView: MapView?
        var currentCourseId: String?
        var cancelBag: [AnyCancelable] = []
        var layersAdded = false
        var onHoleTapped: ((Int) -> Void)?
        var course: NormalizedCourse?
        var currentlyZoomedHole: Int?

        init(onHoleTapped: ((Int) -> Void)?) {
            self.onHoleTapped = onHoleTapped
        }

        func addCourseLayers(course: NormalizedCourse) {
            guard let mapView = mapView,
                  let map = mapView.mapboxMap else { return }

            removeLayers(map: map)

            let featureCollection = CourseGeoJSONBuilder.buildFeatureCollection(from: course)

            var source = GeoJSONSource(id: LayerID.source)
            source.data = .featureCollection(featureCollection)
            try? map.addSource(source)

            // 1. Course boundary — green tinted fill
            var boundaryLayer = FillLayer(id: LayerID.boundary, source: LayerID.source)
            boundaryLayer.filter = Exp(.eq) { Exp(.get) { "type" }; "boundary" }
            boundaryLayer.fillColor = .constant(StyleColor(rawValue: "#2E7D32"))
            boundaryLayer.fillOpacity = .constant(0.08)
            try? map.addLayer(boundaryLayer)

            // 2. Water — blue fill
            var waterLayer = FillLayer(id: LayerID.water, source: LayerID.source)
            waterLayer.filter = Exp(.eq) { Exp(.get) { "type" }; "water" }
            waterLayer.fillColor = .constant(StyleColor(rawValue: "#1565C0"))
            waterLayer.fillOpacity = .constant(0.5)
            try? map.addLayer(waterLayer)

            // 3. Bunkers — tan fill
            var bunkerLayer = FillLayer(id: LayerID.bunkers, source: LayerID.source)
            bunkerLayer.filter = Exp(.eq) { Exp(.get) { "type" }; "bunker" }
            bunkerLayer.fillColor = .constant(StyleColor(rawValue: "#E8D5B7"))
            bunkerLayer.fillOpacity = .constant(0.7)
            try? map.addLayer(bunkerLayer)

            // 4. Hole lines — white dashed
            var holeLineLayer = LineLayer(id: LayerID.holeLines, source: LayerID.source)
            holeLineLayer.filter = Exp(.eq) { Exp(.get) { "type" }; "holeLine" }
            holeLineLayer.lineColor = .constant(StyleColor(rawValue: "#FFFFFF"))
            holeLineLayer.lineOpacity = .constant(0.8)
            holeLineLayer.lineWidth = .constant(2.0)
            holeLineLayer.lineDasharray = .constant([4.0, 3.0])
            try? map.addLayer(holeLineLayer)

            // 5. Greens — green fill
            var greenLayer = FillLayer(id: LayerID.greens, source: LayerID.source)
            greenLayer.filter = Exp(.eq) { Exp(.get) { "type" }; "green" }
            greenLayer.fillColor = .constant(StyleColor(rawValue: "#4CAF50"))
            greenLayer.fillOpacity = .constant(0.6)
            try? map.addLayer(greenLayer)

            // 6. Tees — light green fill
            var teeLayer = FillLayer(id: LayerID.tees, source: LayerID.source)
            teeLayer.filter = Exp(.eq) { Exp(.get) { "type" }; "tee" }
            teeLayer.fillColor = .constant(StyleColor(rawValue: "#81C784"))
            teeLayer.fillOpacity = .constant(0.5)
            try? map.addLayer(teeLayer)

            // 7. Hole labels — white text with halo
            var labelLayer = SymbolLayer(id: LayerID.holeLabels, source: LayerID.source)
            labelLayer.filter = Exp(.eq) { Exp(.get) { "type" }; "holeLabel" }
            labelLayer.textField = .expression(Exp(.get) { "label" })
            labelLayer.textSize = .constant(14.0)
            labelLayer.textColor = .constant(StyleColor(rawValue: "#FFFFFF"))
            labelLayer.textHaloColor = .constant(StyleColor(rawValue: "#000000"))
            labelLayer.textHaloWidth = .constant(1.5)
            labelLayer.textAllowOverlap = .constant(true)
            labelLayer.textFont = .constant(["DIN Pro Bold", "Arial Unicode MS Bold"])
            try? map.addLayer(labelLayer)

            layersAdded = true
        }

        func highlightHole(_ holeNumber: Int?) {
            guard let mapView = mapView,
                  let map = mapView.mapboxMap,
                  layersAdded else { return }

            if let hole = holeNumber {
                try? map.updateLayer(withId: LayerID.holeLines, type: LineLayer.self) { layer in
                    layer.lineOpacity = .expression(
                        Exp(.switchCase) {
                            Exp(.eq) { Exp(.get) { "holeNumber" }; Double(hole) }
                            1.0
                            0.4
                        }
                    )
                    layer.lineWidth = .expression(
                        Exp(.switchCase) {
                            Exp(.eq) { Exp(.get) { "holeNumber" }; Double(hole) }
                            3.5
                            1.5
                        }
                    )
                }
            } else {
                try? map.updateLayer(withId: LayerID.holeLines, type: LineLayer.self) { layer in
                    layer.lineOpacity = .constant(0.8)
                    layer.lineWidth = .constant(2.0)
                }
            }
        }

        // MARK: - Camera Zoom

        func zoomToHole(_ holeNumber: Int?) {
            guard let mapView = mapView,
                  let map = mapView.mapboxMap else { return }

            // Only fly if the selection actually changed
            guard holeNumber != currentlyZoomedHole else { return }
            currentlyZoomedHole = holeNumber

            if let holeNumber,
               let hole = course?.holes.first(where: { $0.number == holeNumber }) {
                let coords = collectCoordinates(for: hole)
                guard coords.count >= 2 else { return }

                let padding = UIEdgeInsets(top: 80, left: 40, bottom: 200, right: 40)
                guard let camera = try? map.camera(
                    for: coords,
                    camera: CameraOptions(),
                    coordinatesPadding: padding,
                    maxZoom: nil,
                    offset: nil
                ) else { return }
                mapView.camera.fly(to: camera, duration: 0.8)
            } else if let course {
                // Fly back to course overview
                let center = CLLocationCoordinate2D(
                    latitude: course.centroid.latitude,
                    longitude: course.centroid.longitude
                )
                mapView.camera.fly(to: CameraOptions(center: center, zoom: 15.5), duration: 0.8)
            }
        }

        /// Collects all coordinates from a hole's geometry features
        private func collectCoordinates(for hole: NormalizedHole) -> [CLLocationCoordinate2D] {
            var coords: [CLLocationCoordinate2D] = []

            // Line of play
            if let line = hole.lineOfPlay {
                for point in line.points {
                    coords.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                }
            }

            // Green
            if let green = hole.green {
                for point in green.outerRing {
                    coords.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                }
            }

            // Tee areas
            for tee in hole.teeAreas {
                for point in tee.outerRing {
                    coords.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                }
            }

            // Bunkers
            for bunker in hole.bunkers {
                for point in bunker.outerRing {
                    coords.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                }
            }

            // Water
            for water in hole.water {
                for point in water.outerRing {
                    coords.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                }
            }

            // Pin
            if let pin = hole.pin {
                coords.append(CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude))
            }

            return coords
        }

        private func removeLayers(map: MapboxMap) {
            let layerIds = [
                LayerID.holeLabels, LayerID.tees, LayerID.greens,
                LayerID.holeLines, LayerID.bunkers, LayerID.water, LayerID.boundary
            ]
            for id in layerIds {
                try? map.removeLayer(withId: id)
            }
            try? map.removeSource(withId: LayerID.source)
            layersAdded = false
        }
    }
}
