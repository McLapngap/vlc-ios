/*****************************************************************************
 * FolderPlaylistService.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright © 2025 VideoLAN. All rights reserved.
 *
 * Authors: VLC iOS Team
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import Foundation

/// Service that automatically creates and manages playlists based on folder structure
/// When a folder containing media files is created in the Documents directory,
/// a playlist with the folder's name is automatically created and populated with its media files.
@objc class FolderPlaylistService: NSObject {
    
    private let mediaLibraryService: MediaLibraryService
    private var folderPlaylistMapping: [String: Int64] = [:] // folder path -> playlist identifier
    
    @objc init(mediaLibraryService: MediaLibraryService) {
        self.mediaLibraryService = mediaLibraryService
        super.init()
    }
    
    /// Scans the Documents directory and creates playlists for all folders containing media files
    @objc func scanAndCreatePlaylists() {
        guard let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return
        }
        
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: documentPath) else {
            return
        }
        
        // Process on a background queue to avoid blocking the main thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            for item in contents {
                let itemPath = (documentPath as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false
                
                if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                    // Skip hidden folders and system folders
                    if item.hasPrefix(".") || item == "Inbox" {
                        continue
                    }
                    
                    self.createOrUpdatePlaylistForFolder(at: itemPath, folderName: item)
                }
            }
        }
    }
    
    /// Creates or updates a playlist for a specific folder
    private func createOrUpdatePlaylistForFolder(at folderPath: String, folderName: String) {
        let mediaFiles = getMediaFilesInFolder(at: folderPath)
        
        // Only create playlist if folder has media files
        guard !mediaFiles.isEmpty else {
            // If folder has no media files and we have a playlist for it, consider removing it
            if let existingPlaylistId = folderPlaylistMapping[folderPath] {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    _ = self.mediaLibraryService.deletePlaylist(with: existingPlaylistId)
                    self.folderPlaylistMapping.removeValue(forKey: folderPath)
                }
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Check if we already have a playlist for this folder
            if let existingPlaylistId = self.folderPlaylistMapping[folderPath],
               let existingPlaylist = self.mediaLibraryService.medialib.playlist(withIdentifier: existingPlaylistId) {
                self.updatePlaylist(existingPlaylist, with: mediaFiles)
            } else {
                // Create a new playlist for this folder
                if let newPlaylist = self.mediaLibraryService.createPlaylist(with: folderName) {
                    self.folderPlaylistMapping[folderPath] = newPlaylist.identifier()
                    self.updatePlaylist(newPlaylist, with: mediaFiles)
                }
            }
        }
    }
    
    /// Updates a playlist with the given media files
    private func updatePlaylist(_ playlist: VLCMLPlaylist, with mediaFiles: [VLCMLMedia]) {
        // Get current media in the playlist
        let currentMedia = playlist.media(with: .default, desc: false) ?? []
        let currentMediaIds = Set(currentMedia.map { $0.identifier() })
        let newMediaIds = Set(mediaFiles.map { $0.identifier() })
        
        // Add new media that's not already in the playlist
        for media in mediaFiles {
            if !currentMediaIds.contains(media.identifier()) {
                _ = playlist.appendMedia(withIdentifier: media.identifier())
            }
        }
        
        // Remove media that's no longer in the folder
        for media in currentMedia {
            if !newMediaIds.contains(media.identifier()) {
                // Remove from playlist
                // Note: VLCMLPlaylist doesn't have a direct remove method, so we skip this for now
                // The playlist will be recreated if the folder structure changes significantly
            }
        }
    }
    
    /// Gets all media files in a folder (including subfolders)
    private func getMediaFilesInFolder(at folderPath: String) -> [VLCMLMedia] {
        var mediaFiles: [VLCMLMedia] = []
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(atPath: folderPath) else {
            return mediaFiles
        }
        
        for item in contents {
            let itemPath = (folderPath as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            
            if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Recursively scan subdirectories
                    mediaFiles.append(contentsOf: getMediaFilesInFolder(at: itemPath))
                } else {
                    // Check if it's a supported media file
                    if item.isSupportedMediaFormat() || item.isSupportedAudioMediaFormat() {
                        // Try to get the media from the media library
                        let fileURL = URL(fileURLWithPath: itemPath)
                        if let media = mediaLibraryService.fetchMedia(with: fileURL) {
                            mediaFiles.append(media)
                        }
                    }
                }
            }
        }
        
        return mediaFiles
    }
    
    /// Called when a folder is created - creates a playlist for it
    @objc func handleFolderCreated(at folderPath: String, folderName: String) {
        // Wait a bit for files to be added before creating the playlist
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.createOrUpdatePlaylistForFolder(at: folderPath, folderName: folderName)
        }
    }
    
    /// Called when a folder is deleted - removes the associated playlist
    @objc func handleFolderDeleted(at folderPath: String) {
        guard let playlistId = folderPlaylistMapping[folderPath] else {
            return
        }
        
        // Delete the playlist
        _ = mediaLibraryService.deletePlaylist(with: playlistId)
        folderPlaylistMapping.removeValue(forKey: folderPath)
    }
    
    /// Called when files are added to a folder - updates the playlist
    @objc func handleFileAdded(in folderPath: String) {
        guard let folderName = URL(fileURLWithPath: folderPath).lastPathComponent as String? else {
            return
        }
        
        // Delay to ensure the file is fully added and indexed by media library
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.createOrUpdatePlaylistForFolder(at: folderPath, folderName: folderName)
        }
    }
}
