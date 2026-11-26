import XCTest
@testable import AltoOBDDashboard

final class ELM327ParserTests: XCTestCase {

    func testDecodeRPMAndSpeed() {
        // 41 0C 0F A0 -> ((15 * 256) + 160) / 4 = 1000 RPM
        let rpmBytes = ELM327Parser.extractMode01DataBytes(from: "010C\r41 0C 0F A0\r\r>", pid: .engineRPM)
        XCTAssertEqual(rpmBytes, [0x0F, 0xA0])
        XCTAssertEqual(ELM327Parser.decodeMode01Value(pid: .engineRPM, bytes: rpmBytes ?? []), 1000.0)

        // CAN headered speed: 7E8 03 41 0D 3C -> 60 km/h
        let speedBytes = ELM327Parser.extractMode01DataBytes(from: "7E8 03 41 0D 3C\r>", pid: .vehicleSpeed)
        XCTAssertEqual(speedBytes, [0x3C])
        XCTAssertEqual(ELM327Parser.decodeMode01Value(pid: .vehicleSpeed, bytes: speedBytes ?? []), 60.0)
    }

    func testDecodeCoolantAndBatteryVoltage() {
        // 41 05 81 -> 129 - 40 = 89°C
        let coolantBytes = ELM327Parser.extractMode01DataBytes(from: "410581\r>", pid: .coolantTemperature)
        XCTAssertEqual(ELM327Parser.decodeMode01Value(pid: .coolantTemperature, bytes: coolantBytes ?? []), 89.0)

        // ELM327 ATRV response
        XCTAssertEqual(ELM327Parser.decodeBatteryVoltage(from: "ATRV\r14.2V\r\r>"), 14.2)
    }

    func testDecodeSupportedPIDsBitmask() {
        // 0xBE 0x3F 0xA8 0x13 -> typical petrol ECU bitmask
        let supported = ELM327Parser.decodeSupportedPIDs(from: "41 00 BE 3F A8 13\r>", basePID: .supportedPIDs01to20)
        XCTAssertTrue(supported.contains(OBDPID.monitorStatus.rawValue))         // 0x01
        XCTAssertTrue(supported.contains(OBDPID.coolantTemperature.rawValue))    // 0x05
        XCTAssertTrue(supported.contains(OBDPID.intakeManifoldPressure.rawValue))// 0x0B
        XCTAssertTrue(supported.contains(OBDPID.engineRPM.rawValue))             // 0x0C
        XCTAssertTrue(supported.contains(OBDPID.vehicleSpeed.rawValue))          // 0x0D
    }

    func testDecodeMode03DTCsISOAndCAN() {
        // ISO 9141 / KWP2000 format: 43 01 71 03 01 00 00 -> P0171, P0301
        let isoDTCs = ELM327Parser.decodeDTCs(from: "43 01 71 03 01 00 00\r>", status: .stored)
        XCTAssertEqual(isoDTCs.map(\.code), ["P0171", "P0301"])

        // ISO 15765 CAN format with count byte: 43 02 01 33 04 20 -> P0133, P0420
        let canDTCs = ELM327Parser.decodeDTCs(from: "43 02 01 33 04 20\r>", status: .stored)
        XCTAssertEqual(canDTCs.map(\.code), ["P0133", "P0420"])
    }

    func testAlto800SpeedDensityMileageCalculation() throws {
        let profile = VehicleProfile.alto800CruzUK
        // Cruising at 64 km/h (~40 mph), 2600 RPM, 48 kPa MAP, 20°C IAT, neutral fuel trims
        let est = ELM327Parser.estimateFuelConsumption(
            speedKmh: 64.0,
            rpm: 2600.0,
            mafGramsPerSec: nil,
            mapKpa: 48.0,
            iatCelsius: 20.0,
            stftPercent: 0.0,
            ltftPercent: 0.0,
            profile: profile
        )

        XCTAssertEqual(est.source, .speedDensityMAP)
        XCTAssertGreaterThan(est.fuelLitersPerHour, 1.5)
        XCTAssertLessThan(est.fuelLitersPerHour, 5.0)

        let kpl = try XCTUnwrap(est.instantKmPerLiter)
        let ukMPG = try XCTUnwrap(UnitSystem.ukImperial.convertEconomy(kmPerLiter: kpl))
        // Realistic Alto 800 cruise economy should fall in ~45–80 UK MPG range
        XCTAssertGreaterThan(ukMPG, 40.0)
        XCTAssertLessThan(ukMPG, 90.0)
    }
}
