import Foundation

/// EEI / CSRA "energy wheel" sources (Safety Assessment / HECA — docs/plans/safety-assessment.md).
enum EnergySource: String, Codable, CaseIterable {
    case gravity, motion, mechanical, electrical, pressure, temperature
    case chemical, radiation, biological, sound, other
}

/// Whether a present high-energy hazard is safeguarded by a control.
enum ControlStatus: String, Codable { case direct, indirect, none }

/// The 13 categorical high-energy hazards (EEI Appendix 3) — snake_case raw ids that double as the
/// exact category ids in the prompt + structured-output schema. Each maps to an energy-wheel source and
/// an SF Symbol for the finding row / HUD / overlay legend.
enum HighEnergyHazard: String, Codable, CaseIterable, Identifiable {
    case suspendedLoad = "suspended_load"
    case fallFromElevation = "fall_from_elevation"
    case mobileEquipment = "mobile_equipment"
    case motorVehicleSpeed = "motor_vehicle_speed"
    case mechanicalRotating = "mechanical_rotating"
    case highTemperature = "high_temperature"
    case steam
    case fire
    case explosion
    case excavation
    case electricalContact = "electrical_contact"
    case arcFlash = "arc_flash"
    case toxicChemicalRadiation = "toxic_chemical_radiation"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .suspendedLoad: return "Suspended Load"
        case .fallFromElevation: return "Fall from Elevation"
        case .mobileEquipment: return "Mobile Equipment / Traffic"
        case .motorVehicleSpeed: return "Motor Vehicle Speed"
        case .mechanicalRotating: return "Heavy Rotating Equipment"
        case .highTemperature: return "High Temperature"
        case .steam: return "Steam"
        case .fire: return "Fire"
        case .explosion: return "Explosion"
        case .excavation: return "Trench / Excavation"
        case .electricalContact: return "Electrical Contact"
        case .arcFlash: return "Arc Flash"
        case .toxicChemicalRadiation: return "Toxic Chemical / Radiation"
        }
    }

    /// Why this category is a high-energy (SIF-capable) hazard — almost always above the
    /// ~1,500 J / 500 ft-lb serious-injury threshold.
    var energyThreshold: String {
        switch self {
        case .suspendedLoad: return "A raised/rigged load — a drop releases well over 1,500 J."
        case .fallFromElevation: return "A fall from > ~1.2 m / 4 ft exceeds the SIF energy threshold."
        case .mobileEquipment: return "Vehicles/equipment moving near workers on foot."
        case .motorVehicleSpeed: return "A vehicle at > ~50 km/h carries SIF-level kinetic energy."
        case .mechanicalRotating: return "Heavy rotating/reciprocating machinery able to catch or strike."
        case .highTemperature: return "Surfaces/materials > ~150 °C capable of serious burns."
        case .steam: return "Pressurised steam — thermal + pressure energy."
        case .fire: return "Active flame / ignition with fuel present."
        case .explosion: return "Stored pressure or explosive atmosphere with an ignition path."
        case .excavation: return "An unshored trench/excavation — soil collapse energy."
        case .electricalContact: return "Exposed/energised conductors > ~50 V."
        case .arcFlash: return "An arc-flash-capable electrical source (incident energy)."
        case .toxicChemicalRadiation: return "High-dose toxic chemical or ionising-radiation source."
        }
    }

    /// Energy-wheel grouping for the legend + summary.
    var energySource: EnergySource {
        switch self {
        case .suspendedLoad, .fallFromElevation, .excavation: return .gravity
        case .mobileEquipment, .motorVehicleSpeed: return .motion
        case .mechanicalRotating: return .mechanical
        case .highTemperature, .steam, .fire: return .temperature
        case .explosion: return .pressure
        case .electricalContact, .arcFlash: return .electrical
        case .toxicChemicalRadiation: return .chemical
        }
    }

    /// SF Symbol for the finding row / HUD card.
    var systemImage: String {
        switch self {
        case .suspendedLoad: return "shippingbox.fill"
        case .fallFromElevation: return "figure.fall"
        case .mobileEquipment: return "car.fill"
        case .motorVehicleSpeed: return "car.side.fill"
        case .mechanicalRotating: return "gearshape.2.fill"
        case .highTemperature: return "thermometer.sun.fill"
        case .steam: return "humidity.fill"
        case .fire: return "flame.fill"
        case .explosion: return "burst.fill"
        case .excavation: return "square.3.layers.3d.down.right"
        case .electricalContact: return "bolt.fill"
        case .arcFlash: return "bolt.trianglebadge.exclamationmark.fill"
        case .toxicChemicalRadiation: return "aqi.high"
        }
    }
}
