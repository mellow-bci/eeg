# Native Apple application and BCI HID boundary

Research checkpoint 2026-09-15. This is an integration design, not a hardware qualification.

## Verified Apple reference

Apple publishes a manufacturer-facing firmware/HID reference for BCI hardware. Its article
metadata lists iOS 26, iPadOS 26 and visionOS 26; it does not establish macOS availability.
The host receives interpreted signals through HID for accessibility interaction. The
manufacturer remains responsible for translating sensor activity into intent. Reports cover
signal feedback (ID 1), button states (ID 2), pointer input (ID 3), and item selection / host
scan feedback (ID 4, distinguished by direction). The examples use IOHIDUserDevice calls;
this alone does not establish that an ordinary sandboxed iOS application may create a
system-wide HID device. [Apple BCI HID reference](https://developer.apple.com/documentation/accessibility/brain-computer-interface-hid-reference-for-connecting-to-apple-platforms)

The linked Markdown was fetched from Apple's `.md` endpoint because the HTML documentation
requires JavaScript. No proprietary Apple implementation was copied into this repository.

## Proposed separation of responsibilities

1. **Acquisition:** CoreBluetooth receives EPOC X notifications. Our decoder produces
   timestamped raw EEG and quality metadata. This is independent of HID.
2. **Interpretation:** A separately validated, calibrated classifier emits an intentional
   command with confidence, provenance and an expiry. No classifier means no EEG-triggered
   accessibility actions.
3. **Action policy:** Explicit arming, idle state, confirmation where appropriate,
   rate limits, cancellation and a visible kill switch govern commands.
4. **Output adapter:** Deliver supported commands through the platform's verified
   accessibility/HID integration. A hardware bridge may be needed; a SwiftUI app is not
   automatically a HID peripheral or system input driver.
5. **Host feedback:** Consume only supported contextual feedback and expire stale selection
   state. Never treat it as unrestricted access to another application's content.

## Platform qualification checklist

| Platform target | Must establish before claiming support |
|---|---|
| macOS SwiftUI | Signed app/service packaging, Bluetooth permission behavior, background capture, sleep/wake and storage recovery; independently verify available HID mechanism and required entitlements. |
| iOS/iPadOS SwiftUI | Physical-device BLE connection to this exact EPOC X mode; foreground/background and interruption constraints; storage/export behavior; OS-supported external BCI/HID bridge and accessibility setup. |
| visionOS SwiftUI | Physical headset testing of BLE availability, permissions, lifecycle and accessibility integration; simulator UI success is insufficient. |
| External bridge, if required | Firmware descriptor/report conformance, delivery/release semantics, command expiry, reconnect neutralization and host compatibility. |

Share Swift domain types, decoder tests and recording contracts where feasible. Keep
platform adapters explicit. Preserve a replay mode for demonstrations and tests, prominently
labeled so it cannot be confused with live hardware or actual decoded intent.
