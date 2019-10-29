//
//  Character+Similar.swift
//  GiftCardReader
//
//  Created by B Gay on 10/28/19.
//  Copyright © 2019 B Gay. All rights reserved.
//

import Foundation

extension Character {
    // Given a list of allowed characters, try to convert self to those in list
    // if not already in it. This handles some common misclassifications for
    // characters that are visually similar and can only be correctly recognized
    // with more context and/or domain knowledge. Some examples (should be read
    // in Menlo or some other font that has different symbols for all characters):
    // 1 and l are the same character in Times New Roman
    // I and l are the same character in Helvetica
    // 0 and O are extremely similar in many fonts
    // oO, wW, cC, sS, pP and others only differ by size in many fonts
    func getSimilarCharacterIfNotIn(allowedChars: String) -> Character {
        let conversionTable = [
            "s": "S",
            "S": "5",
            "5": "S",
            "o": "O",
            "Q": "O",
            "O": "0",
            "0": "O",
            "l": "I",
            "I": "1",
            "1": "I",
            "B": "8",
            "8": "B"
        ]
        // Allow a maximum of two substitutions to handle 's' -> 'S' -> '5'.
        let maxSubstitutions = 2
        var current = String(self)
        var counter = 0
        while !allowedChars.contains(current) && counter < maxSubstitutions {
            if let altChar = conversionTable[current] {
                current = altChar
                counter += 1
            } else {
                // Doesn't match anything in our table. Give up.
                break
            }
        }
        
        return current.first!
    }
}
