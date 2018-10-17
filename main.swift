#!/usr/bin/swift

/**
 *  SwiftPlate
 *
 *  Copyright (c) 2016 John Sundell. Licensed under the MIT license, as follows:
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to deal
 *  in the Software without restriction, including without limitation the rights
 *  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in all
 *  copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 *  SOFTWARE.
 */

import Foundation

// MARK: - Extensions

extension Process {
    @discardableResult func launchBash(withCommand command: String) -> String? {
        launchPath = "/bin/bash"
        arguments = ["-c", command]
        
        let pipe = Pipe()
        standardOutput = pipe
        
        // Silent errors by assigning a dummy pipe to the error output
        standardError = Pipe()
        
        launch()
        waitUntilExit()
        
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8)?.nonEmpty
    }
    
    func gitConfigValue(forKey key: String) -> String? {
        return launchBash(withCommand: "git config --global --get \(key)")?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    var nonEmpty: String? {
        guard count > 0 else {
            return nil
        }
        
        return self
    }
    
    func withoutSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else {
            return self
        }
        
        let startIndex = index(endIndex, offsetBy: -suffix.count)
        return replacingCharacters(in: startIndex..<endIndex, with: "")
    }
}

extension FileManager {
    func isFolder(atPath path: String) -> Bool {
        var objCBool: ObjCBool = false
        
        guard fileExists(atPath: path, isDirectory: &objCBool) else {
            return false
        }
        
        return objCBool.boolValue
    }
}

extension Array {
    func element(after index: Int) -> Element? {
        guard index >= 0 && index < count else {
            return nil
        }
        
        return self[index + 1]
    }
}

// MARK: - Types

struct Arguments {
    var platform: String?
    var destination: String?
    var projectName: String?
    var authorName: String?
    var organizationName: String?
    var repositoryURL: URL?
    var forceEnabled: Bool = false
    
    init(commandLineArguments arguments: [String]) {
        for (index, argument) in arguments.enumerated() {
            switch argument.lowercased() {
            case "--platform", "-pl":
                platform = arguments.element(after: index)
            case "--destination", "-d":
                destination = arguments.element(after: index)
            case "--project", "-p":
                projectName = arguments.element(after: index)
            case "--name", "-n":
                authorName = arguments.element(after: index)
            case "--organization", "-o":
                organizationName = arguments.element(after: index)
            case "--repo", "-r":
                if let urlString = arguments.element(after: index) {
                    repositoryURL = URL(string: urlString)
                }
            case "--force", "-f":
                forceEnabled = true
            default:
                break
            }
        }
    }
}

class StringReplacer {
    private let projectName: String
    private let authorName: String
    private let year: String
    private let today: String
    private let organizationName: String
    private let bundleId: String
    
    init(projectName: String, authorName: String, organizationName: String, bundleId: String) {
        self.projectName = projectName
        self.authorName = authorName
        self.organizationName = organizationName
        self.bundleId = bundleId
        

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "YYYY"
        self.year = yearFormatter.string(from: Date())

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        self.today = dateFormatter.string(from: Date())
    }
    
    private var dateString: String {
        return DateFormatter.localizedString(
            from: Date(),
            dateStyle: DateFormatter.Style.medium,
            timeStyle: DateFormatter.Style.none
        )
    }
    
    func process(string: String) -> String {
        return string.replacingOccurrences(of: "{PROJECT}", with: projectName)
                     .replacingOccurrences(of: "{AUTHOR}", with: authorName)
                     .replacingOccurrences(of: "{YEAR}", with: year)
                     .replacingOccurrences(of: "{TODAY}", with: today)
                     .replacingOccurrences(of: "{DATE}", with: dateString)
                     .replacingOccurrences(of: "{ORGANIZATION}", with: organizationName)
                     .replacingOccurrences(of: "{BUNDLEID}", with: bundleId)

        
    }
    
