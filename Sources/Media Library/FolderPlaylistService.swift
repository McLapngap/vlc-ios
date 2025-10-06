/*****************************************************************************
 * FolderPlaylistService.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2024 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: AI Assistant
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import Foundation
import VLCMediaLibraryKit

/// Service that automatically creates playlists from folders in the document directory
/// 
/// This service monitors the document directory for new folders and automatically creates
/// playlists with the same name as the folder, containing all playable media files found
/// within that folder.
///
/// Features:
/// - Monitors folder creation in real-time
/// - Scans existing folders on startup
/// - Only creates playlists for folders containing playable media files
/// - Skips system folders and hidden folders
/// - Prevents duplicate playlist creation
class FolderPlaylistService: NSObject {
    
    // MARK: - Properties
    
    private let mediaLibraryService: MediaLibraryService
    private let fileManager = FileManager.default
    private var folderWatcher: FolderWatcher?
    private let documentPath: String
    
    // MARK: - Initialization
    
    init(mediaLibraryService: MediaLibraryService) {
        self.mediaLibraryService = mediaLibraryService
        
        guard let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            preconditionFailure("FolderPlaylistService: Unable to get document directory path.")
        }
        self.documentPath = documentPath
        
        super.init()
        setupFolderWatcher()
    }
    
    deinit {
        folderWatcher?.stopWatching()
    }
    
    // MARK: - Setup
    
    private func setupFolderWatcher() {
        folderWatcher = FolderWatcher(path: documentPath) { [weak self] folderPath in
            self?.handleFolderAdded(folderPath)
        }
        folderWatcher?.startWatching()
    }
    
    // MARK: - Folder Handling
    
    private func handleFolderAdded(_ folderPath: String) {
        // Get the folder name for the playlist
        let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        
        // Skip folders that shouldn't have playlists
        guard shouldProcessFolder(folderName: folderName, folderPath: folderPath) else {
            return
        }
        
        // Check if playlist already exists
        let existingPlaylists = mediaLibraryService.playlists()
        if existingPlaylists.contains(where: { $0.name == folderName }) {
            APLog("FolderPlaylistService: Playlist '\(folderName)' already exists, skipping")
            return
        }
        
        // Scan folder for playable media files
        let mediaFiles = scanFolderForMediaFiles(folderPath)
        
        // Only create playlist if there are playable media files
        guard !mediaFiles.isEmpty else {
            APLog("FolderPlaylistService: No playable media files found in folder '\(folderName)', skipping playlist creation")
            return
        }
        
        // Create playlist
        guard let playlist = mediaLibraryService.createPlaylist(with: folderName) else {
            assertionFailure("FolderPlaylistService: Failed to create playlist for folder: \(folderName)")
            return
        }
        
        // Add media files to playlist
        for mediaFile in mediaFiles {
            playlist.appendMedia(mediaFile)
        }
        
        APLog("FolderPlaylistService: Created playlist '\(folderName)' with \(mediaFiles.count) media files")
    }
    
    private func shouldProcessFolder(folderName: String, folderPath: String) -> Bool {
        // Skip empty folder names
        guard !folderName.isEmpty else {
            return false
        }
        
        // Skip system folders and hidden folders
        if folderName.hasPrefix(".") {
            return false
        }
        
        // Skip known system folders
        let systemFolders = ["Logs", "tmp", "temp", "cache", "Cache"]
        if systemFolders.contains(folderName) {
            return false
        }
        
        // Skip if folder doesn't exist or is not accessible
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        
        return true
    }
    
    private func scanFolderForMediaFiles(_ folderPath: String) -> [VLCMLMedia] {
        var mediaFiles: [VLCMLMedia] = []
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: folderPath)
            APLog("FolderPlaylistService: Scanning folder '\(URL(fileURLWithPath: folderPath).lastPathComponent)' with \(contents.count) items")
            
            for item in contents {
                let itemPath = URL(fileURLWithPath: folderPath).appendingPathComponent(item).path
                
                // Check if it's a file (not a subdirectory)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                      !isDirectory.boolValue else {
                    continue
                }
                
                // Check if it's a supported media format
                guard item.isSupportedMediaFormat || item.isSupportedAudioMediaFormat else {
                    continue
                }
                
                // Get or create media in the media library
                let fileURL = URL(fileURLWithPath: itemPath)
                if let media = mediaLibraryService.fetchMedia(with: fileURL) {
                    mediaFiles.append(media)
                    APLog("FolderPlaylistService: Found existing media: \(item)")
                } else {
                    // If media doesn't exist in library, add it
                    if let newMedia = mediaLibraryService.medialib.addExternalMedia(withMrl: fileURL) {
                        mediaFiles.append(newMedia)
                        APLog("FolderPlaylistService: Added new media to library: \(item)")
                    } else {
                        APLog("FolderPlaylistService: Failed to add media to library: \(item)")
                    }
                }
            }
        } catch {
            assertionFailure("FolderPlaylistService: Failed to scan folder \(folderPath): \(error.localizedDescription)")
        }
        
        APLog("FolderPlaylistService: Found \(mediaFiles.count) playable media files in folder '\(URL(fileURLWithPath: folderPath).lastPathComponent)'")
        return mediaFiles
    }
    
    /// Scans all existing folders in the document directory and creates playlists for them
    func scanExistingFolders() {
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: documentPath)
            APLog("FolderPlaylistService: Scanning \(contents.count) items in document directory for existing folders")
            
            for item in contents {
                let itemPath = URL(fileURLWithPath: documentPath).appendingPathComponent(item).path
                
                // Use the same validation logic as the folder watcher
                if shouldProcessFolder(folderName: item, folderPath: itemPath) {
                    handleFolderAdded(itemPath)
                }
            }
        } catch {
            assertionFailure("FolderPlaylistService: Failed to scan existing folders: \(error.localizedDescription)")
        }
    }
}

// MARK: - Folder Watcher

private class FolderWatcher {
    private let path: String
    private let callback: (String) -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var lastKnownFolders: Set<String> = []
    
    init(path: String, callback: @escaping (String) -> Void) {
        self.path = path
        self.callback = callback
    }
    
    func startWatching() {
        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            assertionFailure("FolderWatcher: Failed to open directory for watching")
            return
        }
        
        // Initialize with current folders
        updateKnownFolders()
        
        directorySource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )
        
        directorySource?.setEventHandler { [weak self] in
            self?.handleDirectoryChange()
        }
        
        directorySource?.setCancelHandler {
            close(fileDescriptor)
        }
        
        directorySource?.resume()
    }
    
    func stopWatching() {
        directorySource?.cancel()
        directorySource = nil
    }
    
    private func updateKnownFolders() {
        guard let currentContents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return
        }
        
        var currentFolders: Set<String> = []
        for item in currentContents {
            let itemPath = URL(fileURLWithPath: path).appendingPathComponent(item).path
            var isDirectory: ObjCBool = false
            
            if FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory),
               isDirectory.boolValue {
                currentFolders.insert(itemPath)
            }
        }
        
        lastKnownFolders = currentFolders
    }
    
    private func handleDirectoryChange() {
        // Get current directory contents
        guard let currentContents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return
        }
        
        var currentFolders: Set<String> = []
        for item in currentContents {
            let itemPath = URL(fileURLWithPath: path).appendingPathComponent(item).path
            var isDirectory: ObjCBool = false
            
            if FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory),
               isDirectory.boolValue {
                currentFolders.insert(itemPath)
            }
        }
        
        // Find new folders
        let newFolders = currentFolders.subtracting(lastKnownFolders)
        
        // Notify about new folders
        for folderPath in newFolders {
            DispatchQueue.main.async { [weak self] in
                self?.callback(folderPath)
            }
        }
        
        // Update known folders
        lastKnownFolders = currentFolders
    }
}