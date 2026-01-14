import Foundation
import Observation
import UserNotifications
import ServiceManagement

// Notification time limits
private let startHour = 8   // 08:00
private let endHour = 23    // 23:00

@Observable
class WordManager: NSObject, UNUserNotificationCenterDelegate {
    var allWords: [Word] = []
    var dailyWords: [Word] = []
    var currentIndex: Int = 0
    var lastLearnedWord: Word?
    
    // Update existing property observer
        var isAutoChangeEnabled: Bool = false {
            didSet {
                UserDefaults.standard.set(isAutoChangeEnabled, forKey: "isAutoChangeEnabled")
                if isAutoChangeEnabled {
                    // When enabled, schedule the NEXT one based on interval,
                    // OR trigger one now if you prefer. Let's stick to interval loop logic:
                    startTimer()
                } else {
                    timer?.invalidate() // Stop timer
                    cancelAllNotifications()
                }
            }
        }
    
    var selectedInterval: TimeInterval = 1800 {
        didSet {
            UserDefaults.standard.set(selectedInterval, forKey: "SelectedInterval")
            // Restart the timer and schedule notifications with the new interval
            startTimer()
        }
    }
    
    // Launch at login logic
    var isLaunchAtLoginEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch { print("Launch error: \(error.localizedDescription)") }
        }
    }
    
    private var timer: Timer?
    private let fileURL: URL
    
    var currentWord: Word? {
        if dailyWords.indices.contains(currentIndex) {
            return dailyWords[currentIndex]
        }
        return dailyWords.first
    }
    
    override init() {
        // 1. Set File Path
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = appSupport.appendingPathComponent("words.json")
        
        super.init()
        
        // 2. Setup Notifications
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        
        // 3. Load Persistent Settings
        loadSavedSettings()
        
        // 4. Load existing Daily Loop BEFORE syncing
        setupDailyWords()
        
        // 5. Sync with JSON and start
        syncWithBundleJSON()
        
        // Start the loop
        startTimer()
    }
    
    // MARK: - Core Functions
    
    private func loadSavedSettings() {
        let savedInterval = UserDefaults.standard.double(forKey: "SelectedInterval")
        self.selectedInterval = savedInterval == 0 ? 1800 : savedInterval
        self.isAutoChangeEnabled = UserDefaults.standard.bool(forKey: "isAutoChangeEnabled")
    }

    func syncWithBundleJSON() {
        guard let bundleURL = Bundle.main.url(forResource: "words", withExtension: "json"),
              let bundleData = try? Data(contentsOf: bundleURL),
              let bundleWords = try? JSONDecoder().decode([Word].self, from: bundleData) else { return }
        
        if let existingData = try? Data(contentsOf: fileURL),
           let existingWords = try? JSONDecoder().decode([Word].self, from: existingData) {
            
            var updatedWords: [Word] = []
            for bWord in bundleWords {
                if let existing = existingWords.first(where: { $0.word == bWord.word }) {
                    var updated = bWord
                    updated.isLearned = existing.isLearned
                    updatedWords.append(updated)
                } else {
                    updatedWords.append(bWord)
                }
            }
            self.allWords = updatedWords
        } else {
            self.allWords = bundleWords
        }
        
        saveAllWordsToDisk()
        cleanDailyWords()
    }

    private func cleanDailyWords() {
        dailyWords = dailyWords.filter { dw in allWords.contains(where: { $0.word == dw.word }) }
        
        if dailyWords.isEmpty && !allWords.isEmpty {
            dailyWords = Array(allWords.filter({ !$0.isLearned }).shuffled().prefix(7))
            currentIndex = 0
            saveProgress()
        }
    }

    @MainActor
    func markAsLearned() {
        guard !dailyWords.isEmpty else { return }
        let word = dailyWords.remove(at: currentIndex)
        var updatedWord = word
        updatedWord.isLearned = true
        
        self.lastLearnedWord = updatedWord
        
        Task {
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            await MainActor.run {
                if self.lastLearnedWord?.word == updatedWord.word {
                    self.lastLearnedWord = nil
                }
            }
        }
        
        if let index = allWords.firstIndex(where: { $0.word == word.word }) {
            allWords[index].isLearned = true
            saveAllWordsToDisk()
        }
        
        if currentIndex >= dailyWords.count { currentIndex = 0 }
        saveProgress()
        // Word list changed, so we need to update the schedule
        scheduleNotification(delay: 1)
    }

    @MainActor
    func undoLastLearned() {
        guard var word = lastLearnedWord else { return }
        word.isLearned = false
        dailyWords.insert(word, at: currentIndex)
        
        if let index = allWords.firstIndex(where: { $0.word == word.word }) {
            allWords[index].isLearned = false
            saveAllWordsToDisk()
        }
        lastLearnedWord = nil
        saveProgress()
        // Word list changed, update schedule
        scheduleNotification(delay: 1)
    }

    @MainActor
    func resetAllData() {
        UserDefaults.standard.removeObject(forKey: "DailyWords")
        UserDefaults.standard.removeObject(forKey: "CurrentIndex")
        try? FileManager.default.removeItem(at: fileURL)
        
        syncWithBundleJSON()
        setupDailyWords()
        lastLearnedWord = nil
        startTimer() // Restart logic
    }

    // MARK: - Helpers

    func removeFromLoop(at index: Int) {
        guard dailyWords.indices.contains(index) else { return }
        dailyWords.remove(at: index)
        if currentIndex >= dailyWords.count { currentIndex = 0 }
        saveProgress()
        scheduleNotification(delay: 1)
    }
    
    func addNewWordToLoop() {
        let currentIds = dailyWords.map { $0.word }
        if let newWord = allWords.filter({ !$0.isLearned && !currentIds.contains($0.word) }).randomElement() {
            dailyWords.append(newWord)
            saveProgress()
            scheduleNotification(delay: 1)
        }
    }
    
    func nextWord(automatically: Bool = false) {
            if automatically && !isAutoChangeEnabled { return }
            guard !dailyWords.isEmpty else { return }
            
            // Move to next index
            currentIndex = (currentIndex + 1) % dailyWords.count
            saveProgress()
            
            // Trigger notification IMMEDIATELY (1 second delay) because the word just changed
            if isAutoChangeEnabled {
                scheduleNotification(delay: 1)
            }
        }
    
    func saveAllWordsToDisk() {
        if let data = try? JSONEncoder().encode(allWords) {
            try? data.write(to: fileURL)
        }
    }
    
    func saveProgress() {
        let data = try? JSONEncoder().encode(dailyWords)
        UserDefaults.standard.set(data, forKey: "DailyWords")
        UserDefaults.standard.set(currentIndex, forKey: "CurrentIndex")
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func setupDailyWords() {
        if let savedData = UserDefaults.standard.data(forKey: "DailyWords"),
           let decoded = try? JSONDecoder().decode([Word].self, from: savedData) {
            self.dailyWords = decoded
            self.currentIndex = UserDefaults.standard.integer(forKey: "CurrentIndex")
        }
    }
    
    // MARK: - Improved Timer & Scheduler Logic
    
    func startTimer() {
        timer?.invalidate()
        
        // 1. Internal Timer: Keeps the app UI updated if the app is awake
        timer = Timer.scheduledTimer(withTimeInterval: selectedInterval, repeats: true) { _ in
            self.nextWord(automatically: true)
        }
        
        // 2. System Scheduler: Ensures notification fires even if screen is off
        if isAutoChangeEnabled {
            scheduleNotification(delay: 1)
        }
    }
    
    /// Schedules or sends a notification.
        /// - Parameter delay: If nil, uses `selectedInterval`. If set (e.g., 1.0), sends almost immediately.
        func scheduleNotification(delay: TimeInterval? = nil) {
            // 1. Cancel pending requests to avoid duplicates
            cancelAllNotifications()
            
            guard !dailyWords.isEmpty, isAutoChangeEnabled else { return }
            
            // 2. Use the CURRENT word, not the next one, because the index has already updated in nextWord()
            guard let wordToNotify = currentWord else { return }
            
            // 3. Time Restriction Check (08:00 - 23:00)
            let currentHour = Calendar.current.component(.hour, from: Date())
            if currentHour < startHour || currentHour >= endHour {
                print("Notification skipped due to time restriction (Hour: \(currentHour))")
                return
            }

            // 4. Content Content
            let content = UNMutableNotificationContent()
            content.title = "\(wordToNotify.word)"
            content.body = "\(wordToNotify.pronunciation) - \(wordToNotify.meaning)"
            content.sound = .default
            
            // 5. Determine Trigger Time
            // If delay is provided (immediate), use it. Otherwise use selectedInterval.
            let timeInterval = delay ?? selectedInterval
            
            // Triggers must be at least greater than 0
            let safeInterval = max(timeInterval, 1.0)
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: safeInterval, repeats: false)
            let request = UNNotificationRequest(identifier: "word_notification", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling notification: \(error.localizedDescription)")
                } else {
                    print("Notification scheduled in \(safeInterval) seconds.")
                }
            }
        }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
