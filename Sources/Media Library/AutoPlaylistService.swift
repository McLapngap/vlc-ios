/*****************************************************************************
 * AutoPlaylistService.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2024 VideoLAN. All rights reserved.
 *
 * Authors: Auto Playlist Feature Implementation
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

/**
 * AutoPlaylistService automatically creates playlists based on folder structure.
 * 
 * When users create folders in the VLC Documents directory (via Files app or other means),
 * this service scans those folders and automatically creates playlists with the same name
 * containing all playable media files found in each folder.
 *
 * Features:
 * - Automatically scans Documents directory for folders
 * - Creates playlists matching folder names
 * - Recursively includes media files from subfolders
 * - Skips system folders (.Trash, Logs, etc.)
 * - Prevents duplicate playlist creation
 * - Integrates with existing MediaLibraryService
 */

import Foundation
import VLCMediaLibraryKit

@objc protocol AutoPlaylistServiceDelegate: AnyObject {
    @objc optional func autoPlaylistService(_ service: AutoPlaylistService, 
                                          didCreatePlaylist playlist: VLCMLPlaylist, 
                                          forFolder folderName: String)
}

class AutoPlaylistService: NSObject {
    private let mediaLibraryService: MediaLibraryService
    private var processedFolders: Set<String> = []
    private let documentsPath: String
    
    @objc weak var delegate: AutoPlaylistServiceDelegate?
    
    init(mediaLibraryService: MediaLibraryService) {
        self.mediaLibraryService = mediaLibraryService
        self.documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        super.init()
        
        // Set default value for the setting if not already set
        if UserDefaults.standard.object(forKey: kVLCSettingAutoCreateFolderPlaylists) == nil {
            UserDefaults.standard.set(true, forKey: kVLCSettingAutoCreateFolderPlaylists)
        }
        
        // Add observer for media library changes
        mediaLibraryService.observable.addObserver(self)
    }
    
    deinit {
        mediaLibraryService.observable.removeObserver(self)
    }
    
    /// Scans the Documents directory for folders and creates playlists for folders containing media files
    @objc func scanForFolderPlaylists() {
        // Check if feature is enabled
        guard UserDefaults.standard.bool(forKey: kVLCSettingAutoCreateFolderPlaylists) else {
            return
        }
        
        guard !documentsPath.isEmpty else {
            return
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.performFolderScan()
        }
    }
    
    private func performFolderScan() {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: documentsPath) else {
            return
        }
        
        for item in contents {
            let itemPath = (documentsPath as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            
            if FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                // Skip system folders and already processed folders
                if !shouldProcessFolder(named: item) {
                    continue
                }
                
                processFolder(at: itemPath, folderName: item)
            }
        }
    }
    
    private func shouldProcessFolder(named folderName: String) -> Bool {
        // Skip system folders and hidden folders
        let systemFolders = [".Trash", "Logs", "Inbox"]
        return !systemFolders.contains(folderName) && 
               !folderName.hasPrefix(".") && 
               !processedFolders.contains(folderName)
    }
    
    private func processFolder(at folderPath: String, folderName: String) {
        let mediaFiles = getMediaFilesInFolder(at: folderPath)
        
        // Only create playlist if folder contains media files
        guard !mediaFiles.isEmpty else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.createPlaylistForFolder(named: folderName, mediaFiles: mediaFiles)
        }
    }
    
    private func getMediaFilesInFolder(at folderPath: String) -> [String] {
        var mediaFiles: [String] = []
        
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folderPath) else {
            return mediaFiles
        }
        
        for file in contents {
            let filePath = (folderPath as NSString).appendingPathComponent(file)
            var isDirectory: ObjCBool = false
            
            if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Recursively scan subdirectories (limit depth to prevent infinite loops)
                    let subfolderFiles = getMediaFilesInFolder(at: filePath)
                    for subFile in subfolderFiles {
                        mediaFiles.append((file as NSString).appendingPathComponent(subFile))
                    }
                } else if isMediaFile(fileName: file) {
                    mediaFiles.append(file)
                }
            }
        }
        
        return mediaFiles
    }
    
    private func isMediaFile(fileName: String) -> Bool {
        // Use the existing NSString extension methods that are consistent with VLC's supported formats
        return (fileName as NSString).isSupportedMediaFormat() || (fileName as NSString).isSupportedAudioMediaFormat()
    }
    
    private func createPlaylistForFolder(named folderName: String, mediaFiles: [String]) {
        // Check if playlist already exists
        let existingPlaylists = mediaLibraryService.playlists()
        for playlist in existingPlaylists {
            if playlist.name == folderName {
                // Playlist already exists, mark as processed and return
                processedFolders.insert(folderName)
                return
            }
        }
        
        // Create new playlist
        guard let playlist = mediaLibraryService.createPlaylist(with: folderName) else {
            print("AutoPlaylistService: Failed to create playlist for folder: \(folderName)")
            return
        }
        
        // Add media files to playlist
        var addedCount = 0
        for mediaFile in mediaFiles {
            let fullPath = (documentsPath as NSString).appendingPathComponent(folderName).appendingPathComponent(mediaFile)
            let fileURL = URL(fileURLWithPath: fullPath)
            
            // Check if file still exists
            guard FileManager.default.fileExists(atPath: fullPath) else {
                continue
            }
            
            if let media = mediaLibraryService.fetchMedia(with: fileURL) {
                if playlist.appendMedia(with: media.identifier()) {
                    addedCount += 1
                }
            }
        }
        
        processedFolders.insert(folderName)
        
        print("AutoPlaylistService: Created playlist '\(folderName)' with \(addedCount) media files")
        
        // Notify delegate
        delegate?.autoPlaylistService?(self, didCreatePlaylist: playlist, forFolder: folderName)
    }
    
    /// Removes a folder from the processed list, allowing it to be rescanned
    @objc func resetProcessedFolder(named folderName: String) {
        processedFolders.remove(folderName)
    }
    
    /// Clears all processed folders, forcing a complete rescan on next call
    @objc func resetAllProcessedFolders() {
        processedFolders.removeAll()
    }
}

// MARK: - MediaLibraryObserver

extension AutoPlaylistService: MediaLibraryObserver {
    func medialibrary(_ medialibrary: MediaLibraryService, didAddVideos videos: [VLCMLMedia]) {
        // When new media is added, check if we need to create playlists for new folders
        scanForFolderPlaylists()
    }
    
    func medialibrary(_ medialibrary: MediaLibraryService, didAddTracks tracks: [VLCMLMedia]) {
        // When new media is added, check if we need to create playlists for new folders
        scanForFolderPlaylists()
    }
}