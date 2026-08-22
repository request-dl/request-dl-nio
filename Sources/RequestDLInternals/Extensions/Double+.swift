//
// See LICENSE for this package's licensing information.
//

extension Double {

    /// This value as a decimal string with a fixed number of fraction digits.
    ///
    /// Replaces `String(format: "%.3f", self)`. `String(format:)` is not part of
    /// `FoundationEssentials`, and its `%f` handling is among the weaker parts of the
    /// reimplementation on the platforms this package targets off Apple.
    ///
    /// Rounds half away from zero, as `%f` does.
    ///
    /// - Note: For logs and diagnostics. It is not locale aware, and deliberately so: a decimal
    /// point that turns into a comma depending on who is running the process makes log output
    /// harder to parse, not easier to read.
    package func fixed(fractionDigits: Int) -> String {
        guard isFinite else {
            return "\(self)"
        }

        guard fractionDigits > .zero else {
            return "\(Int64(rounded()))"
        }

        let scale = Double.pow(10 as Double, Double(fractionDigits))
        let scaled = Int64((self * scale).rounded())

        let whole = scaled / Int64(scale)
        var fraction = String((scaled % Int64(scale)).magnitude)

        while fraction.count < fractionDigits {
            fraction = "0" + fraction
        }

        // The sign lives on `whole`, unless the whole part rounded to zero and the value was
        // negative, in which case it would be lost.
        let sign = self < 0 && whole == 0 ? "-" : ""

        return "\(sign)\(whole).\(fraction)"
    }
}
