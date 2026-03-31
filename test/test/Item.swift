//
//  Item.swift
//  test
//
//  Created by cbzw008 on 2026/3/31.
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
