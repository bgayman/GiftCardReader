//
//  String+GiftCard.swift
//  GiftCardReader
//
//  Created by B Gay on 10/28/19.
//  Copyright © 2019 B Gay. All rights reserved.
//

import Foundation

extension String {
    // Extracts the first US-style phone number found in the string, returning
    // the range of the number and the number itself as a tuple.
    // Returns nil if no number is found.
    func extractGiftCard() -> (Range<String.Index>, String)? {
        // Do a first pass to find any substring that could be a US phone
        // number. This will match the following common patterns and more:
        // xxx-xxx-xxxx
        // xxx xxx xxxx
        // (xxx) xxx-xxxx
        // (xxx)xxx-xxxx
        // xxx.xxx.xxxx
        // xxx xxx-xxxx
        // xxx/xxx.xxxx
        // +1-xxx-xxx-xxxx
        // Note that this doesn't only look for digits since some digits look
        // very similar to letters. This is handled later.
        let pattern = #"""
        (?x)                    # Verbose regex, allows comments
        \b(\w{4})                # Capture xxxx
        [\ -./]?                # Potential separator
        (\w{4})                    # Capture xxxx
        [\ -./]?                # Potential separator
        (\w{4})\b                # Capture xxxx
        [\ -./]?                # Potential separator
        (\w{4})\b                # Capture xxxx
        """#
        
        guard let range = self.range(of: pattern, options: .regularExpression, range: nil, locale: nil) else {
            // No phone number found.
            return nil
        }
        
        // Potential number found.
        let giftCardDigits = String(self[range])
        
        // Must be exactly 10 digits.
        guard giftCardDigits.count == 19 else {
            return nil
        }
        
        // Substitute commonly misrecognized characters, for example: 'S' -> '5' or 'l' -> '1'
        var result = ""
        let allowedChars = "0123456789 "
        for var char in giftCardDigits {
            char = char.getSimilarCharacterIfNotIn(allowedChars: allowedChars)
            guard allowedChars.contains(char) else {
                return nil
            }
            result.append(char)
        }
        return (range, result)
    }
}