    func process(filesInFolderWithPath folderPath: String) throws {
        let fileManager = FileManager.default
        let currentFileName = URL.init(fileURLWithPath: #file).lastPathComponent

        for itemName in try fileManager.contentsOfDirectory(atPath: folderPath) {
            if itemName.hasPrefix(".") || itemName == currentFileName {
                continue
            }

            let itemPath = folderPath + "/" + itemName
            let newItemPath = folderPath + "/" + process(string: itemName)
            
            if fileManager.isFolder(atPath: itemPath) {
                try process(filesInFolderWithPath: itemPath)
                try fileManager.moveItem(atPath: itemPath, toPath: newItemPath)
                continue
            }
            
            let fileContents = try String(contentsOfFile: itemPath)
            try process(string: fileContents).write(toFile: newItemPath, atomically: false, encoding: .utf8)
            
            if newItemPath != itemPath {
                try fileManager.removeItem(atPath: itemPath)
            }
        }
    }
}

// MARK: - Functions

func printError(_ message: String) {
    print("👮  \(message)")
}

func askForRequiredInfo(question: String, errorMessage errorMessageClosure: @autoclosure () -> String) -> String {
    print(question)
    
    guard let info = readLine()?.nonEmpty else {
        printError("\(errorMessageClosure()). Try again.")
        return askForRequiredInfo(question: question, errorMessage: errorMessageClosure)
    }
    
    return info
}

func askForOptionalInfo(question: String, questionSuffix: String = "You may leave this empty.") -> String? {
    print("\(question) \(questionSuffix)")
    return readLine()?.nonEmpty
}

func askForBooleanInfo(question: String) -> Bool {
    let errorMessage = "Please enter Y/y (yes) or N/n (no)"
    let answerString = askForRequiredInfo(question: "\(question) (Y/N)", errorMessage: errorMessage)
    
    switch answerString.lowercased() {
    case "y":
        return true
    case "n":
        return false
    default:
        printError("\(errorMessage). Try again.")
        return askForBooleanInfo(question: question)
    }
}

func askForPlatformType() -> String {
    let defaultPlatform = "iOS"
    
    let platformType = askForOptionalInfo(
        question: "📱  Is this an iOS project or a macOS project?",
        questionSuffix: "(Leave empty to default to iOS)"
    )
    
    return platformType ?? defaultPlatform
}

func askForDestination() -> String {
    let destination = askForOptionalInfo(
        question: "📦  Where would you like to generate a project?",
        questionSuffix: "(Leave empty to use current directory)"
    )
    
    let fileManager = FileManager.default
    
    if let destination = destination {
        guard fileManager.fileExists(atPath: destination) else {
            printError("That path doesn't exist. Try again.")
            return askForDestination()
        }
        
        return destination
    }
    
    return fileManager.currentDirectoryPath
}

func askForProjectName(destination: String) -> String {
    let projectFolderName = destination.withoutSuffix("/").components(separatedBy: "/").last!
    
    let projectName = askForOptionalInfo(
        question: "📛  What's the name of your project?",
        questionSuffix: "(Leave empty to use the name of the project folder: \(projectFolderName))"
    )
    
    return projectName ?? projectFolderName
}

func askForAuthorName() -> String {
    let gitName = Process().gitConfigValue(forKey: "user.name")
    let question = "👶  What's your name?"
    
    if let gitName = gitName {
        let authorName = askForOptionalInfo(question: question, questionSuffix: "(Leave empty to use your git config name: \(gitName))")
        return authorName ?? gitName
    }
    
    return askForRequiredInfo(question: question, errorMessage: "Your name cannot be empty")
}

func performCommand(description: String, command: () throws -> Void) rethrows {
    print("👉  \(description)...")
    try command()
    print("✅  Done")
}
// MARK: - Program

print("Welcome to the SwiftPlate project generator 🐣")

let arguments = Arguments(commandLineArguments: CommandLine.arguments)
let platform = arguments.platform ?? askForPlatformType()
let destination = arguments.destination ?? askForDestination()
let projectName = arguments.projectName ?? askForProjectName(destination: destination)
let authorName = arguments.authorName ?? askForAuthorName()
let organizationName = "Ramsey Solutions"
let bundleId = "ramseysolutions"


print("---------------------------------------------------------------------")
print("SwiftPlate will now generate a project with the following parameters:")
print("📱  Platform: \(platform)")
print("📦  Destination: \(destination)")
print("📛  Name: \(projectName)")
print("👶  Author: \(authorName)")
print("🏢  Organization Name: \(organizationName)")

print("---------------------------------------------------------------------")

if !arguments.forceEnabled {
    if !askForBooleanInfo(question: "Proceed? ✅") {
        exit(0)
    }
}

print("🚀  Starting to generate project \(projectName)...")

do {
    let fileManager = FileManager.default
    let temporaryDirectoryPath = destination + "/swiftplate_temp"
    let gitClonePath = "\(temporaryDirectoryPath)/SwiftPlate"
    let iOSTemplatePath = "\(gitClonePath)/iOSTemplate"
    let macOSTemplatePath = "\(gitClonePath)/macOSTemplate"
    
    performCommand(description: "Removing any previous temporary folder") {
        try? fileManager.removeItem(atPath: temporaryDirectoryPath)
    }
    
    try performCommand(description: "Making temporary folder (\(temporaryDirectoryPath))") {
        try fileManager.createDirectory(atPath: temporaryDirectoryPath, withIntermediateDirectories: false, attributes: nil)
    }
    
    performCommand(description: "Making a local clone of the SwiftPlate repo") {
        let repositoryURL = arguments.repositoryURL ?? URL(string: "https://github.com/lampo/SwiftPlate.git")!
        Process().launchBash(withCommand: "git clone \(repositoryURL.absoluteString) '\(gitClonePath)' -q")
    }
    
    try performCommand(description: "Copying template folder") {
        let ignorableItems: Set<String> = ["readme.md", "license"]
        let ignoredItems = try fileManager.contentsOfDirectory(atPath: destination).map {
            $0.lowercased()
        }.filter {
            ignorableItems.contains($0)
        }
        
        let path = platform == "iOS" ? iOSTemplatePath : macOSTemplatePath

        for itemName in try fileManager.contentsOfDirectory(atPath: path) {
            let originPath = path + "/" + itemName
            let destinationPath = destination + "/" + itemName

            let lowercasedItemName = itemName.lowercased()
            guard ignoredItems.contains(lowercasedItemName) == false else {
                continue
            }

            try fileManager.copyItem(atPath: originPath, toPath: destinationPath)
        }
    }
    
    try performCommand(description: "Removing temporary folder") {
        try fileManager.removeItem(atPath: temporaryDirectoryPath)
    }
    
    try performCommand(description: "Filling in template") {
        let replacer = StringReplacer(
            projectName: projectName,
            authorName: authorName,
            organizationName: organizationName,
            bundleId: bundleId
        )
        
        try replacer.process(filesInFolderWithPath: destination)
    }
    
    performCommand(description: "Setting up Carthage (running Carthage bootstrap)") {
        Process().launchBash(withCommand: "cd \(destination) && carthage update")
    }
    
    print("All done! 🎉  Good luck with your project! 🚀")
} catch {
    print("An error was encountered 🙁")
    print("Error: \(error)")
}
