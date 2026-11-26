# Alto OBD Dashboard (iOS / SwiftUI)

A native iOS SwiftUI OBD-II dashboard tailored for the **Suzuki Alto 800 Cruz (UK)** (and compatible with the UK 1.0L K10B Alto or any EOBD petrol vehicle).

## Key Features
- **Live Cockpit Gauges:** Vector Speedometer & Tachometer with Alto 800 redline (6,000 RPM) and shift-point hints (`SHIFT UP` / `SHIFT DOWN`).
- **Accurate Mileage Without a MAF Sensor:** Small 3-cylinder Suzuki ECUs (such as the 796cc F8D) typically expose **MAP (`010B`) + IAT (`010F`) + RPM (`010C`)** instead of a Mass Air Flow sensor. The app automatically uses MAF if present and seamlessly falls back to a **Speed-Density fuel calculation** (with STFT/LTFT fuel trim correction and a pump-calibration slider for Volumetric Efficiency).
- **UK & Metric Units:** Defaults to **mph + UK Imperial MPG + £/L**, with instant switching to **km/L**, **L/100km**, or **US MPG**.
- **Engine & Electrical Health:** Live Coolant Temperature (with overheat alert), Battery / Alternator Voltage (`0142` with `ATRV` fallback), Engine Load, Throttle Position, MAP kPa, Intake Air Temp, Short/Long Term Fuel Trims, and Ignition Timing.
- **Trip Computer & Mileage History:** Tracks distance, fuel used, estimated trip cost (£), idle %, live Swift Charts economy curve, and saves trip history locally.
- **Diagnostics & ELM327 Terminal:** Reads Stored (`Mode 03`) and Pending (`Mode 07`) fault codes with an offline Suzuki/EOBD code lookup table, supports clearing codes (`Mode 04`), shows auto-detected ECU PIDs, and includes a raw ELM327 AT command console.
- **Built-In Alto 800 Demo Mode:** Test every gauge, chart, and fault alert immediately without being plugged into the car.

---

## Important iOS Bluetooth Requirement
Apple's `CoreBluetooth` framework on iOS only supports **Bluetooth Low Energy (BLE 4.0 / 5.0)** OBD-II adapters — **not** older Bluetooth Classic 2.0/3.0 blue ELM327 dongles (which require Android SPP).

Compatible BLE adapters supported out of the box (`FFF0`, `FFE0`, `18F0`, `E7810A71-...`, plus dynamic GATT UART discovery):
- **Veepeak OBDCheck BLE / BLE+**
- **Vgate iCar Pro BLE 4.0**
- **OBDLink CX**
- **LELink / Generic ELM327 BLE 4.0+ adapters**

---

## Opening & Running on iPhone
1. Copy the `AltoOBDDashboard` folder to a Mac with **Xcode 15 or newer**.
2. Double-click **`AltoOBDDashboard.xcodeproj`** (or run `xcodegen generate` if you prefer regenerating from `project.yml`).
3. Select the **AltoOBDDashboard** target -> **Signing & Capabilities** -> pick your Apple ID **Team** (free personal Apple Developer account works for running on your own iPhone).
4. Plug in your iPhone, select it as the build destination, and click **Run (`Cmd + R`)**.
5. To preview before going to the car, open the **Connect** tab and enable **Suzuki Alto 800 Demo Mode**.

## Calibrating Mileage (MPG) to Your Alto 800
1. Fill your tank full and tap **Save & Reset** on the **Mileage** tab.
2. Drive normally, then refill to full and note the actual litres pumped vs. the app's `Fuel Burned`.
3. In **Connect -> Alto 800 Cruz Calibration**, adjust **Volumetric Efficiency** (default `82%`) up or down proportionally:
   - App reports *less* fuel than the pump -> increase VE slightly (e.g., `82% -> 86%`).
   - App reports *more* fuel than the pump -> decrease VE slightly (e.g., `82% -> 78%`).
