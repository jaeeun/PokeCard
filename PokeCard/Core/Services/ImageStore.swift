//
//  ImageStore.swift
//  PokeCard
//
//  Saves user-captured card images into the app's sandbox (Documents) and
//  loads them back. Only the user's own photos are stored — never third-party
//  artwork.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

enum ImageStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("cards", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a CGImage as JPEG and returns the stored file name.
    @discardableResult
    static func save(_ image: CGImage, quality: CGFloat = 0.85) -> String? {
        let name = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        return CGImageDestinationFinalize(dest) ? name : nil
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    #if canImport(UIKit)
    static func loadUIImage(_ fileName: String?) -> UIImage? {
        guard let fileName else { return nil }
        return UIImage(contentsOfFile: url(for: fileName).path)
    }
    #endif

    static func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
