//
//  AppUser.swift
//  PokeCard
//
//  A lightweight, SDK-agnostic representation of an authenticated user.
//  Keeping this separate from Firebase's User type means the rest of the
//  app never imports Firebase directly, which makes testing and previews easy.
//

import Foundation

struct AppUser: Identifiable, Equatable {
    let id: String          // provider UID
    let email: String?
    let displayName: String?
    let photoURL: URL?

    init(id: String, email: String? = nil, displayName: String? = nil, photoURL: URL? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
    }
}
