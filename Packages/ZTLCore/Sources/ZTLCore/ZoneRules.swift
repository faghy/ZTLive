import Foundation

/// Quali zone contano per il veicolo e le impostazioni scelte.
public struct ZoneRules: Equatable, Sendable {
    public var isMotorcycle: Bool
    public var includeAreaB: Bool
    public var includeLocalZones: Bool
    /// Solo per le prove: considera le zone sempre attive.
    public var ignoreSchedule: Bool

    public init(isMotorcycle: Bool = false, includeAreaB: Bool = false, includeLocalZones: Bool = true, ignoreSchedule: Bool = false) {
        self.isMotorcycle = isMotorcycle
        self.includeAreaB = includeAreaB
        self.includeLocalZones = includeLocalZones
        self.ignoreSchedule = ignoreSchedule
    }

    /// Area B e Area C: in moto l'Area C non si paga.
    public func applies(to zone: Zone, at date: Date) -> Bool {
        let areaActive = ignoreSchedule || ZoneSchedule.isAreaActive(at: date)
        switch zone {
        case .areaC: return !isMotorcycle && areaActive
        case .areaB: return includeAreaB && areaActive
        case .ztl, .pedestrian: return includeLocalZones
        }
    }

    public func applies(to zone: LocalZone, at date: Date) -> Bool {
        if zone.zone.hasGates {
            return applies(to: zone.zone, at: date)
        }
        guard includeLocalZones, !(isMotorcycle && zone.motoAllowed) else { return false }
        return ignoreSchedule || zone.isActive(at: date)
    }
}
