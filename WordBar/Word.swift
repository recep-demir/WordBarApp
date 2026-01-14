import Foundation

struct Word: Codable, Identifiable, Equatable {
    var id = UUID()
    let word: String
    let meaning: String
    let example: String
    var isLearned: Bool
    let pronunciation: String // New field
    
    enum CodingKeys: String, CodingKey {
        case word, meaning, example, isLearned, pronunciation
    }
}
