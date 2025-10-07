/*****************************************************************************
 * FolderPlaylistManager.swift
 * VLC for iOS
 *****************************************************************************
 * Copyright © 2024 VideoLAN. All rights reserved.
 *
 * Authors: Assistant AI
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import Foundation
import VLCMediaLibraryKit

/// Protocol for folder playlist manager delegate
@objc protocol FolderPlaylistManagerDelegate: AnyObject {
    func folderPlaylistManager(_ manager: FolderPlaylistManager, didCreatePlaylist playlist: VLCMLPlaylist, forFolder folderName: String)
    func folderPlaylistManager(_ manager: FolderPlaylistManager, didFailToCreatePlaylist error: Error, forFolder folderName: String)
}

/// Manager class that automatically creates playlists from folders in the Documents directory
class FolderPlaylistManager: NSObject {

    // MARK: - Properties

    private let mediaLibraryService: MediaLibraryService
    private let fileManager = FileManager.default
    private var folderMonitoringTimer: Timer?
    private var processedFolders = Set<String>()
    private weak var delegate: FolderPlaylistManagerDelegate?

    // MARK: - Initialization

    init(mediaLibraryService: MediaLibraryService, delegate: FolderPlaylistManagerDelegate? = nil) {
        self.mediaLibraryService = mediaLibraryService
        self.delegate = delegate
        super.init()
        startFolderMonitoring()
    }

    deinit {
        stopFolderMonitoring()
    }

    // MARK: - Public Methods

    /// Manually scan for new folders and create playlists
    func scanForNewFolders() {
        guard let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return
        }

        do {
            let folderNames = try fileManager.contentsOfDirectory(atPath: documentsPath)
                .filter { fileManager.directoryExists(atPath: documentsPath + "/" + $0) }
                .filter { !$0.hasPrefix(".") } // Skip hidden folders

            for folderName in folderNames {
                let folderPath = documentsPath + "/" + folderName
                if !processedFolders.contains(folderPath) {
                    createPlaylistFromFolder(at: folderPath, folderName: folderName)
                    processedFolders.insert(folderPath)
                }
            }
        } catch {
            APLog("FolderPlaylistManager: Error scanning for folders: \(error.localizedDescription)")
        }
    }

    /// Reset processed folders (useful for testing or after major changes)
    func resetProcessedFolders() {
        processedFolders.removeAll()
    }

    // MARK: - Private Methods

    private func startFolderMonitoring() {
        // Scan immediately
        scanForNewFolders()

        // Set up periodic scanning every 30 seconds
        folderMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.scanForNewFolders()
        }
    }

    private func stopFolderMonitoring() {
        folderMonitoringTimer?.invalidate()
        folderMonitoringTimer = nil
    }

    private func createPlaylistFromFolder(at folderPath: String, folderName: String) {
        do {
            // Get all files in the folder
            let files = try fileManager.contentsOfDirectory(atPath: folderPath)

            // Filter for playable media files
            var playableFiles = [String]()
            for file in files {
                let filePath = folderPath + "/" + file
                if !fileManager.directoryExists(atPath: filePath) &&
                   (file.isSupportedMediaFormat || file.isSupportedAudioMediaFormat) {
                    playableFiles.append(filePath)
                }
            }

            // Only create playlist if there are playable files
            guard !playableFiles.isEmpty else {
                APLog("FolderPlaylistManager: No playable files found in folder '\(folderName)'")
                return
            }

            // Create playlist
            guard let playlist = mediaLibraryService.createPlaylist(with: folderName) else {
                let error = NSError(domain: "FolderPlaylistManager",
                                  code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to create playlist"])
                delegate?.folderPlaylistManager(self, didFailToCreatePlaylist: error, forFolder: folderName)
                return
            }

            // Add files to playlist
            var successfullyAdded = 0
            for filePath in playableFiles {
                if let url = URL(string: "file://" + filePath),
                   let media = mediaLibraryService.medialib.media(withMrl: url) {
                    if playlist.appendMedia(media) {
                        successfullyAdded += 1
                    }
                }
            }

            APLog("FolderPlaylistManager: Created playlist '\(folderName)' with \(successfullyAdded)/\(playableFiles.count) files")

            delegate?.folderPlaylistManager(self, didCreatePlaylist: playlist, forFolder: folderName)

        } catch {
            APLog("FolderPlaylistManager: Error creating playlist for folder '\(folderName)': \(error.localizedDescription)")
            delegate?.folderPlaylistManager(self, didFailToCreatePlaylist: error, forFolder: folderName)
        }
    }
}

// MARK: - FileManager Extension

private extension FileManager {
    func directoryExists(atPath path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

// MARK: - NSString Extension

private extension NSString {
    var isSupportedMediaFormat: Bool {
        return (self as String).isSupportedMediaFormat
    }

    var isSupportedAudioMediaFormat: Bool {
        return (self as String).isSupportedAudioMediaFormat
    }
}

// MARK: - String Extension

private extension String {
    var isSupportedMediaFormat: Bool {
        let supportedVideoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "3gp", "3g2", "f4v", "asf", "rm", "rmvb", "vob", "ogv", "dv", "ts", "mts", "m2ts"]
        let supportedAudioExtensions = ["mp3", "m4a", "aac", "flac", "ogg", "wma", "wav", "aiff", "au", "ra", "ape", "opus"]

        let pathExtension = (self as NSString).pathExtension.lowercased()
        return supportedVideoExtensions.contains(pathExtension) || supportedAudioExtensions.contains(pathExtension)
    }

    var isSupportedAudioMediaFormat: Bool {
        let supportedAudioExtensions = ["mp3", "m4a", "aac", "flac", "ogg", "wma", "wav", "aiff", "au", "ra", "ape", "opus"]
        let pathExtension = (self as NSString).pathExtension.lowercased()
        return supportedAudioExtensions.contains(pathExtension)
    }
}