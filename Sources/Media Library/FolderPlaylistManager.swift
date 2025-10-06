/*****************************************************************************
 * FolderPlaylistManager.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright © 2025 VideoLAN. All rights reserved.
 *
 * Authors: VLC iOS Team
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import Foundation
import VLCMediaLibraryKit

/// Manages automatic playlist creation from folders
class FolderPlaylistManager {
    
    private weak var mediaLibraryService: MediaLibraryService?
    private var processedFolders = Set<String>()
    private let userDefaults = UserDefaults.standard
    private let processedFoldersKey = "VLCProcessedFolderPlaylists"
    private var folderPlaylistMapping = [String: VLCMLPlaylist]() // Maps folder paths to playlists
    
    init(mediaLibraryService: MediaLibraryService) {
        self.mediaLibraryService = mediaLibraryService
        loadProcessedFolders()
    }
    
    // MARK: - Public Methods
    
    /// Scans a folder and creates a playlist with its media files
    /// - Parameter folderPath: The path to the folder to scan
    /// - Returns: The created playlist, or nil if creation failed
    @discardableResult
    func createPlaylistFromFolder(at folderPath: String) -> VLCMLPlaylist? {
        guard let mediaLibraryService = mediaLibraryService else { return nil }
        
        let folderURL = URL(fileURLWithPath: folderPath)
        let folderName = folderURL.lastPathComponent
        
        // Check if we've already processed this folder
        if processedFolders.contains(folderPath) {
            APLog("Folder playlist already exists for: \(folderName)")
            return nil
        }
        
        // Get all media files in the folder
        let mediaFiles = scanFolderForMediaFiles(at: folderPath)
        
        // Only create playlist if there are media files
        guard !mediaFiles.isEmpty else {
            APLog("No media files found in folder: \(folderName)")
            return nil
        }
        
        // Check if a playlist with this name already exists
        let existingPlaylists = mediaLibraryService.playlists()
        let playlistName = generateUniquePlaylistName(baseName: folderName, existingPlaylists: existingPlaylists)
        
        // Create the playlist
        guard let playlist = mediaLibraryService.createPlaylist(with: playlistName) else {
            APLog("Failed to create playlist for folder: \(folderName)")
            return nil
        }
        
        // Add media files to the playlist
        for mediaFile in mediaFiles {
            if let mlMedia = mediaLibraryService.fetchMedia(with: mediaFile) {
                playlist.append(mlMedia)
            } else if let mlMedia = mediaLibraryService.medialib.addExternalMedia(withMrl: mediaFile) {
                // If media is not in library, add it first
                playlist.append(mlMedia)
            }
        }
        
        // Mark folder as processed and store mapping
        processedFolders.insert(folderPath)
        folderPlaylistMapping[folderPath] = playlist
        saveProcessedFolders()
        
        APLog("Created playlist '\(playlistName)' with \(mediaFiles.count) files from folder: \(folderName)")
        return playlist
    }
    
    /// Processes newly discovered folders
    /// - Parameter folderPaths: Array of folder paths to process
    func processNewFolders(_ folderPaths: [String]) {
        for folderPath in folderPaths {
            createPlaylistFromFolder(at: folderPath)
        }
    }
    
    /// Updates a folder playlist when a new file is added
    /// - Parameters:
    ///   - filePath: Path to the newly added file
    func updatePlaylistForNewFile(at filePath: String) {
        guard let mediaLibraryService = mediaLibraryService else { return }
        
        // Get the folder containing this file
        let fileURL = URL(fileURLWithPath: filePath)
        let folderPath = fileURL.deletingLastPathComponent().path
        
        // Check if we have a playlist for this folder
        guard let playlist = getPlaylistForFolder(at: folderPath) else {
            // No playlist exists for this folder yet, check if we should create one
            if shouldCreatePlaylistForFolder(at: folderPath) {
                createPlaylistFromFolder(at: folderPath)
            }
            return
        }
        
        // Check if this is a media file
        let fileName = fileURL.lastPathComponent
        guard fileName.isSupportedMediaFormat() || fileName.isSupportedAudioMediaFormat() else {
            return
        }
        
        // Add the new file to the playlist if it's not already there
        if let mlMedia = mediaLibraryService.fetchMedia(with: fileURL) {
            // Check if media is already in playlist
            if let existingMedia = playlist.media(with: .default, desc: false),
               !existingMedia.contains(where: { $0.identifier() == mlMedia.identifier() }) {
                playlist.append(mlMedia)
                APLog("Added new file '\(fileName)' to playlist '\(playlist.name)'")
            }
        } else if let mlMedia = mediaLibraryService.medialib.addExternalMedia(withMrl: fileURL) {
            playlist.append(mlMedia)
            APLog("Added new file '\(fileName)' to playlist '\(playlist.name)'")
        }
    }
    
    /// Gets the playlist associated with a folder
    /// - Parameter folderPath: Path to the folder
    /// - Returns: The playlist for the folder, or nil if none exists
    private func getPlaylistForFolder(at folderPath: String) -> VLCMLPlaylist? {
        // First check our cache
        if let playlist = folderPlaylistMapping[folderPath] {
            return playlist
        }
        
        // If not in cache, search through existing playlists
        guard let mediaLibraryService = mediaLibraryService else { return nil }
        let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        let playlists = mediaLibraryService.playlists()
        
        // Look for a playlist with the folder name
        for playlist in playlists {
            if playlist.name == folderName || playlist.name.hasPrefix(folderName + " (") {
                folderPlaylistMapping[folderPath] = playlist
                return playlist
            }
        }
        
        return nil
    }
    
    /// Checks if a path is a folder that should have a playlist
    /// - Parameter path: The path to check
    /// - Returns: True if the path is a valid folder for playlist creation
    func shouldCreatePlaylistForFolder(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        
        guard exists && isDirectory.boolValue else { return false }
        
        // Skip system folders and hidden folders
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        if folderName.hasPrefix(".") || folderName == "Documents" {
            return false
        }
        
        // Check if folder contains media files
        let mediaFiles = scanFolderForMediaFiles(at: path)
        return !mediaFiles.isEmpty
    }
    
    // MARK: - Private Methods
    
    private func scanFolderForMediaFiles(at folderPath: String) -> [URL] {
        var mediaFiles: [URL] = []
        
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(atPath: folderPath)
            
            for fileName in contents {
                let filePath = (folderPath as NSString).appendingPathComponent(fileName)
                var isDirectory: ObjCBool = false
                
                if fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory) {
                    if !isDirectory.boolValue {
                        // Check if it's a supported media file
                        if fileName.isSupportedMediaFormat() || fileName.isSupportedAudioMediaFormat() {
                            mediaFiles.append(URL(fileURLWithPath: filePath))
                        }
                    }
                }
            }
        } catch {
            APLog("Error scanning folder \(folderPath): \(error.localizedDescription)")
        }
        
        return mediaFiles
    }
    
    private func generateUniquePlaylistName(baseName: String, existingPlaylists: [VLCMLPlaylist]) -> String {
        var name = baseName
        var counter = 1
        
        let existingNames = Set(existingPlaylists.map { $0.name })
        
        while existingNames.contains(name) {
            name = "\(baseName) (\(counter))"
            counter += 1
        }
        
        return name
    }
    
    private func loadProcessedFolders() {
        if let savedFolders = userDefaults.array(forKey: processedFoldersKey) as? [String] {
            processedFolders = Set(savedFolders)
        }
    }
    
    private func saveProcessedFolders() {
        userDefaults.set(Array(processedFolders), forKey: processedFoldersKey)
    }
    
    /// Resets the processed folders list (useful for debugging or user preference)
    func resetProcessedFolders() {
        processedFolders.removeAll()
        userDefaults.removeObject(forKey: processedFoldersKey)
    }
}

// MARK: - String Extension for Media Format Check

extension String {
    func isSupportedMediaFormat() -> Bool {
        let videoExtensions = "\\.(3g2|3gp|3gp2|3gpp|amv|asf|avi|divx|drc|dv|f4v|flv|gvi|gxf|ismv|iso|m1v|m2v|m2t|m2ts|m4v|mkv|mov|mp2|mp2v|mp4|mp4v|mpe|mpeg|mpeg1|mpeg2|mpeg4|mpg|mpv2|mts|mtv|mxf|mxg|nsv|nut|nuv|ogm|ogv|ogx|ps|rec|rm|rmvb|tod|ts|tts|vob|vro|webm|wm|wmv|wtv|xesc)$"
        let regex = try? NSRegularExpression(pattern: videoExtensions, options: .caseInsensitive)
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex?.firstMatch(in: self, options: [], range: range) != nil
    }
    
    func isSupportedAudioMediaFormat() -> Bool {
        let audioExtensions = "\\.(3ga|669|a52|aa3|aac|ac3|adt|adts|aif|aifc|aiff|amb|amr|aob|ape|at3|au|awb|caf|dts|flac|it|kar|m4a|m4b|m4p|m5p|mid|mka|mlp|mod|mpa|mp1|mp2|mp3|mpc|mpga|mus|oga|ogg|oma|opus|qcp|ra|rmi|s3m|sid|spx|tak|thd|tta|voc|vqf|w64|wav|wma|wv|xa|xm)$"
        let regex = try? NSRegularExpression(pattern: audioExtensions, options: .caseInsensitive)
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex?.firstMatch(in: self, options: [], range: range) != nil
    }
}