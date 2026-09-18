struct LabelMedia {
  let barcode: String
  let width: Int
  let height: Int
  let name: String

  static let fallback = LabelMedia(
    barcode: "unknown", width: 160, height: 80, name: "Unknown label")
}
