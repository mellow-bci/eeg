import Foundation

extension EEGSample {
    /// Index/counter adjacency only, not timing, transport or signal validity.
    /// Imported Int values may reach the integer boundary. Subtract only from
    /// a known-positive successor; never overflow the previous sample index.
    func followsIndexAndCounter(_ previous: EEGSample) -> Bool {
        index > 0 && previous.index >= 0 && index - 1 == previous.index &&
        (0..<128).contains(counter) && (0..<128).contains(previous.counter) &&
        counter == (previous.counter + 1) % 128
    }
}
