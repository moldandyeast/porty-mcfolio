import Foundation

enum GallerySelection: Hashable {
    case file(URL)
    case folder(URL)
    case link(String)  // LinkItem.id
}
