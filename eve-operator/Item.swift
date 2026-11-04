//
//  Item.swift
//  eve-operator
//
//  Created by lesha on 4. 11. 2026..
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
