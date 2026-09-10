import Foundation

/// Builds the `upi://pay?...` deep link that hands a settle-up payment off to
/// whichever UPI app the payer has installed (`FEATURE_BACKLOG.md` "UPI deep
/// link on Settle Up") — ClanTab never sees or moves the money, it only
/// constructs the URI.
///
/// Pure and view-free so both `SettleUpView` and `MemberProfileView` share one
/// definition.
public enum UPIPayLink {
    /// - Parameters:
    ///   - vpa: the payee's UPI VPA (e.g. `name@bank`).
    ///   - payeeName: shown in the UPI app as the recipient.
    ///   - amountMinor: amount in integer minor units.
    ///   - currency: must be `"INR"` — UPI's only currency; any other returns `nil`.
    ///   - note: the transaction note (`tn`).
    /// - Returns: the deep link, or `nil` if the currency isn't INR or the VPA is blank.
    public static func url(
        vpa: String?,
        payeeName: String,
        amountMinor: Int64,
        currency: String,
        note: String = "ClanTab settle up"
    ) -> URL? {
        guard currency == "INR", let vpa, !vpa.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "upi"
        components.host = "pay"
        let amount = Decimal(amountMinor) / 100
        components.queryItems = [
            URLQueryItem(name: "pa", value: vpa),
            URLQueryItem(name: "pn", value: payeeName),
            URLQueryItem(name: "am", value: NSDecimalNumber(decimal: amount).stringValue),
            URLQueryItem(name: "cu", value: "INR"),
            URLQueryItem(name: "tn", value: note),
        ]
        return components.url
    }
}
